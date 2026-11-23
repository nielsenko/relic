#!/usr/bin/env bash
# Startup script for a GCP instance that runs the sweep once, copies the
# results to a bucket and shuts itself down. bench gcp create passes it to
# a new instance. It is a shell script since it runs before the instance
# has Dart. Ubuntu 24.04 on x86-64 or arm64. Instance metadata attributes,
# all optional:
#   relic-repo    the git URL to clone, nielsenko/relic by default
#   relic-branch  the branch to sweep, chore-benchmark-sweep by default
#   relic-patch   a patch to apply to the clone, none by default
#   relic-bucket  the bucket for the results, relic-bench-nights by default
#   sweep-env     environment for the sweep, "QUIET=0 PAUSE=5 LOAD_THREADS=8 NET=veth"
#                 by default
#   sweep-only    a space-separated list of targets, all by default
#   sweep-script  the steps to run in packages/benchmark, separated by
#                 spaces, "sweep kernel micro" by default. sweep and kernel
#                 are commands of bin/bench.dart, kernel writing into
#                 kernel/ of the results, micro runs the micro
#                 benchmarks through bench_press, JIT and AOT, pinned to
#                 CPU 2, into micro/ of the results
#   dart-sdks     the Dart SDK versions to install, "3.14.1" by default. The
#                 first one runs the tools. With more than one, the sweep
#                 runs every Dart target on each of them
#   keep          1 leaves the instance running after the sweep
#   require-pmu   1 stops the sweep at once when it gets no hardware
#                 counters, 0 by default
# Progress is in the serial console and /var/log/relic-sweep.log.
# Any failure uploads that log to the bucket as failed-<date>-<type>.log
# and shuts down, as a finished sweep does, unless keep is 1. A restart
# after a finished sweep only shuts down again, a restart after a failed
# one repeats it. The instance's service account needs only
# roles/storage.objectCreator on the bucket.
set -euo pipefail
exec > >(tee -a /var/log/relic-sweep.log) 2>&1
md() {
  curl -sf -H 'Metadata-Flavor: Google' \
    "http://metadata.google.internal/computeMetadata/v1/instance/attributes/$1" || echo "${2:-}"
}
REPO=$(md relic-repo https://github.com/nielsenko/relic.git)
BRANCH=$(md relic-branch chore-benchmark-sweep)
PATCH=$(md relic-patch "")
BUCKET=$(md relic-bucket relic-bench-nights)
ENVS=$(md sweep-env "QUIET=0 PAUSE=5 LOAD_THREADS=8 NET=veth")
ONLY=$(md sweep-only "")
SCRIPT=$(md sweep-script "sweep kernel micro")
DARTS=$(md dart-sdks 3.14.1)
KEEP=$(md keep 0)
REQUIRE_PMU=$(md require-pmu 0)
NAME=$(curl -sf -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/name)
TYPE=$(curl -sf -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/machine-type | sed 's#.*/##')
upload() {
  local token
  token=$(curl -sf -H 'Metadata-Flavor: Google' \
    http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token |
    python3 -c 'import json, sys; print(json.load(sys.stdin)["access_token"])')
  curl -sf -o /dev/null -X POST -H "Authorization: Bearer $token" \
    -H 'Content-Type: application/octet-stream' --data-binary @"$1" \
    "https://storage.googleapis.com/upload/storage/v1/b/$BUCKET/o?uploadType=media&name=$2"
}
finish() {
  local rc=$?
  trap - EXIT
  if (( rc )); then
    echo "=== failed with $rc $(date)"
    upload /var/log/relic-sweep.log "failed-$(date -u +%Y%m%d-%H%M)-$TYPE.log" || true
  fi
  if [[ $KEEP != 1 ]]; then
    echo "=== shutdown $(date)"
    shutdown -h now
  fi
}
trap finish EXIT
DONE=/var/lib/relic-sweep.done
if [[ -e $DONE ]]; then
  echo "=== sweep already finished, remove $DONE to repeat it"
  exit 0
fi
ARCH=$(uname -m)
case $ARCH in
  x86_64) DART_ARCH=x64 ;;
  aarch64) DART_ARCH=arm64 ;;
  *) echo "unsupported arch $ARCH"; exit 1 ;;
esac

echo "=== toolchains $(date)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q build-essential pkg-config unzip git curl ca-certificates psmisc strace rsync ethtool iputils-ping
apt-get install -y -q linux-tools-common "linux-tools-$(uname -r)" || echo "perf not available for this kernel"
SDKS=""
for v in $DARTS; do
  curl -fsSL -o /tmp/dart.zip "https://storage.googleapis.com/dart-archive/channels/stable/release/$v/sdk/dartsdk-linux-$DART_ARCH-release.zip"
  rm -rf /tmp/dart-sdk "/opt/dart-$v"
  unzip -q /tmp/dart.zip -d /tmp && mv /tmp/dart-sdk "/opt/dart-$v"
  SDKS="$SDKS $v=/opt/dart-$v"
done
rm -f /tmp/dart.zip
DART=/opt/dart-${DARTS%% *}/bin
# One SDK runs the sweep as before, with no copies of the repository.
[[ $DARTS == *" "* ]] || SDKS=""
curl -sSL "https://github.com/marler8997/anyzig/releases/download/v2026_10_23/anyzig-${ARCH}-linux.tar.gz" | tar xz -C /usr/local/bin zig
# zrk, the load tool, checked against the release's SHA256SUMS.
ZRK=zrk-3.0.5-${ARCH}-linux.tar.gz
curl -fsSL -o "/tmp/$ZRK" "https://github.com/zoxy-io/zrk/releases/download/v3.0.5/$ZRK"
curl -fsSL -o /tmp/zrk.sums https://github.com/zoxy-io/zrk/releases/download/v3.0.5/SHA256SUMS.txt
(cd /tmp && grep " $ZRK\$" zrk.sums | sha256sum -c -)
tar -xzf "/tmp/$ZRK" -C /usr/local/bin zrk
curl -fsSL https://deno.land/install.sh | DENO_INSTALL=/usr/local sh -s v2.9.8
curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr/local bash -s bun-v1.4.5
id bench >/dev/null 2>&1 || useradd -m -s /bin/bash bench
# The kernel run counts the system calls of the servers it starts,
# with perf as root and with strace attached as bench. With NET=veth the
# sweep makes network namespaces and runs every server and load tool in
# one through sudo, which can run anything as root, so bench may.
printf 'bench ALL=(root) NOPASSWD: ALL\n' > /etc/sudoers.d/bench
chmod 440 /etc/sudoers.d/bench
sysctl -w kernel.yama.ptrace_scope=0
# http_load and cpu_bench read the instructions and cycles of the servers
# as bench, in user and kernel mode. They need an instance created with
# PMU set, see bench gcp create.
sysctl -w kernel.perf_event_paranoid=1
# The postgres behind /db in the async pass. The sweep starts it with
# pg_ctl where the load tools run and stops it after the pass, so the
# packaged service stays off. Password postgres, reachable from the veth
# network and the loopback.
apt-get install -y -q postgresql
systemctl disable --now postgresql || true
PG_BIN=$(ls -d /usr/lib/postgresql/*/bin | sort -V | tail -1)
PG_DATA=/var/lib/relic-pg
if [[ ! -d $PG_DATA ]]; then
  install -d -o postgres -g postgres -m 700 "$PG_DATA"
  printf 'postgres\n' > /tmp/pgpass && chown postgres /tmp/pgpass
  sudo -u postgres "$PG_BIN/initdb" -D "$PG_DATA" -U postgres --pwfile=/tmp/pgpass --auth-host=scram-sha-256 >/dev/null
  rm -f /tmp/pgpass
  printf 'host all all 10.77.0.0/24 scram-sha-256\n' >> "$PG_DATA/pg_hba.conf"
fi

echo "=== clone and build $(date)"
if [[ -n $PATCH ]]; then printf '%s\n' "$PATCH" > /tmp/relic.patch; else : > /tmp/relic.patch; fi
chmod 644 /tmp/relic.patch
su - bench <<BENCH
set -euo pipefail
export PATH=\$HOME/.cargo/bin:$DART:\$PATH
curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain 1.100.0 >/dev/null
rm -rf relic && git clone --quiet --branch '$BRANCH' --depth 1 '$REPO' relic
cd relic
if [[ -s /tmp/relic.patch ]]; then git apply /tmp/relic.patch; fi
(cd packages/benchmark && dart pub get)
# anyzig fetches the compiler on first use, with no timeout of its own.
(cd packages/relic_native && for i in 1 2 3; do timeout 300 zig version && break; [[ \$i -lt 3 ]] || exit 1; done)
(cd packages/benchmark/baselines/hyper && cargo build --release --quiet)
(cd packages/benchmark/baselines/tungstenite && cargo build --release --quiet)
(cd packages/benchmark/baselines/dusty && zig build --release)
BENCH

OUT=/home/bench/sweep-out
for STEP in $SCRIPT; do
  echo "=== $STEP $(date)"
  case $STEP in
    micro)
      su - bench -c "export PATH=\$HOME/.cargo/bin:$DART:\$PATH; mkdir -p $OUT/micro; cd relic/packages/benchmark && for t in jit aot; do dart run bench_press run -t \$t --pin-cpu=2 --save $OUT/micro/\$t.json benchmark/ > $OUT/micro/\$t.md 2>&1 || echo micro \$t exited \$?; done" || echo "micro exited $?"
      ;;
    *)
      DIR=$OUT
      [[ $STEP == kernel ]] && DIR=$OUT/kernel
      su - bench -c "export PATH=\$HOME/.cargo/bin:$DART:\$PATH; cd relic/packages/benchmark && env REQUIRE_PMU=$REQUIRE_PMU PG_CTL=$PG_BIN/pg_ctl PG_DATA=$PG_DATA $ENVS DART_SDKS='${SDKS# }' ONLY='$ONLY' OUT=$DIR dart run bin/bench.dart $STEP" || echo "$STEP exited $?"
      ;;
  esac
done
mkdir -p "$OUT"
{
  echo "instance: $NAME $TYPE"
  echo "relic: $BRANCH $(su - bench -c 'git -C relic log -1 --format=%h')"
  echo "image: $(. /etc/os-release && echo "$PRETTY_NAME")"
  echo "kernel: $(uname -r)"
  echo "smt: $(cat /sys/devices/system/cpu/smt/control 2>/dev/null || echo unknown)"
  echo "governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo none)"
  echo "io_uring_disabled: $(sysctl -n kernel.io_uring_disabled 2>/dev/null || echo unknown)"
} >> "$OUT/machine.txt"
cp /var/log/relic-sweep.log "$OUT/"

echo "=== upload $(date)"
RUN=$(date -u +%Y%m%d-%H%M)-$TYPE
cd "$OUT"
# zrk's own reports, a few per run, go up as one archive.
find . -type d -name '*.zrk' -print0 | tar -czf zrk.tar.gz --null -T - --remove-files
find . -type f | sed 's#^\./##' | while read -r f; do upload "$f" "$RUN/$f"; done
echo "results in gs://$BUCKET/$RUN/"
touch "$DONE"
