#!/usr/bin/env bash
# The kernel's share of a request. For each server, on one isolate or
# thread, and for the plaintext and headers workloads, the run reads the
# server's user and system time from /proc over a load window. It then
# counts the server's system calls by name over two more windows, one
# with perf's syscall tracepoints and one with strace, each when it may.
# Where the VM has a PMU, one more window counts instructions and cycles
# in user and kernel mode. Linux only.
#
#   tool/sweep/kernel.sh
#   ONLY='dartio relic-native' WINDOW=5 tool/sweep/kernel.sh
#
# WINDOW is the seconds of each load window, 10 by default. OUT is the
# output directory, kernel-out beside this package by default. The
# baselines must be built first, as for sweep.sh. perf runs through sudo
# -n when sudo allows it, and strace attaches as the user, which takes
# kernel.yama.ptrace_scope 0. The GCP startup script arranges both.
# kernel_rows.py turns the results into kernel.md.
set -u
R=$(cd "$(dirname "$0")/../.." && pwd)
N=${OUT:-$R/kernel-out}
mkdir -p "$N"
WINDOW=${WINDOW:-10}
OHA_THREADS=${OHA_THREADS:-4}
ONLY=${ONLY:-}
PORT=18098
URL=http://127.0.0.1:$PORT
# perf opens one descriptor per event and thread.
ulimit -n 65536 2> /dev/null || ulimit -n "$(ulimit -Hn)"
SUDO=()
sudo -n perf --version > /dev/null 2>&1 && SUDO=(sudo -n)

H=$R/baselines/hyper/target/release/relic_baseline_hyper
Z=$R/baselines/dusty/zig-out/bin/relic_baseline_dusty
O=$R/baselines/relic_1_2
(cd "$O" && dart pub get > "$N/relic_1_2_pub.log" 2>&1)

# The browser head of lib/src/browser_headers.dart, as oha arguments.
BH=()
while IFS= read -r h; do BH+=(-H "$h"); done < <(python3 -I -c '
import ast, re, sys
src = open(sys.argv[1]).read()
body = re.search(r"const browserHeaders = \[(.*?)\];", src, re.S).group(1)
print("\n".join(ast.literal_eval("[" + body + "]")))
' "$R/lib/src/browser_headers.dart")

{
  echo "machine: $(uname -a)"
  grep -m1 'model name' /proc/cpuinfo
  echo "cores: $(nproc)"
  echo "dart: $(dart --version 2>&1)"
  echo "oha: $(oha --version 2>&1)"
  echo "perf: $("${SUDO[@]}" perf --version 2>&1 | head -1)"
  echo "strace: $(strace -V 2>&1 | head -1)"
  echo "clock ticks: $(getconf CLK_TCK)"
  echo "window: $WINDOW"
  echo "load: oha, 64 connections, $OHA_THREADS threads, ${#BH[@]} header arguments for headers"
  echo "ptrace_scope: $(cat /proc/sys/kernel/yama/ptrace_scope 2> /dev/null)"
  echo "perf_event_paranoid: $(cat /proc/sys/kernel/perf_event_paranoid 2> /dev/null)"
  echo "io_uring_disabled: $(cat /proc/sys/kernel/io_uring_disabled 2> /dev/null)"
} > "$N/machine.txt"

wanted() {
  [[ -z $ONLY ]] && return 0
  for w in $ONLY; do [[ $w == "$1" ]] && return 0; done
  return 1
}
up() {
  for _ in $(seq 1 600); do curl -s -o /dev/null "$URL/plaintext" && return 0; sleep 1; done
  return 1
}
listener() {
  ss -ltnpH "sport = :$PORT" 2> /dev/null | grep -o 'pid=[0-9]*' | head -1 | cut -d= -f2
}
# The user and system clock ticks of a process, its threads included.
ticks() {
  sed 's/.*) //' "/proc/$1/stat" | awk '{print $12, $13}'
}
# oha <route> <seconds>: the oha command for one window, in OHA.
oha_for() {
  OHA=(oha --no-tui --output-format json -c 64 -z "$2s" --worker-threads "$OHA_THREADS")
  [[ $1 == headers ]] && OHA+=("${BH[@]}")
  OHA+=("$URL/$1")
}
# What perf counts: every system call together, and the ones a server
# makes per request by name, those this kernel has. All of
# syscalls:sys_enter_* would be a descriptor per event and thread.
CALLS='read write readv writev recvfrom sendto recvmsg sendmsg epoll_wait
epoll_pwait epoll_pwait2 epoll_ctl io_uring_enter futex ioctl mmap munmap
madvise mprotect nanosleep clock_nanosleep sched_yield poll ppoll accept4
close fcntl getsockopt setsockopt shutdown'
EVENTS=raw_syscalls:sys_enter
AVAILABLE=$("${SUDO[@]}" perf list 'syscalls:sys_enter_*' 2> /dev/null | grep -o 'syscalls:sys_enter_[a-z0-9_]*')
for c in $CALLS; do
  grep -qx "syscalls:sys_enter_$c" <<< "$AVAILABLE" && EVENTS="$EVENTS,syscalls:sys_enter_$c"
done
echo "perf events: $EVENTS" >> "$N/machine.txt"
perf_ok() {
  "${SUDO[@]}" perf stat -e "$EVENTS" -- true > /dev/null 2>&1
}
# Instructions and cycles need a PMU in the VM. On GCP that is C4, C4A
# and M4 created with --performance-monitoring-unit, and not C4D.
COUNTERS=instructions:u,instructions:k,cycles:u,cycles:k
COUNTED=0
"${SUDO[@]}" perf stat -x, -e "$COUNTERS" -- true 2>&1 | grep -Eq '^[0-9]+,[^,]*,instructions:k' && COUNTED=1
echo "counters: $COUNTED" >> "$N/machine.txt"
stop() {
  pkill -P "$1" 2> /dev/null
  kill "$1" 2> /dev/null
  for _ in $(seq 1 10); do
    local left
    left=$(listener)
    [[ -z $left ]] && break
    # shellcheck disable=SC2086
    kill $left 2> /dev/null
    sleep 1
  done
  sleep 2
}

# server <name> <command...> measures both workloads on one server.
server() {
  local name=$1
  shift
  wanted "$name" || return 0
  (cd "$R" && exec nohup "$@") > "$N/$name.server.log" 2>&1 &
  local launcher=$!
  if ! up; then
    echo "$name not up" >> "$N/progress.log"
    stop "$launcher"
    return
  fi
  local pid
  pid=$(listener)
  for route in plaintext headers; do
    oha_for "$route" 5
    "${OHA[@]}" > /dev/null
    local before after
    before=$(ticks "$pid")
    oha_for "$route" "$WINDOW"
    "${OHA[@]}" > "$N/$name.$route.time.json"
    after=$(ticks "$pid")
    echo "$name $route $pid $before $after" >> "$N/ticks.txt"
    if ((COUNTED)); then
      "${SUDO[@]}" perf stat --per-thread -x, -e "$COUNTERS" -p "$pid" \
        -o "$N/$name.$route.counters.csv" -- "${OHA[@]}" \
        > "$N/$name.$route.counters.json" 2> "$N/$name.$route.counters.err"
    fi
    if perf_ok; then
      "${SUDO[@]}" perf stat --per-thread -x, -e "$EVENTS" -p "$pid" \
        -o "$N/$name.$route.perf.csv" -- "${OHA[@]}" \
        > "$N/$name.$route.perf.json" 2> "$N/$name.$route.perf.err"
    fi
    if command -v strace > /dev/null; then
      strace -f -c -q -p "$pid" -o "$N/$name.$route.strace.txt" \
        2> "$N/$name.$route.strace.err" &
      local tracer=$!
      sleep 2
      "${OHA[@]}" > "$N/$name.$route.strace.json"
      kill -INT "$tracer" 2> /dev/null
      wait "$tracer"
    fi
  done
  echo "$name done $(date)" >> "$N/progress.log"
  stop "$launcher"
}

server dartio dart baselines/dartio/server.dart "$PORT"
server relic12-io dart --packages="$O/.dart_tool/package_config.json" "$O/bin/server.dart" "$PORT" 1
server relic-io dart run bin/load_serve.dart io 1
server shelf dart run bin/load_serve.dart shelf 1
server relic-native dart run bin/load_serve.dart native 1
server hyper "$H" "$PORT" 1
server dusty "$Z" "$PORT" 1
python3 -I "$R/tool/sweep/kernel_rows.py" "$N" > "$N/kernel.md" 2> "$N/kernel_rows.err"
echo "done $(date)" >> "$N/progress.log"
