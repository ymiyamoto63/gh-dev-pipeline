#!/usr/bin/env bash
# Checks that the Claude Code and GitHub Copilot variants of each agent stay in sync.
#
# The two variants are intentionally identical except for frontmatter and a few
# known phrase differences (Agent tool vs agent tool, AskUserQuestion vs chat).
# For each pair this script strips the frontmatter, computes which body lines
# exist only on one side, and compares that delta against a committed snapshot
# in tools/sync-snapshots/. If the delta changed, one side was edited without
# the other.
#
# Shares the same tools/sync-snapshots/ files as check-sync.ps1 — the two
# scripts produce identical delta output, so either can verify or update them.
#
# Usage:
#   ./tools/check-sync.sh            # verify (exit 1 on drift)
#   ./tools/check-sync.sh --update   # re-record snapshots after an intentional divergence

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$script_dir/.." && pwd)"
snapshot_dir="$script_dir/sync-snapshots"

update=0
if [[ "${1:-}" == "--update" ]]; then
  update=1
fi

pairs=(
  "dev-pipeline|commands/dev-pipeline.md|copilot/agents/dev-pipeline.agent.md"
  "requirements-analyst|agents/requirements-analyst.md|copilot/agents/requirements-analyst.agent.md"
  "software-architect|agents/software-architect.md|copilot/agents/software-architect.agent.md"
  "implementer|agents/implementer.md|copilot/agents/implementer.agent.md"
  "test-engineer|agents/test-engineer.md|copilot/agents/test-engineer.agent.md"
  "code-reviewer|agents/code-reviewer.md|copilot/agents/code-reviewer.agent.md"
  "pr-publisher|agents/pr-publisher.md|copilot/agents/pr-publisher.agent.md"
)

get_body() {
  # Strips CRLF and any leading YAML frontmatter (--- ... ---); prints the rest as-is.
  sed 's/\r$//' "$1" | awk '
    NR==1 {
      if ($0=="---") { infm=1; next }
      print; next
    }
    infm==1 {
      if ($0=="---") { infm=0 }
      next
    }
    { print }
  '
}

get_delta() {
  local claude_path="$1" copilot_path="$2"
  local a_tmp b_tmp
  a_tmp="$(mktemp)"
  b_tmp="$(mktemp)"
  get_body "$claude_path" > "$a_tmp"
  get_body "$copilot_path" > "$b_tmp"

  # Multiset-subtract each side against the other, preserving original line order —
  # matches Get-UniqueLines in check-sync.ps1 so both scripts agree on the delta.
  awk 'NR==FNR{b[$0]++; next} { if (b[$0] > 0) { b[$0]--; next } print "claude-only| " $0 }' "$b_tmp" "$a_tmp"
  awk 'NR==FNR{a[$0]++; next} { if (a[$0] > 0) { a[$0]--; next } print "copilot-only| " $0 }' "$a_tmp" "$b_tmp"

  rm -f "$a_tmp" "$b_tmp"
}

mkdir -p "$snapshot_dir"

failed=()
for pair in "${pairs[@]}"; do
  IFS='|' read -r name claude_rel copilot_rel <<< "$pair"
  claude_path="$root/$claude_rel"
  copilot_path="$root/$copilot_rel"
  snap_path="$snapshot_dir/$name.delta.txt"

  delta="$(get_delta "$claude_path" "$copilot_path")"

  if [[ $update -eq 1 ]]; then
    printf '%s\n' "$delta" > "$snap_path"
    echo "updated snapshot: $name"
    continue
  fi

  expected=""
  if [[ -f "$snap_path" ]]; then
    expected="$(sed 's/\r$//' "$snap_path")"
  fi

  if [[ "$delta" != "$expected" ]]; then
    failed+=("$name")
    echo "DRIFT: $name — the Claude and Copilot bodies diverge beyond the recorded snapshot."
    echo "  current delta (lines present on only one side):"
    if [[ -n "$delta" ]]; then
      printf '%s\n' "$delta" | sed 's/^/    /'
    else
      echo "    (none)"
    fi
  else
    echo "ok: $name"
  fi
done

if [[ ${#failed[@]} -gt 0 ]]; then
  echo ""
  IFS=,
  echo "Sync check failed for: ${failed[*]}"
  unset IFS
  echo "Either mirror the edit to the other variant, or — if the divergence is intentional — run ./tools/check-sync.sh --update and commit the snapshot."
  exit 1
fi

echo "all pairs in sync"
