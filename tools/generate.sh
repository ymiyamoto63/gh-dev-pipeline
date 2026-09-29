#!/usr/bin/env bash
# Generates both the Claude Code and GitHub Copilot variants of each agent /
# orchestrator definition from the single-source files in src/.
#
# Each src/<name>.md has three sections, introduced by marker lines:
#   <<<claude>>>     Claude-variant frontmatter, verbatim (including the --- lines)
#   <<<copilot>>>    Copilot-variant frontmatter, verbatim
#   <<<body>>>       shared body; format-specific phrases are written inline as
#                    {{claude:...}} / {{copilot:...}}  (marker text must not contain "}")
#
# Rendering rules:
#   - {{claude:X}} expands to X in the Claude output and to nothing in the Copilot
#     output (and vice versa).
#   - A non-empty source line that renders to an empty string (it held only
#     markers for the other format) is dropped entirely.
#   - An AUTO-GENERATED notice is inserted between the frontmatter and the body.
#   - A body block delimited by <<<phase:SLUG>>> ... <<<endphase>>> is a phase section.
#     Copilot output keeps it inline (the delimiter lines are dropped). Claude output keeps
#     only the block's first line (the heading) plus a pointer sentence in the main file, and
#     writes the rest to <main-output-dir>/phases/SLUG.md, which the orchestrator Reads on
#     entering the phase (smaller always-loaded prompt).
#
# tools/generate.ps1 is the same generator for PowerShell; keep the two behaviorally identical.
#
# Usage:
#   ./tools/generate.sh            # (re)write the generated files
#   ./tools/generate.sh --check    # verify generated files are up to date (exit 1 if stale)

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

check=0
if [[ "${1:-}" == "--check" ]]; then
  check=1
elif [[ $# -gt 0 ]]; then
  echo "usage: $0 [--check]" >&2
  exit 2
fi

pairs=(
  "dev-pipeline|skills/dev-pipeline/SKILL.md|copilot/agents/dev-pipeline.agent.md"
  "requirements-analyst|agents/requirements-analyst.md|copilot/agents/requirements-analyst.agent.md"
  "requirements-reviewer|agents/requirements-reviewer.md|copilot/agents/requirements-reviewer.agent.md"
  "software-architect|agents/software-architect.md|copilot/agents/software-architect.agent.md"
  "design-reviewer|agents/design-reviewer.md|copilot/agents/design-reviewer.agent.md"
  "implementer|agents/implementer.md|copilot/agents/implementer.agent.md"
  "test-engineer|agents/test-engineer.md|copilot/agents/test-engineer.agent.md"
  "security-reviewer|agents/security-reviewer.md|copilot/agents/security-reviewer.agent.md"
  "test-reviewer|agents/test-reviewer.md|copilot/agents/test-reviewer.agent.md"
  "quality-reviewer|agents/quality-reviewer.md|copilot/agents/quality-reviewer.agent.md"
  "pr-publisher|agents/pr-publisher.md|copilot/agents/pr-publisher.agent.md"
)

rendered=""
render_line() { # $1=line $2=keep-format $3=drop-format
  local line=$1 keep=$2 drop=$3 out prefix rest content
  out=$line
  while [[ $out == *"{{${keep}:"* ]]; do
    prefix=${out%%"{{${keep}:"*}
    rest=${out#*"{{${keep}:"}
    content=${rest%%\}\}*}
    rest=${rest#*\}\}}
    out="$prefix$content$rest"
  done
  while [[ $out == *"{{${drop}:"* ]]; do
    prefix=${out%%"{{${drop}:"*}
    rest=${out#*"{{${drop}:"}
    rest=${rest#*\}\}}
    out="$prefix$rest"
  done
  if [[ $out == *"{{"* || $out == *"}}"* ]]; then
    echo "unrendered marker remains in line: $out" >&2
    exit 1
  fi
  rendered=$out
}

phase_pointer() { # $1=slug
  printf '\n**このフェーズに入る直前に、このスキルのディレクトリにある`phases/%s.md`をReadツールで全文読み、その手順に従う。読まずにこのフェーズを始めない。**\n' "$1"
}

notice() { # $1=src-name
  printf '<!-- 自動生成ファイル: dev-pipelineリポジトリ（https://github.com/ymiyamoto63/gh-dev-pipeline）の src/%s.md から生成。編集はそのリポジトリの src/%s.md で行い tools/generate.ps1（または tools/generate.sh）を実行して再生成し、生成物をコピーし直すこと。インストール先にコピーされたこのファイルを直接編集しないこと（次回の更新で上書きされる）。 -->\n' "$1" "$1"
}

# result in $built; for the Claude format also $phase_slugs / $phase_bodies (parallel arrays)
build_output() { # $1=src-name $2=format
  local name=$1 fmt=$2 other src line cur="" slug="" pfirst=0 pbody="" text
  src="src/$name.md"
  phase_slugs=()
  phase_bodies=()
  if [[ ! -f $src ]]; then
    echo "missing source file: $src" >&2
    exit 1
  fi
  for m in '<<<claude>>>' '<<<copilot>>>' '<<<body>>>'; do
    grep -qxF "$m" "$src" || { echo "$src: missing $m section" >&2; exit 1; }
  done
  if [[ $fmt == claude ]]; then other=copilot; else other=claude; fi
  built=""
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    case $line in
      '<<<claude>>>')  cur=claude;  continue ;;
      '<<<copilot>>>') cur=copilot; continue ;;
      '<<<body>>>')
        cur=body
        built+="$(notice "$name")"$'\n'
        continue ;;
      '<<<phase:'*'>>>')
        [[ $cur == body ]] || { echo "$src: phase marker outside body" >&2; exit 1; }
        [[ -z $slug ]] || { echo "$src: nested phase marker" >&2; exit 1; }
        slug=${line#'<<<phase:'}; slug=${slug%'>>>'}
        pfirst=1
        pbody="$(notice "$name")"$'\n'
        continue ;;
      '<<<endphase>>>')
        [[ -n $slug ]] || { echo "$src: endphase without phase" >&2; exit 1; }
        if [[ $fmt == claude ]]; then
          phase_slugs+=("$slug")
          phase_bodies+=("$pbody")
        fi
        slug=""
        continue ;;
    esac
    if [[ $cur == "$fmt" ]]; then
      built+="$line"$'\n'
    elif [[ $cur == body ]]; then
      text=$line
      if [[ $line == *"{{"* ]]; then
        render_line "$line" "$fmt" "$other"
        if [[ -n $line && -z $rendered ]]; then continue; fi
        text=$rendered
      fi
      if [[ $fmt == claude && -n $slug ]]; then
        if [[ $pfirst == 1 ]]; then
          built+="$text"$'\n'"$(phase_pointer "$slug")"$'\n'
          pbody+="$text"$'\n'
          pfirst=0
        else
          pbody+="$text"$'\n'
        fi
      else
        built+="$text"$'\n'
      fi
    fi
  done < "$src"
  [[ -z $slug ]] || { echo "$src: unterminated phase block $slug" >&2; exit 1; }
}

stale=()
write_or_check() { # $1=path $2=content
  if [[ $check == 1 ]]; then
    if [[ -f $1 ]] && cmp -s <(printf '%s' "$2") <(tr -d '\r' < "$1"); then
      echo "ok: $1"
    else
      stale+=("$1")
    fi
  else
    mkdir -p "$(dirname "$1")"
    printf '%s' "$2" > "$1"
    echo "generated: $1"
  fi
}

for pair in "${pairs[@]}"; do
  IFS='|' read -r name claude_out copilot_out <<< "$pair"
  for fmt in claude copilot; do
    if [[ $fmt == claude ]]; then out_path=$claude_out; else out_path=$copilot_out; fi
    build_output "$name" "$fmt"
    write_or_check "$out_path" "$built"
    if [[ $fmt == claude ]]; then
      for i in "${!phase_slugs[@]}"; do
        write_or_check "$(dirname "$out_path")/phases/${phase_slugs[$i]}.md" "${phase_bodies[$i]}"
      done
    fi
  done
done

if [[ $check == 1 ]]; then
  if [[ ${#stale[@]} -gt 0 ]]; then
    echo ""
    echo "STALE: the following generated files do not match src/. Regenerate with ./tools/generate.sh (or ./tools/generate.ps1) and commit the result - never edit generated files directly:"
    for f in "${stale[@]}"; do echo "  $f"; done
    exit 1
  fi
  echo "all generated files up to date"
fi
