#!/bin/bash
# TeammateIdle hook: track dev-team initialization readiness.
# Fires every time a teammate goes idle. Records the teammate as ready
# in a state file. When all 7 canonical teammates are ready, writes
# ready_count=7 so dev-team Step 6 can detect completion immediately
# instead of waiting a fixed 30 seconds.
#
# Input: JSON via stdin  { teammate_name, team_name, ... }
# State file: ~/.claude/teams/dev-team/ready.json

CANONICAL_MEMBERS='["fe-team-leader","fe-developer","be-team-leader","be-developer","test-team-leader","test-engineer","security-engineer"]'
STATE_FILE="$HOME/.claude/teams/dev-team/ready.json"

INPUT=$(cat)
TEAM=$(echo "$INPUT"  | jq -r '.team_name    // empty' 2>/dev/null)
NAME=$(echo "$INPUT"  | jq -r '.teammate_name // empty' 2>/dev/null)

# Only process the dev-team
[ "$TEAM" != "dev-team" ] && exit 0
[ -z "$NAME" ] && exit 0

mkdir -p "$(dirname "$STATE_FILE")"

# Atomically update the state file
TMP=$(mktemp)
CURRENT=$(cat "$STATE_FILE" 2>/dev/null || echo '{"ready":[]}')

# Add this teammate to the ready list (deduplicated)
UPDATED=$(echo "$CURRENT" | jq \
  --arg name "$NAME" \
  --argjson canonical "$CANONICAL_MEMBERS" \
  '
    .ready = (.ready + [$name] | unique) |
    .ready_count = (.ready | map(select(. as $m | $canonical | index($m) != null)) | length)
  ')

echo "$UPDATED" > "$TMP" && mv "$TMP" "$STATE_FILE"

READY_COUNT=$(echo "$UPDATED" | jq '.ready_count')

# Exit 0 — let the teammate go idle normally
exit 0
