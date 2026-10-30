#!/usr/bin/env bash
# The load sweep: one http_load run per target, each against a server
# started for it alone, with the results of every target in its own
# files under the output directory.
#
#   tool/sweep/sweep.sh                 # all targets, laptop defaults
#   QUIET=0 PAUSE=5 tool/sweep/sweep.sh # an instance that runs nothing else
#   ONLY='hyper relic-native' tool/sweep/sweep.sh
#
# QUIET=1 waits for a one-minute load average under 1.5 before every
# target, up to 15 minutes. PAUSE is the seconds after a target. OUT is
# the output directory, sweep-out beside this package by default. LOAD
# is the http_load argument list. The baselines must be built first, see
# the comments at the top of baselines/*/.
set -u
R=$(cd "$(dirname "$0")/../.." && pwd)
C=$R/../relic_native/test/certs
export RELIC_TEST_CERTS=$C
N=${OUT:-$R/sweep-out}
mkdir -p "$N"
LOAD=${LOAD:-"--workloads=plaintext,headers,browser --connections=64 --seconds=5 --loads=0.5,0.75,0.9,0.95,1.0 --saturation-runs=5"}
QUIET=${QUIET:-1}
PAUSE=${PAUSE:-60}
ONLY=${ONLY:-}

loadavg() {
  if [[ -r /proc/loadavg ]]; then cut -d' ' -f1 /proc/loadavg
  else sysctl -n vm.loadavg | awk '{print $2}'; fi
}
quiet() {
  (( QUIET )) || return 0
  for _ in $(seq 1 90); do
    if awk -v l="$(loadavg)" 'BEGIN { exit !(l < 1.5) }'; then return 0; fi
    sleep 10
  done
}
up() {
  for _ in $(seq 1 180); do curl -sk -o /dev/null "$1" && return 0; sleep 1; done
  echo "$1 not up"
}
listeners() {
  if command -v lsof >/dev/null; then lsof -nP -iTCP:"$1" -sTCP:LISTEN -t 2>/dev/null
  else ss -ltnpH "sport = :$1" 2>/dev/null | grep -o 'pid=[0-9]*' | cut -d= -f2; fi
}
wanted() {
  [[ -z $ONLY ]] && return 0
  for w in $ONLY; do [[ $w == "$1" ]] && return 0; done
  return 1
}
# scenario <name> <target-spec> [http_load args] -- [server command...]
scenario() {
  local name=$1 spec=$2; shift 2
  wanted "$name" || return 0
  local extra=""
  while [[ $# -gt 0 && $1 != "--" ]]; do extra="$extra $1"; shift; done
  [[ $# -gt 0 ]] && shift
  quiet
  local pid="" url=""
  if [[ $# -gt 0 ]]; then
    nohup "$@" > "$N/$name.server.log" 2>&1 &
    pid=$!
    url=${spec#*=}
    up "$url/plaintext"
  fi
  # shellcheck disable=SC2086
  (cd "$R" && dart run bin/http_load.dart $extra --targets="$spec" $LOAD --out="$N/$name.md" > "$N/$name.out" 2> "$N/$name.err")
  echo "$name exit $?" >> "$N/progress.log"
  if [[ -n $pid ]]; then
    pkill -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null
    local port=${url##*:}
    for _ in $(seq 1 10); do
      local left; left=$(listeners "$port")
      [[ -z $left ]] && break
      # shellcheck disable=SC2086
      kill $left 2>/dev/null; sleep 1
    done
  fi
  sleep "$PAUSE"
}

{
  echo "machine: $(uname -a)"
  if [[ -r /proc/cpuinfo ]]; then grep -m1 'model name' /proc/cpuinfo; echo "cores: $(nproc)"
  else echo "cpu: $(sysctl -n machdep.cpu.brand_string), cores: $(sysctl -n hw.physicalcpu)"; fi
  echo "dart: $(dart --version 2>&1)"
  echo "oha: $(oha --version 2>&1)"
  echo "zig: $(cd "$R/../relic_native" && zig version 2>&1)"
  echo "rustc: $(rustc --version 2>&1)"
  echo "deno: $(deno --version 2>&1 | head -1)"
  echo "load: $LOAD"
} > "$N/machine.txt"

(cd "$R" && dart build cli --target bin/load_serve.dart > "$N/aot_build.log" 2>&1)
B=$(ls "$R"/build/cli/*/bundle/bin/load_serve | head -1)
H=$R/baselines/hyper/target/release/relic_baseline_hyper
Z=$R/baselines/dusty/zig-out/bin/relic_baseline_dusty
echo "start $(date)" >> "$N/progress.log"
# HTTP
scenario hyper hyper=http://127.0.0.1:8090 -- "$H" 8090 1
scenario hyper4 hyper4=http://127.0.0.1:8089 -- "$H" 8089 4
scenario deno deno=http://127.0.0.1:8092 -- deno run --allow-net "$R/baselines/deno/server.mjs" 8092
scenario dusty dusty=http://127.0.0.1:8093 -- "$Z" 8093 1
scenario dusty4 dusty4=http://127.0.0.1:8098 -- "$Z" 8098 4
scenario relic-native-aot relic-native-aot=http://127.0.0.1:18101 -- "$B" native 1 notls 18101
scenario relic-native-handler-aot relic-native-handler-aot=http://127.0.0.1:18102 -- "$B" native-handler 1 notls 18102
scenario relic-native4-aot relic-native4-aot=http://127.0.0.1:18103 -- "$B" native 4 notls 18103
scenario relic-io-aot relic-io-aot=http://127.0.0.1:18104 -- "$B" io 1 notls 18104
scenario relic-io relic-io=io
scenario relic-io-handler relic-io-handler=io-handler
scenario relic-native relic-native=native
scenario relic-native-handler relic-native-handler=native-handler
scenario relic-native4 relic-native4=native4
scenario relic-native4-handler relic-native4-handler=native4-handler
scenario shelf shelf=shelf
scenario shelf4 shelf4=shelf4
# HTTPS
scenario hyper-tls hyper-tls=https://127.0.0.1:8490 -- "$H" 8490 1 "$C/localhost_cert.pem" "$C/localhost_key.pem"
scenario hyper4-tls hyper4-tls=https://127.0.0.1:8489 -- "$H" 8489 4 "$C/localhost_cert.pem" "$C/localhost_key.pem"
scenario deno-tls deno-tls=https://127.0.0.1:8492 -- deno run --allow-net --allow-read "$R/baselines/deno/server.mjs" 8492 "$C/localhost_cert.pem" "$C/localhost_key.pem"
scenario dusty-tls dusty-tls=https://127.0.0.1:8493 -- "$Z" 8493 1 "$C/localhost_cert.pem" "$C/localhost_key.pem"
scenario dusty4-tls dusty4-tls=https://127.0.0.1:8498 -- "$Z" 8498 4 "$C/localhost_cert.pem" "$C/localhost_key.pem"
scenario relic-io-tls relic-io-tls=io --tls
scenario relic-native-tls relic-native-tls=native --tls
scenario relic-native-handler-tls relic-native-handler-tls=native-handler --tls
scenario relic-native4-tls relic-native4-tls=native4 --tls
scenario relic-native4-handler-tls relic-native4-handler-tls=native4-handler --tls
scenario shelf-tls shelf-tls=shelf --tls
scenario shelf4-tls shelf4-tls=shelf4 --tls
# two-way
scenario hyper2 hyper2=http://127.0.0.1:8190 -- "$H" 8190 2
scenario dusty2 dusty2=http://127.0.0.1:8193 -- "$Z" 8193 2
scenario relic-native2-aot relic-native2-aot=http://127.0.0.1:18201 -- "$B" native 2 notls 18201
scenario relic-native2 relic-native2=native2
scenario relic-native2-handler relic-native2-handler=native2-handler
scenario shelf2 shelf2=shelf2
scenario hyper2-tls hyper2-tls=https://127.0.0.1:8590 -- "$H" 8590 2 "$C/localhost_cert.pem" "$C/localhost_key.pem"
scenario dusty2-tls dusty2-tls=https://127.0.0.1:8593 -- "$Z" 8593 2 "$C/localhost_cert.pem" "$C/localhost_key.pem"
scenario relic-native2-tls relic-native2-tls=native2 --tls
scenario relic-native2-handler-tls relic-native2-handler-tls=native2-handler --tls
scenario shelf2-tls shelf2-tls=shelf2 --tls
scenario relic-io2 relic-io2=io2
scenario relic-io4 relic-io4=io4
scenario relic-io2-tls relic-io2-tls=io2 --tls
scenario relic-io4-tls relic-io4-tls=io4 --tls
scenario relic-native-aot-tls relic-native-aot-tls=https://127.0.0.1:18501 -- "$B" native 1 tls 18501
scenario relic-native-handler-aot-tls relic-native-handler-aot-tls=https://127.0.0.1:18502 -- "$B" native-handler 1 tls 18502
scenario relic-native2-aot-tls relic-native2-aot-tls=https://127.0.0.1:18503 -- "$B" native 2 tls 18503
scenario relic-native4-aot-tls relic-native4-aot-tls=https://127.0.0.1:18504 -- "$B" native 4 tls 18504
scenario relic-io-aot-tls relic-io-aot-tls=https://127.0.0.1:18505 -- "$B" io 1 tls 18505
echo "done $(date)" >> "$N/progress.log"
