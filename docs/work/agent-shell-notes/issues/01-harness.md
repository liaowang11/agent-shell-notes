---
title: Stand up the package and test harness
status: open
labels: [ready-for-agent]
assignee:
blocked-by: []
---

## What to build

A buildable, testable empty package. `make check` byte-compiles
`agent-shell-notes.el` with warnings as errors and runs batch ERT against
the real agent-shell fork, Magit and markdown-mode, locally and in GitHub
Actions. Design: `DESIGN.md` §2 and §11.

## Acceptance criteria

- [ ] `agent-shell-notes.el` has a package header declaring Emacs 29.1, agent-shell and markdown-mode; Magit is a soft dependency.
- [ ] Makefile targets `compile`, `test`, `check`, `live-check`, `clean`; dependency directories are variables listed once and used by every target.
- [ ] Tests live under `tests/`; one passing test loads the package and the real agent-shell fork.
- [ ] GitHub Actions runs `make check` on push and pull request, Emacs 29.1 and snapshot, shallow-cloning the agent-shell fork at `main` head, the acp fork, shell-maker, markdown-mode, and Magit with its dependencies.
- [ ] `make check` is green locally and in CI.

## Blocked by

None (can start immediately).
