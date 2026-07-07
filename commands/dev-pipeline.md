---
description: Run a feature/bugfix through requirements -> design -> implementation -> test -> review -> PR, delegating each phase to a dedicated subagent.
argument-hint: <task description>
---

Task: $ARGUMENTS

Run this task through the full dev pipeline, using the Agent tool to delegate each phase to its dedicated subagent. Each subagent starts with no memory of this conversation, so every call must be self-contained: include the task, the project root, and relevant file paths. Do not perform the phases yourself — delegate and synthesize.

Every phase's subagent writes its output document to `<project_root>/docs/` (creating the directory on first use) instead of only returning it as text — this is the durable record of the pipeline run. Tell each subagent the project root explicitly. When delegating to a later phase, point it at the doc path(s) from earlier phases (e.g. "read `docs/requirements.md` and `docs/design.md` first") rather than pasting their full contents into the prompt — the subagent has Read access and the file is authoritative.

**Lessons learned (failure recall).** `<project_root>/docs/lessons-learned.md` is a cumulative log, separate from the per-run docs above: it is never overwritten, only appended to, and it survives across pipeline runs so past failures inform future ones. Before phase 1, check whether it exists. If it does, tell every subagent you call in this run to read it first (e.g. "also read `docs/lessons-learned.md` and apply any lessons relevant to your phase before you start") — the file has Read access for all of them.

Whenever a retry loop in phases 4, 5, or 6 below fires (a test failure, a blocking review finding, or a publish blocker), once it's resolved — or once the retry budget is exhausted and you stop — append one entry to `docs/lessons-learned.md` yourself (create the file with a `# Lessons Learned` heading if it doesn't exist yet). Use today's date and this shape:

```
## YYYY-MM-DD — <phase> — <short title>
- **Failure**: what broke, concretely
- **Root cause**: why it happened
- **Fix**: what resolved it (or "unresolved — pipeline stopped" if the retry budget ran out)
- **Prevention**: concrete, actionable guidance for that phase's subagent next time (what to check/do differently)
```

Keep entries short and specific — this file is only useful if it stays skimmable; don't log routine, non-recurring issues (e.g. a one-off typo the implementer fixed on its own without a retry loop).

Phases, in order:

1. **Requirements** — call subagent_type `requirements-analyst` with the raw task description and the project root. It writes `docs/requirements.md`. If it reports open questions that materially affect design, resolve them with the user via AskUserQuestion before continuing (don't guess on anything that changes scope) — update the file yourself if the resolution changes its content, or note the resolution when briefing the next phase.

2. **Design** — call subagent_type `software-architect`, pointing it at `docs/requirements.md`. It writes `docs/design.md`. Show the user a brief summary (files affected + approach, a few sentences) and confirm before moving on if the change is non-trivial (multiple files, new dependencies, architectural change). For small/obvious changes you may proceed without pausing.

3. **Implementation** — call subagent_type `implementer` once per implementation step from the design (or batch tightly-related small steps together), pointing it at `docs/requirements.md` and the relevant slice of `docs/design.md`, plus exact file paths. Each call appends to `docs/implementation-notes.md`.

4. **Testing** — call subagent_type `test-engineer`, pointing it at `docs/requirements.md` and `docs/implementation-notes.md`. It writes `docs/test-report.md`.
   - If it reports failures: route the failure details back to a new `implementer` call to fix, then re-run `test-engineer`. Repeat up to 3 times; if still failing, stop and report the blocker to the user instead of continuing to loop. Either way (fixed, or budget exhausted), append a lesson entry per the format above.

5. **Review** — call subagent_type `code-reviewer`, pointing it at `docs/requirements.md`, `docs/design.md`, and `docs/implementation-notes.md`. It writes `docs/review.md`.
   - If there are correctness-level (not stylistic) findings: route them back to `implementer` to fix, then re-run `test-engineer` and `code-reviewer` again. Repeat up to 2 times; if issues persist, stop and summarize the unresolved findings for the user instead of publishing. Either way, append a lesson entry per the format above.

6. **Publish** — before calling `pr-publisher`, explicitly ask the user for confirmation (this pushes to a remote and opens a PR — a visible, hard-to-reverse action). Once confirmed, call subagent_type `pr-publisher`, pointing it at `docs/requirements.md`, `docs/design.md`, and `docs/test-report.md` so it can write an accurate PR body. It also saves `docs/pr-description.md`.
   - If it stops instead of publishing (no `gh` auth, no remote, suspected secrets, wrong branch), append a lesson entry per the format above so the next run avoids the same blocker.

Throughout: give the user a one-line status update between phases (what finished, what's next, which doc was written) rather than dumping each subagent's full raw output. At the end, report the PR URL (or wherever the pipeline stopped and why), and remind the user the full trail is in `docs/`, including `docs/lessons-learned.md` if this run added to it.
