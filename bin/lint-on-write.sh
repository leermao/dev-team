#!/bin/bash
# PostToolUse hook: auto-lint after any Write or Edit tool call.
# Input: JSON via stdin  { tool_name, tool_input: { file_path, ... }, ... }
# Output: additionalContext JSON if lint issues remain after auto-fix.
# Always exits 0 — lint errors are advisory, not blocking.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Nothing to lint if no file path
[ -z "$FILE_PATH" ] && exit 0
[ ! -f "$FILE_PATH" ] && exit 0

EXT="${FILE_PATH##*.}"
ISSUES=""

case "$EXT" in
  ts|tsx|js|jsx|mjs|cjs)
    if command -v npx &>/dev/null; then
      # Auto-fix first, then capture any remaining issues
      npx --no eslint --fix "$FILE_PATH" &>/dev/null || true
      ISSUES=$(npx --no eslint "$FILE_PATH" 2>&1) || true
    fi
    ;;
  py)
    if command -v ruff &>/dev/null; then
      ruff check --fix "$FILE_PATH" &>/dev/null || true
      ISSUES=$(ruff check "$FILE_PATH" 2>&1) || true
    elif command -v flake8 &>/dev/null; then
      ISSUES=$(flake8 "$FILE_PATH" 2>&1) || true
    fi
    ;;
  go)
    if command -v gofmt &>/dev/null; then
      gofmt -w "$FILE_PATH" &>/dev/null || true
    fi
    ;;
  rb)
    if command -v rubocop &>/dev/null; then
      rubocop -a "$FILE_PATH" &>/dev/null || true
      ISSUES=$(rubocop "$FILE_PATH" 2>&1) || true
    fi
    ;;
esac

# Return remaining issues as context so Claude is aware
if [ -n "$ISSUES" ]; then
  jq -n --arg msg "Lint issues remaining in ${FILE_PATH}:\n${ISSUES}" \
    '{"additionalContext": $msg}'
fi

exit 0
