# shellcheck shell=bash
# The WebSocket targets, which sweep.sh sources after the HTTP ones, with
# its helpers and settings. Each target runs two echo loads, 64-byte text
# and 1 KiB binary messages on WS_CONNECTIONS connections for WS_SECONDS
# after WS_WARMUP, and opens WS_IDLE quiet connections, all with
# baselines/tungstenite's client on OHA_THREADS threads. The results are
# JSON lines in <target>.ws.jsonl.
WS_CONNECTIONS=${WS_CONNECTIONS:-64}
WS_SECONDS=${WS_SECONDS:-10}
WS_WARMUP=${WS_WARMUP:-3}
WS_IDLE=${WS_IDLE:-10000}
echo "ws: $WS_CONNECTIONS connections, $WS_SECONDS s after $WS_WARMUP s warm-up, $WS_IDLE idle, $OHA_THREADS client threads" >> "$N/machine.txt"

open_port() {
  for _ in $(seq 1 180); do (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null && return 0; sleep 1; done
  echo "port $1 not up"
}
# ws_scenario <name> <port> -- <server command...>, the server started in
# this package's directory.
ws_scenario() {
  local name=$1 port=$2; shift 3
  wanted "$name" || return 0
  quiet
  local pid
  pid=$(cd "$R" && { nohup "$@" > "$N/$name.server.log" 2>&1 & echo $!; })
  open_port "$port"
  local server; server=$(listeners "$port" | head -1)
  local load=("$R/baselines/tungstenite/target/release/relic_baseline_ws_load" --url="ws://127.0.0.1:$port/" --threads="$OHA_THREADS" --pid="$server")
  local limit=()
  command -v timeout >/dev/null && limit=(timeout 300)
  {
    "${limit[@]}" "${load[@]}" --mode=echo --connections="$WS_CONNECTIONS" --size=64 --seconds="$WS_SECONDS" --warmup="$WS_WARMUP"
    "${limit[@]}" "${load[@]}" --mode=echo --connections="$WS_CONNECTIONS" --size=1024 --binary --seconds="$WS_SECONDS" --warmup="$WS_WARMUP"
    "${limit[@]}" "${load[@]}" --mode=idle --connections="$WS_IDLE" --size=64 --seconds=5
  } > "$N/$name.ws.jsonl" 2> "$N/$name.err"
  echo "$name exit $?" >> "$N/progress.log"
  pkill -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null
  for _ in $(seq 1 10); do
    local left; left=$(listeners "$port")
    [[ -z $left ]] && break
    # shellcheck disable=SC2086
    kill $left 2>/dev/null; sleep 1
  done
  sleep "$PAUSE"
}

# The servers hold up to WS_IDLE sockets each.
ulimit -n 65536 2>/dev/null || ulimit -n "$(ulimit -Hn)" 2>/dev/null
ws_echo=$R/baselines/tungstenite/target/release/relic_baseline_ws_echo
ws_serve=(dart run bin/ws_echo_serve.dart)
for ways in 1 2 4 8; do
  suffix=$ways; [[ $ways == 1 ]] && suffix=""
  ws_scenario "tungstenite$suffix-ws" "830$ways" -- "$ws_echo" "830$ways" "$ways"
  ws_scenario "dusty$suffix-ws" "1833$ways" -- "$Z" "1833$ways" "$ways"
  ws_scenario "relic-native$suffix-ws" "1830$ways" -- "${ws_serve[@]}" native "1830$ways" "$ways"
  ws_scenario "relic-io$suffix-ws" "1831$ways" -- "${ws_serve[@]}" io "1831$ways" "$ways"
  ws_scenario "shelf$suffix-ws" "1832$ways" -- "${ws_serve[@]}" shelf "1832$ways" "$ways"
done
