#!/usr/bin/env bash
# WARNING: This script is NOT idempotent. Running it twice will corrupt the layout.
set -euo pipefail

CONFIG="$HOME/.claude/teams/dev-team/config.json"

command -v jq   >/dev/null 2>&1 || { echo "apply-layout error: jq is required but not installed" >&2; exit 1; }
command -v tmux >/dev/null 2>&1 || { echo "apply-layout error: tmux is required but not installed" >&2; exit 1; }

fail() {
  echo "apply-layout error: $*" >&2
  echo "Hint: tmux layout may be partially applied. Re-run after fixing the issue." >&2
  exit 1
}

get_pane() {
  local role="$1"
  # NOTE: declare and assign separately so `set -e` catches jq failures
  local pane
  pane=$(jq -r --arg n "$role" '
    [.members[]? | select(.name==$n)] |
    if length != 1 then error("expected exactly 1, found \(length)")
    else .[0].tmuxPaneId // ""
    end
  ' "$CONFIG") || fail "cannot read member $role from $CONFIG"

  if [ -z "$pane" ] || [ "$pane" = "null" ]; then
    fail "tmuxPaneId for $role is empty or null"
  fi
  case "$pane" in
    %*) printf '%s\n' "$pane" ;;
    *) fail "tmuxPaneId for $role is invalid: $pane" ;;
  esac
}

pane_exists() {
  local pane="$1"
  tmux list-panes -a -F '#{pane_id}' |
    awk -v pane="$pane" '$0 == pane { found = 1 } END { exit found ? 0 : 1 }'
}

validate_panes() {
  local names=(
    "fe-team-leader"
    "fe-developer"
    "be-team-leader"
    "be-developer"
    "test-team-leader"
    "test-engineer"
    "security-engineer"
  )
  local panes=(
    "$FE_LEADER"
    "$FE_DEV"
    "$BE_LEADER"
    "$BE_DEV"
    "$TEST_LEADER"
    "$TEST_ENG"
    "$SECURITY"
  )

  for i in "${!panes[@]}"; do
    if [ "${panes[$i]}" = "$TEAM_LEAD" ]; then
      fail "current pane $TEAM_LEAD is also assigned to ${names[$i]}"
    fi

    if ! pane_exists "${panes[$i]}"; then
      fail "tmuxPaneId for ${names[$i]} does not exist: ${panes[$i]}"
    fi

    for j in "${!panes[@]}"; do
      if [ "$i" -lt "$j" ] && [ "${panes[$i]}" = "${panes[$j]}" ]; then
        fail "duplicate tmuxPaneId ${panes[$i]} for ${names[$i]} and ${names[$j]}"
      fi
    done
  done
}

TEAM_LEAD=$(tmux display-message -p '#{pane_id}')
FE_LEADER=$(get_pane "fe-team-leader")
FE_DEV=$(get_pane "fe-developer")
BE_LEADER=$(get_pane "be-team-leader")
BE_DEV=$(get_pane "be-developer")
TEST_LEADER=$(get_pane "test-team-leader")
TEST_ENG=$(get_pane "test-engineer")
SECURITY=$(get_pane "security-engineer")

validate_panes

# Ensure all teammate panes are in the same window as team-lead
WINDOW=$(tmux display-message -p '#{window_id}')
for PANE in "$FE_LEADER" "$FE_DEV" "$BE_LEADER" "$BE_DEV" "$TEST_LEADER" "$TEST_ENG" "$SECURITY"; do
  PANE_WIN=$(tmux display-message -p -t "$PANE" '#{window_id}' 2>/dev/null || true)
  if [ "$PANE_WIN" != "$WINDOW" ]; then
    tmux join-pane -d -s "$PANE" -t "$TEAM_LEAD"
  fi
done

# Step 1: Place security-engineer to the right of team-lead (50% width)
tmux join-pane -h -l 50% -s "$SECURITY" -t "$TEAM_LEAD"

# Step 2: Stack 3 rows above security so all 4 rows are equal height (~25% each)
# Each -l percentage is relative to security's current height at time of split:
#   25% of 100% = 25% total -> fe row
#   33% of 75%  ~= 25% total -> be row
#   50% of 50%  = 25% total -> test row (security keeps final 25%)
tmux join-pane -b -v -l 25% -s "$FE_LEADER"   -t "$SECURITY"
tmux join-pane -b -v -l 33% -s "$BE_LEADER"   -t "$SECURITY"
tmux join-pane -b -v -l 50% -s "$TEST_LEADER" -t "$SECURITY"

# Step 3: Split FE / BE / Test rows into leader + developer (50/50 each)
tmux join-pane -h -l 50% -s "$FE_DEV"   -t "$FE_LEADER"
tmux join-pane -h -l 50% -s "$BE_DEV"   -t "$BE_LEADER"
tmux join-pane -h -l 50% -s "$TEST_ENG" -t "$TEST_LEADER"
