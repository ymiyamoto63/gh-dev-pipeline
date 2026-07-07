---
description: Run a feature/bugfix through requirements -> design -> implementation -> test -> review -> PR, delegating each phase to a dedicated subagent.
argument-hint: <task description>
---

Task: $ARGUMENTS

Run this task through the full dev pipeline, using the Agent tool to delegate each phase to its dedicated subagent. Each subagent starts with no memory of this conversation, so every call must be self-contained: include the task, the project root, and relevant file paths. Do not perform the phases yourself — delegate and synthesize.

**Language: All output documents and GitHub Issue content must be written in Japanese.**

**Document directory:** Every phase's subagent writes its output document to `<project_root>/docs/<issue-number>/` (where `<issue-number>` is the GitHub Issue number assigned in phase 1). The directory is created after phase 1 when the issue number is known. Tell each subagent the exact docs directory path explicitly. When delegating to a later phase, point it at the doc path(s) from earlier phases rather than pasting their full contents into the prompt — the subagent has Read access and the file is authoritative.

**Lessons learned (failure recall).** `<project_root>/docs/lessons-learned.md` is a cumulative log, separate from the per-run docs above: it is never overwritten, only appended to, and it survives across pipeline runs so past failures inform future ones. Before phase 1, check whether it exists. If it does, tell every subagent you call in this run to read it first (e.g. "also read `docs/lessons-learned.md` and apply any lessons relevant to your phase before you start") — the file has Read access for all of them.

Whenever a retry loop in phases 4, 5, or 6 below fires (a test failure, a blocking review finding, or a publish blocker), once it's resolved — or once the retry budget is exhausted and you stop — append one entry to `docs/lessons-learned.md` yourself (create the file with a `# Lessons Learned` heading if it doesn't exist yet). Use today's date and this shape:

```
## YYYY-MM-DD — <phase> — <short title>
- **失敗**: 具体的に何が壊れたか
- **根本原因**: なぜ発生したか
- **修正**: 何が解決したか（リトライ予算が尽きた場合は「未解決 — パイプライン停止」）
- **予防策**: 次回同フェーズのサブエージェントへの具体的・実行可能な指針
```

Keep entries short and specific — this file is only useful if it stays skimmable; don't log routine, non-recurring issues (e.g. a one-off typo the implementer fixed on its own without a retry loop).

Phases, in order:

1. **Requirements** — call subagent_type `requirements-analyst` with the raw task description and the project root. It writes `docs/requirements.md` (temporary location before issue number is known). **All document content must be in Japanese.** If it reports open questions that materially affect design, resolve them with the user via AskUserQuestion before continuing (don't guess on anything that changes scope) — update the file yourself if the resolution changes its content, or note the resolution when briefing the next phase.

   After the requirements doc is written, **create a GitHub Issue** using `gh issue create`:
   - Title: task summary in Japanese (concise, one line)
   - Body: the full content of `docs/requirements.md`
   - Label: `requirements` if it exists, otherwise no label
   
   Capture the issue number from the output (e.g. `gh issue create` prints the URL — extract the number). Then move `docs/requirements.md` to `docs/<issue-number>/requirements.md` (create the directory first). All subsequent docs go into `docs/<issue-number>/`.

2. **Design** — call subagent_type `software-architect`, pointing it at `docs/<issue-number>/requirements.md`. It writes `docs/<issue-number>/design.md`. **All document content must be in Japanese.** Show the user a brief summary (files affected + approach, a few sentences) and confirm before moving on if the change is non-trivial (multiple files, new dependencies, architectural change). For small/obvious changes you may proceed without pausing.

   After the design doc is written, **update the GitHub Issue** by posting a comment using `gh issue comment <issue-number>`:
   - Body: `## 設計\n\n` followed by the full content of `docs/<issue-number>/design.md`

3. **Implementation** — call subagent_type `implementer` once per implementation step from the design (or batch tightly-related small steps together), pointing it at `docs/<issue-number>/requirements.md` and the relevant slice of `docs/<issue-number>/design.md`, plus exact file paths. Each call appends to `docs/<issue-number>/implementation-notes.md`. **All document content must be in Japanese.**

4. **Testing** — call subagent_type `test-engineer`, pointing it at `docs/<issue-number>/requirements.md` and `docs/<issue-number>/implementation-notes.md`. It writes `docs/<issue-number>/test-report.md`. **All document content must be in Japanese.**
   - If it reports failures: route the failure details back to a new `implementer` call to fix, then re-run `test-engineer`. Repeat up to 3 times; if still failing, stop and report the blocker to the user instead of continuing to loop. Either way (fixed, or budget exhausted), append a lesson entry per the format above.

5. **Review** — call subagent_type `code-reviewer`, pointing it at `docs/<issue-number>/requirements.md`, `docs/<issue-number>/design.md`, and `docs/<issue-number>/implementation-notes.md`. It writes `docs/<issue-number>/review.md`. **All document content must be in Japanese.**
   - If there are correctness-level (not stylistic) findings: route them back to `implementer` to fix, then re-run `test-engineer` and `code-reviewer` again. Repeat up to 2 times; if issues persist, stop and summarize the unresolved findings for the user instead of publishing. Either way, append a lesson entry per the format above.

6. **Publish** — before calling `pr-publisher`, explicitly ask the user for confirmation (this pushes to a remote and opens a PR — a visible, hard-to-reverse action). Once confirmed, call subagent_type `pr-publisher`, pointing it at `docs/<issue-number>/requirements.md`, `docs/<issue-number>/design.md`, and `docs/<issue-number>/test-report.md` so it can write an accurate PR body. It also saves `docs/<issue-number>/pr-description.md`. Include `Closes #<issue-number>` in the PR body so the Issue closes automatically on merge.
   - If it stops instead of publishing (no `gh` auth, no remote, suspected secrets, wrong branch), append a lesson entry per the format above so the next run avoids the same blocker.

Throughout: give the user a one-line status update between phases (what finished, what's next, which doc was written) rather than dumping each subagent's full raw output. At the end, report the PR URL (or wherever the pipeline stopped and why), and remind the user the full trail is in `docs/<issue-number>/`, including `docs/lessons-learned.md` if this run added to it.
