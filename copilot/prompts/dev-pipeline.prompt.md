---
name: dev-pipeline
description: Run a feature/bugfix through requirements -> design -> implementation -> test -> review -> PR, delegating each phase to a dedicated subagent.
argument-hint: <task description> | <path to an existing requirements doc> | resume #<issue-number>
agent: dev-pipeline
---

Run the task described with this command through the full dev pipeline, following your agent instructions (requirements → design → implementation → test → review → PR). The text the user typed after the command is the task description; if it is a path to an existing requirements document (e.g. `docs/requirements/<feature-slug>.md` written by the refine-requirements skill), start phase 1 from that document per your agent instructions — the approval gate, GitHub Issue creation, and `.scratch/<issue-number>/` setup still run as usual; if it is `resume #<issue-number>`, continue the interrupted run from the Issue's state comment per your agent instructions.
