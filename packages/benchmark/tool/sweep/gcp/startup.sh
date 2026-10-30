#!/usr/bin/env bash
# Startup script for a GCP instance that runs the sweep once, copies the
# results to a bucket and shuts itself down. Ubuntu 24.04 on x86-64 or
# arm64. Instance metadata attributes, all optional:
#   relic-repo    the git URL to clone, nielsenko/relic by default
#   relic-branch  the branch to sweep, chore-benchmark-sweep by default
#   relic-patch   a patch to apply to the clone, none by default
#   relic-bucket  the bucket for the results, relic-bench-nights by default
#   sweep-env     environment for sweep.sh, "QUIET=0 PAUSE=5" by default
#   sweep-only    a space-separated list of targets, all by default
#   keep          1 leaves the instance running after the sweep
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
ENVS=$(md sweep-env "QUIET=0 PAUSE=5")
ONLY=$(md sweep-only "")
KEEP=$(md keep 0)
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
  x86_64) OHA_ARCH=amd64 ;;
  aarch64) OHA_ARCH=arm64 ;;
  *) echo "unsupported arch $ARCH"; exit 1 ;;
esac

echo "=== toolchains $(date)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q build-essential pkg-config unzip git curl ca-certificates gnupg psmisc
apt-get install -y -q linux-tools-common "linux-tools-$(uname -r)" || echo "perf not available for this kernel"
curl -fsSL https://dl-ssl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/dart.gpg
echo 'deb [signed-by=/usr/share/keyrings/dart.gpg arch=amd64,arm64] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main' > /etc/apt/sources.list.d/dart_stable.list
apt-get update -q && apt-get install -y -q dart
curl -sSL "https://github.com/marler8997/anyzig/releases/download/v2026_10_23/anyzig-${ARCH}-linux.tar.gz" | tar xz -C /usr/local/bin zig
curl -sSL -o /usr/local/bin/oha "https://github.com/hatoo/oha/releases/download/v1.16.0/oha-linux-${OHA_ARCH}" && chmod +x /usr/local/bin/oha
curl -fsSL https://deno.land/install.sh | DENO_INSTALL=/usr/local sh -s v2.9.6
id bench >/dev/null 2>&1 || useradd -m -s /bin/bash bench

echo "=== clone and build $(date)"
if [[ -n $PATCH ]]; then printf '%s\n' "$PATCH" > /tmp/relic.patch; else : > /tmp/relic.patch; fi
chmod 644 /tmp/relic.patch
su - bench <<BENCH
set -euo pipefail
export PATH=\$HOME/.cargo/bin:/usr/lib/dart/bin:\$PATH
curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain 1.99.1 >/dev/null
rm -rf relic && git clone --quiet --branch '$BRANCH' --depth 1 '$REPO' relic
cd relic
if [[ -s /tmp/relic.patch ]]; then git apply /tmp/relic.patch; fi
dart pub get
(cd packages/relic_native && zig version)
(cd packages/benchmark/baselines/hyper && cargo build --release --quiet)
(cd packages/benchmark/baselines/dusty && zig build --release)
BENCH

echo "=== sweep $(date)"
OUT=/home/bench/sweep-out
su - bench -c "export PATH=\$HOME/.cargo/bin:/usr/lib/dart/bin:\$PATH; cd relic/packages/benchmark && env $ENVS ONLY='$ONLY' OUT=$OUT tool/sweep/sweep.sh" || echo "sweep exited $?"
{
  echo "instance: $NAME $TYPE"
  echo "image: $(. /etc/os-release && echo "$PRETTY_NAME")"
  echo "kernel: $(uname -r)"
  echo "smt: $(cat /sys/devices/system/cpu/smt/control 2>/dev/null || echo unknown)"
  echo "governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo none)"
} >> "$OUT/machine.txt"
cp /var/log/relic-sweep.log "$OUT/"

echo "=== upload $(date)"
RUN=$(date -u +%Y%m%d-%H%M)-$TYPE
cd "$OUT"
find . -type f | sed 's#^\./##' | while read -r f; do upload "$f" "$RUN/$f"; done
echo "results in gs://$BUCKET/$RUN/"
touch "$DONE"
