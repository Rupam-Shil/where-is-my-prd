#!/bin/sh
# Records assets/demo.gif with Take One (https://github.com/Rupam-Shil/TakeOne):
#   1. opens a Terminal window running a real Claude Code session (demo.exp) with this plugin,
#   2. records that window with Take One's studio-recorder helper,
#   3. writes a Take One project whose timeline fast-forwards the waits for the model,
#   4. lets the Take One editor export the GIF ("Record & save" route, no dialogs).
#
# Usage: sh scripts/demo/record.sh "/path/to/Take One.app" [model]
# Needs: macOS, Take One (quit before running), expect, node >= 22, python3, a logged-in claude CLI.
# Take One's settings.json is backed up and restored; the demo repo is created next to this repo and removed after.

set -eu

root=$(cd "$(dirname "$0")/../.." && pwd)
app=${1:?usage: sh scripts/demo/record.sh "/path/to/Take One.app" [model]}
model=${2:-sonnet}
helper="$app/Contents/Resources/bin/Take One Helper.app/Contents/MacOS/studio-recorder"
settings="$HOME/Library/Application Support/Take One/settings.json"
name=wheres-my-prd-demo
work=$(mktemp -d "${TMPDIR:-/tmp}/wmp-demo.XXXXXX")
state="$work/state"
project="$work/$name.takeone"
demo_repo="$(dirname "$root")/acme-saas"

now_ms() { python3 -c 'import time; print(int(time.time() * 1000))'; }

wait_for() { # wait_for <seconds> <test command...>
  limit=$1
  shift
  i=0
  until "$@"; do
    i=$((i + 1))
    [ "$i" -le $((limit * 5)) ] || { echo "timed out waiting for: $*" >&2; exit 1; }
    sleep 0.2
  done
}

terminal_windows() {
  "$helper" list | python3 -c '
import json, sys
for line in sys.stdin:
    if line.startswith("{"):
        for w in json.loads(line).get("windows", []):
            if w.get("appName") == "Terminal":
                print(w["id"])'
}

[ -x "$helper" ] || { echo "studio-recorder not found in $app" >&2; exit 1; }
if pgrep -x "Take One" >/dev/null; then echo "Quit Take One first: its settings are edited for the export." >&2; exit 1; fi
if [ -e "$demo_repo" ]; then echo "$demo_repo already exists; move it out of the way first." >&2; exit 1; fi
if ioreg -n Root -d1 -a | grep -A1 CGSSessionScreenIsLocked | grep -q true; then
  echo "The screen is locked, and macOS blocks screen capture while it is. Unlock and run again." >&2
  exit 1
fi

cp "$settings" "$work/settings.backup.json"
cleanup() {
  cp "$work/settings.backup.json" "$settings"
  rm -rf "${demo_repo:?}"
  pkill -f "$state" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM
caffeinate -d -i -w $$ &

mkdir -p "$state" "$project/recording" "$work/export"
cp -R "$root/evals/fixtures/acme-saas" "$demo_repo"

# 1. Terminal window running the scripted Claude Code session
before=$(terminal_windows | sort)
# Terminal runs the profile's command without a login shell (no PATH, no prompt), so go through a launcher.
{
  printf '#!/bin/sh\n'
  printf "export PATH='%s'\n" "$PATH"
  printf "exec /usr/bin/expect '%s' '%s' '%s' '%s' '%s'\n" "$root/scripts/demo/demo.exp" "$root" "$demo_repo" "$state" "$model"
} > "$work/launch.sh"
osascript -l JavaScript "$root/scripts/demo/terminal-profile.js" "$work/demo.terminal" "/bin/sh $work/launch.sh" >/dev/null
open "$work/demo.terminal"
new_window() {
  window=$(terminal_windows | sort | comm -13 "$work/before" - | head -n 1)
  [ -n "$window" ]
}
printf '%s\n' "$before" > "$work/before"
wait_for 30 new_window
echo "terminal window $window; waiting for Claude Code to be ready"
wait_for 180 test -e "$state/ready"
open -a Terminal
sleep 1
screencapture -x -o -l"$window" "$work/ready.png" || echo "(no ready.png: the window is not on the current Space)"
if [ -n "${DEMO_CONFIRM:-}" ]; then
  echo "check $work/ready.png, then: touch $work/confirm"
  wait_for 600 test -e "$work/confirm"
fi

# 2. Record that window with Take One's helper; commands go in through a FIFO
mkfifo "$work/ctl"
config=$(printf '{"outputDir":"%s","source":{"type":"window","windowId":%s},"fps":30,"captureSystemAudio":false,"keystrokes":"off","showCursor":false}' "$project/recording" "$window")
"$helper" record "$config" < "$work/ctl" > "$work/recorder.log" 2>&1 &
recorder=$!
exec 3> "$work/ctl"
wait_for 30 grep -q '"started"' "$work/recorder.log"
now_ms > "$state/t0"
sleep 2
if grep -q '"error"' "$work/recorder.log"; then
  echo "Take One's recorder reported an error (is the screen locked, or Screen Recording not allowed?):" >&2
  cat "$work/recorder.log" >&2
  exit 1
fi
echo "recording"
touch "$state/go"

wait_for 1800 test -e "$state/done"
echo stop >&3
wait_for 60 grep -q '"finished"' "$work/recorder.log"
exec 3>&-
wait "$recorder" || true
touch "$state/stopped"
echo "recorded $(python3 -c "import json; print(round(json.load(open('$project/recording/meta.json'))['duration'], 1))")s"

# 3. Take One project: normal speed for typing and reading, fast-forward while the model works
python3 - "$project" "$state" "$name" <<'EOF'
import json, math, os, sys, uuid, datetime
project, state, name = sys.argv[1:]
t0 = int(open(os.path.join(state, "t0")).read())
events = {}
for line in open(os.path.join(state, "events.log")):
    ms, label = line.split()
    events[label] = int(ms) - t0
duration = round(json.load(open(os.path.join(project, "recording", "meta.json")))["duration"] * 1000)

def fast(start, end):  # squeeze each wait into roughly 6 seconds
    return max(4, min(24, math.ceil((end - start) / 6000)))

cuts = [0, events["submitted"] + 2500, events["answered"], events["submitted2"] + 2500, events["answered2"], duration]
slices = []
for i, (start, end) in enumerate(zip(cuts, cuts[1:])):
    end = min(end, duration)
    if end - start < 100:
        continue
    speed = fast(start, end) if i % 2 else 1
    slices.append({"id": uuid.uuid4().hex[:12], "start": start, "end": end, "speed": speed, "volume": 1,
                   "systemVolume": 1, "hideCursor": True, "disableSmoothing": False})
now = datetime.datetime.now(datetime.timezone.utc).isoformat()
config = {"style": {"output": {"padding": 0.06}, "cursor": {"hide": True}}, "timeline": {"slices": slices}, "transcript": None}
project_file = {"version": 1, "id": str(uuid.uuid4()), "name": name, "createdAt": now, "updatedAt": now,
                "recordings": ["recording"], "config": config}
json.dump(project_file, open(os.path.join(project, "project.json"), "w"), indent=2)
print("timeline:", ", ".join(f"{(s['end'] - s['start']) / 1000:.1f}s@{s['speed']}x" for s in slices))
EOF

# 4. Export through the Take One editor
python3 - "$settings" "$work/export" <<'EOF'
import json, sys
path, export_dir = sys.argv[1:]
s = json.load(open(path))
s.setdefault("export", {}).update({"format": "gif", "gifHeight": 800, "gifFps": 15, "gifHighQuality": True, "gifLoop": True})
s.setdefault("general", {})["exportDir"] = export_dir
json.dump(s, open(path, "w"), indent=2)
EOF
node "$root/scripts/demo/take-one-export.mjs" "$app" "$project" "$work/export/$name.gif"
cp "$work/export/$name.gif" "$root/assets/demo.gif"
echo "wrote assets/demo.gif (project kept at $project)"
