---
title: Stand up the package and test harness
status: closed
labels: [ready-for-agent]
assignee: claude
blocked-by: []
---

## What to build

A buildable, testable empty package. `make check` byte-compiles
`agent-shell-notes.el` with warnings as errors and runs batch ERT against
the real agent-shell fork, Magit and markdown-mode, locally and in GitHub
Actions. Design: `DESIGN.md` §2 and §11.

## Acceptance criteria

- [x] `agent-shell-notes.el` has a package header declaring Emacs 29.1, agent-shell and markdown-mode; Magit is a soft dependency.
- [x] Makefile targets `compile`, `test`, `check`, `live-check`, `clean`; dependency directories are variables listed once and used by every target.
- [x] Tests live under `tests/`; one passing test loads the package and the real agent-shell fork.
- [x] GitHub Actions runs `make check` on push and pull request, Emacs 29.1 and snapshot, shallow-cloning the agent-shell fork at `main` head, the acp fork, shell-maker, markdown-mode, and Magit with its dependencies.
- [x] `make check` is green locally and in CI.

## Blocked by

None (can start immediately).

## Comments

Done in 5808c23, 90ab338, 0fefd8b. `make check` green locally (Emacs
31.1.50) and in CI run 38149231441 (29.1 and snapshot, 2 tests each).
`make live-check` fails with a missing `agent-shell-notes-live` until the
send-all ticket adds the live test.
