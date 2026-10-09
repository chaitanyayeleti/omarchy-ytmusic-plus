#!/usr/bin/env bash
# test/run.sh — offline regression tests for the ytmusic-plus backend.
#
# Runs against a throwaway HOME/XDG sandbox with a generated local opus file
# and mpv forced to a null audio output: no network, no sound, no effect on
# your real library/settings/queue. Usage:
#
#   bash test/run.sh
#
# Exits non-zero when any check fails. Requires: bash, mpv, jq, socat, flock,
# ffmpeg (all present on a standard Omarchy install). The MPRIS check runs
# only when a session bus + busctl + mpv-mpris are available; otherwise it is
# reported as skipped.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT/bin/ytmusic-plus"

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/ytmusic-test.XXXXXX")"
export HOME="$SANDBOX/home"
export XDG_RUNTIME_DIR="$SANDBOX/runtime"
export XDG_DATA_HOME="$SANDBOX/data"
export XDG_CACHE_HOME="$SANDBOX/cache"
export XDG_CONFIG_HOME="$SANDBOX/config"
mkdir -p "$HOME/Music/ytmusic-plus" "$SANDBOX/runtime" "$SANDBOX/data" \
         "$SANDBOX/cache" "$SANDBOX/config/mpv"
printf 'ao=null\nvolume=0\n' >"$SANDBOX/config/mpv/mpv.conf"

R="$SANDBOX/runtime/omarchy-ytmusic-plus"
D="$SANDBOX/data/omarchy-ytmusic-plus"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$1"; }
skip() { printf 'skip %s\n' "$1"; }

check() { # check <name> <condition...>
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi
}

cleanup() {
  "$CLI" stop >/dev/null 2>&1 || true
  rm -rf "$SANDBOX"
}
trap cleanup EXIT

for dep in mpv jq socat flock ffmpeg; do
  command -v "$dep" >/dev/null 2>&1 || { printf 'missing dependency: %s\n' "$dep" >&2; exit 2; }
done

wait_socket() {
  local i
  for i in $(seq 1 60); do
    [[ -S "$R/mpv.sock" ]] && return 0
    sleep 0.25
  done
  return 1
}

status_field() { "$CLI" status | jq -r "$1"; }
session_field() { jq -r "$1" "$D/session.json"; }

vid_a="dQw4w9WgXcQ"
vid_b="BBBBBBBBBBB"

# ---- fixtures -------------------------------------------------------------
ffmpeg -f lavfi -i "sine=frequency=440:duration=60" \
  -metadata title="Test Song" -metadata artist="Test Artist" \
  -y "$HOME/Music/ytmusic-plus/$vid_a.opus" >/dev/null 2>&1
ffmpeg -f lavfi -i "sine=frequency=330:duration=60" \
  -y "$HOME/Music/ytmusic-plus/$vid_b.opus" >/dev/null 2>&1
"$CLI" set volume 0 >/dev/null

# ---- static checks --------------------------------------------------------
check "bash syntax" bash -n "$CLI"
if command -v qmllint >/dev/null 2>&1; then
  check "qmllint Player.qml" qmllint "$ROOT/Player.qml"
else
  skip "qmllint (not installed)"
fi
if command -v luac >/dev/null 2>&1; then
  check "lua syntax hypr-bindings.lua" luac -p "$ROOT/hypr-bindings.lua"
else
  skip "luac (not installed)"
fi

# ---- queue + playback -----------------------------------------------------
"$CLI" queue "[{\"videoId\":\"$vid_a\",\"title\":\"Test Song\",\"artist\":\"Test Artist\",\"thumbnail\":\"\",\"duration\":\"1:00\",\"isLive\":false}]" 0 >/dev/null
wait_socket || bad "mpv socket comes up"

check "status reports running" test "$(status_field .running)" = "true"
check "status reports the title" test "$(status_field .title)" = "Test Song"
check "session snapshot exists" test -s "$D/session.json"
check "session carries the track" test "$(session_field .state.videoId)" = "$vid_a"
check "session starts unpaused" test "$(session_field .paused)" = "false"

# ---- position snapshot (throttled) ---------------------------------------
# The position keeps advancing while the track plays, so assert a sane range
# rather than an exact second: 0 would mean the throttle never wrote.
"$CLI" seek-to 20 >/dev/null
sleep 0.5
"$CLI" status >/dev/null
pos_snap="$(session_field .position)"
check "session throttles position after seek" \
  bash -c "[[ '$pos_snap' -ge 15 && '$pos_snap' -le 30 ]]"

# ---- stop keeps the live position ----------------------------------------
"$CLI" stop
sleep 0.5
pos_stop="$(session_field .position)"
check "stop snapshots paused=true" test "$(session_field .paused)" = "true"
check "stop keeps the live position" \
  bash -c "[[ '$pos_stop' -ge 15 && '$pos_stop' -le 35 ]]"

# ---- simulated reboot: runtime wiped, session restored -------------------
rm -rf "$R"
mkdir -p "$R"
check "session-restore prints restored" test "$("$CLI" session-restore)" = "restored"
check "restore rebuilds the queue" test "$(jq -r '.[0].videoId' "$R/queue.json")" = "$vid_a"
check "restore rebuilds the state" test "$(jq -r '.videoId' "$R/state.json")" = "$vid_a"
check "restore is idempotent (silent)" test -z "$("$CLI" session-restore)"

# ---- dead polls never wipe the remembered position -----------------------
pos_dead="$(session_field .position)"
"$CLI" status >/dev/null
"$CLI" status >/dev/null
check "dead polls keep the remembered position" test "$(session_field .position)" = "$pos_dead"

# ---- toggle resumes at the saved position --------------------------------
pos_before="$(session_field .position)"
"$CLI" toggle
wait_socket || bad "resume relaunches mpv"
sleep 0.5
check "resume passes --start=<saved position>" \
  bash -c "tr '\\0' '\\n' < /proc/\$(cat '$R/mpv.pid')/cmdline | grep -q -- '--start=$pos_before'"
check "resume status reports running" test "$(status_field .running)" = "true"

# ---- MPRIS metadata (optional) -------------------------------------------
# Match the MPRIS name to OUR sandbox mpv pid: a real player running on the
# same session bus must never be mistaken for the test instance.
if command -v busctl >/dev/null 2>&1 && busctl --user list >/dev/null 2>&1 \
   && ls /etc/mpv/scripts/mpris.so /usr/lib/mpv-mpris/mpris.so >/dev/null 2>&1; then
  mpv_pid="$(cat "$R/mpv.pid" 2>/dev/null || true)"
  name="$(busctl --user list --no-pager 2>/dev/null \
    | awk -v pid="$mpv_pid" '$1 ~ /^org\.mpris\.MediaPlayer2\.mpv/ && $2 == pid { print $1; exit }')"
  if [[ -n "$name" ]]; then
    check "mpris exposes the track title" \
      bash -c "busctl --user get-property '$name' /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player Metadata | grep -q 'Test Song'"
  else
    skip "mpris player not registered for the sandbox mpv"
  fi
else
  skip "mpris (no session bus or mpv-mpris)"
fi

# ---- next advances and follows in the session ----------------------------
"$CLI" queue "[{\"videoId\":\"$vid_a\",\"title\":\"A\",\"artist\":\"X\",\"thumbnail\":\"\",\"duration\":\"1:00\",\"isLive\":false},{\"videoId\":\"$vid_b\",\"title\":\"B\",\"artist\":\"Y\",\"thumbnail\":\"\",\"duration\":\"1:00\",\"isLive\":false}]" 0 >/dev/null
wait_socket || bad "two-track queue plays"
"$CLI" next
for _ in $(seq 1 40); do
  [[ "$(status_field .videoId)" = "$vid_b" ]] && break
  sleep 0.25
done
check "next advances the state" test "$(status_field .videoId)" = "$vid_b"
check "next follows in the session" test "$(session_field .state.videoId)" = "$vid_b"

# ---- queue-clear drops the session ---------------------------------------
"$CLI" queue-clear >/dev/null
check "queue-clear removes the session file" test ! -e "$D/session.json"
check "queue-clear stops playback" test "$(status_field .running)" = "false"

# ---- fresh boot: restore is a silent no-op -------------------------------
check "fresh restore no-op" test -z "$("$CLI" session-restore)"

# ---- empty queue start is a clean stop -----------------------------------
"$CLI" queue '[]' 0 >/dev/null
check "empty queue leaves nothing running" test "$(status_field .running)" = "false"

# ---- downloads manager (offline mechanics) --------------------------------
SD="$R/downloads"
mkdir -p "$SD"

check "dl-status starts empty" test "$("$CLI" dl-status)" = "[]"

# A second tap during a live transfer must never spawn a duplicate yt-dlp:
# hold the per-vid lock and expect a polite refusal without any network use.
# (vid_c has no local file, so the "cached" short-circuit cannot mask this.)
vid_c="CCCCCCCCCCC"
( flock -x 8; sleep 3 ) 8>"$SD/$vid_c.lock" &
guard_pid=$!
sleep 0.3
dup_out="$("$CLI" dl-get "$vid_c" "X" "Y" "" "" false)"
if [[ "$dup_out" == "already downloading $vid_c" ]]; then
  ok "duplicate dl-get refused while locked"
else
  bad "duplicate dl-get refused while locked (got: '$dup_out')"
fi
wait "$guard_pid" 2>/dev/null || true

# A "downloading" entry whose pid is not a live yt-dlp (crash, kill, pid
# reuse) must be reaped to failed instead of spinning forever.
sleep 5 &
fake_pid=$!
jq -cn --arg v "$vid_a" --argjson pid "$fake_pid" \
  '{videoId:$v,state:"downloading",progress:42,speed:"1MiB/s",eta:"00:03",title:"Fake",pid:$pid}' \
  >"$SD/$vid_a.json"
reaped="$("$CLI" dl-status | jq -r '.[0].state + ":" + (.[0].error // "")')"
check "stale download reaped to failed:interrupted" test "$reaped" = "failed:interrupted"
kill "$fake_pid" 2>/dev/null || true

check "dl-cancel dismisses the failed entry" \
  test "$("$CLI" dl-cancel "$vid_a")" = "cancelled $vid_a"
check "dl-cancel removed the state file" test ! -e "$SD/$vid_a.json"
check "dl-status empty after cancel" test "$("$CLI" dl-status)" = "[]"
check "dl-cancel on an unknown id is a no-op" test -z "$("$CLI" dl-cancel "$vid_b")"

# dl-remove clears any leftover state entry for the same video.
jq -cn --arg v "$vid_b" '{videoId:$v,state:"failed",progress:0,title:"B"}' >"$SD/$vid_b.json"
"$CLI" dl-remove "$vid_b" >/dev/null
check "dl-remove clears the state entry" test ! -e "$SD/$vid_b.json"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
