#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
SCRIPT="$ROOT/skills/dev-team/scripts/apply-layout.sh"

make_config() {
  local home="$1"
  local security_pane="${2:-%79}"

  mkdir -p "$home/.claude/teams/dev-team"
  cat >"$home/.claude/teams/dev-team/config.json" <<JSON
{
  "members": [
    {"name": "fe-team-leader", "tmuxPaneId": "%73"},
    {"name": "fe-developer", "tmuxPaneId": "%74"},
    {"name": "be-team-leader", "tmuxPaneId": "%75"},
    {"name": "be-developer", "tmuxPaneId": "%76"},
    {"name": "test-team-leader", "tmuxPaneId": "%77"},
    {"name": "test-engineer", "tmuxPaneId": "%78"},
    {"name": "security-engineer", "tmuxPaneId": "$security_pane"}
  ]
}
JSON
}

make_fake_tmux() {
  local bin="$1"
  cat >"$bin/tmux" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

log="${TMUX_LOG:?}"

case "${1:-}" in
  display-message)
    target=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -t) target="$2"; shift 2 ;;
        -p) shift ;;
        *) format="$1"; shift ;;
      esac
    done
    case "${format:-}" in
      '#{pane_id}') printf '%s\n' "${CURRENT_PANE:-%72}" ;;
      '#{window_id}') printf '@17\n' ;;
      *) printf '@17\n' ;;
    esac
    ;;
  join-pane)
    printf '%s\n' "$*" >>"$log"
    source=""
    target=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -s) source="$2"; shift 2 ;;
        -t) target="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    if [ "$source" = "$target" ]; then
      echo "source and target panes must be different" >&2
      exit 1
    fi
    ;;
  list-panes)
    printf '%%72\n%%73\n%%74\n%%75\n%%76\n%%77\n%%78\n%%79\n'
    ;;
  *)
    echo "unexpected tmux command: $*" >&2
    exit 1
    ;;
esac
SH
  chmod +x "$bin/tmux"
}

run_with_fake_tmux() {
  local work="$1"
  local security_pane="${2:-%79}"

  mkdir -p "$work/bin"
  make_config "$work/home" "$security_pane"
  make_fake_tmux "$work/bin"

  TMUX_LOG="$work/tmux.log" HOME="$work/home" PATH="$work/bin:$PATH" \
    bash "$SCRIPT" >"$work/stdout" 2>"$work/stderr"
}

test_join_pane_uses_tmux_size_flag() {
  local work
  work=$(mktemp -d)

  run_with_fake_tmux "$work"

  if awk '{ for (i = 1; i <= NF; i++) if ($i == "-p") found = 1 } END { exit found ? 0 : 1 }' "$work/tmux.log"; then
    echo "join-pane must not use unsupported -p flag" >&2
    cat "$work/tmux.log" >&2
    exit 1
  fi

  grep -q -- 'join-pane -h -l 50% -s %79 -t %72' "$work/tmux.log"
}

test_current_pane_cannot_be_teammate_pane() {
  local work
  work=$(mktemp -d)

  if run_with_fake_tmux "$work" "%72"; then
    echo "expected duplicate current/team pane validation to fail" >&2
    exit 1
  fi

  grep -q 'current pane %72 is also assigned to security-engineer' "$work/stderr"
  if [ -s "$work/tmux.log" ]; then
    echo "layout should not be modified after validation failure" >&2
    cat "$work/tmux.log" >&2
    exit 1
  fi
}

test_join_pane_uses_tmux_size_flag
test_current_pane_cannot_be_teammate_pane
