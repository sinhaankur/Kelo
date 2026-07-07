#!/usr/bin/env bash
#
# Anita, work while I'm away.
#
# Run this, then walk away. Anita drives the TOP unchecked item in BACKLOG.md
# toward completion — bounded, sandboxed, and logged — then stops. It is NOT a
# daemon: it does one launch-and-finish run and exits. Read the checkpoint log
# when you're back; every edit is git-committed-able and revertible.
#
#   ./anita-drive.sh                 # drive the top backlog item
#   ./anita-drive.sh "some goal"     # drive a goal you type instead
#
# Safety: Anita acts only through the sandboxed drive_* tools (can't leave this
# project, can't rm / git push / run arbitrary shell), with a capped step budget
# and a full step log at ~/.cognitive-twin/drive/.

set -euo pipefail
PROJECT="$(cd "$(dirname "$0")" && pwd)"
VERA="$HOME/Documents/cognitive-twin-agent"

# The goal: an explicit arg, else the top "Now" item from the backlog.
if [[ $# -ge 1 ]]; then
  GOAL="$1"
else
  # First unchecked "- [ ]" line under the file, trimmed of the checkbox.
  GOAL="$(grep -m1 '^- \[ \]' "$PROJECT/BACKLOG.md" | sed 's/^- \[ \] //' | sed 's/\*\*//g')"
fi

if [[ -z "${GOAL:-}" ]]; then
  echo "Nothing to do — no unchecked backlog item found."
  exit 0
fi

echo "Anita is driving Kelo toward:"
echo "  $GOAL"
echo "Project: $PROJECT"
echo "Follow along at: ~/.cognitive-twin/drive/drive-$(basename "$PROJECT").md"
echo "Starting… (you can walk away; it stops when done)"
echo

# Ensure Ollama (Anita's local brain) is up before she starts.
if ! curl -s -m 2 http://localhost:11434/api/tags >/dev/null 2>&1; then
  echo "Starting Ollama (local model)…"
  (ollama serve >/dev/null 2>&1 &) || true
  sleep 3
fi

# Call the drive skill directly (deterministic — no reliance on the model
# choosing to invoke it), from the Vera project so imports resolve.
cd "$VERA"
python3 - "$PROJECT" "$GOAL" <<'PY'
import sys
from cognitive_twin.skills import vscode_drive  # registers drive skills
from cognitive_twin.skills.base import default_registry as R

project, goal = sys.argv[1], sys.argv[2]
print(R.dispatch("drive", {"project": project, "goal": goal, "max_steps": 24}))
PY

echo
echo "Done. Review the checkpoint log above, then check `git -C \"$PROJECT\" diff` and"
echo "commit or revert as you like. Anita never commits or pushes on her own."
