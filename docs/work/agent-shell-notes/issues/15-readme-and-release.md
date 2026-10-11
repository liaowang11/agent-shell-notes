---
title: README and release hygiene
status: open
labels: [ready-for-agent]
assignee:
blocked-by: [011, 012, 013, 014]
---

## What to build

A README that lets someone install and use the package, and a clean
release state. Design: §2 (bindings suggested, Doom-agnostic), §10.

## Acceptance criteria

- [ ] README: what it does, install, the three entry commands with suggested bindings, the review and popup keys, the options from §10, a note that Doom popup rules and leader keys are the user's config.
- [ ] Commentary header matches the README's summary.
- [ ] `checkdoc` clean; byte-compile clean on Emacs 29.1 and snapshot in CI.
- [ ] Every option and face in §10 exists with a docstring.

## Blocked by

- [Jump from the review back to the source](11-jump.md)
- [The codex style](12-codex-style.md)
- [The omp style](13-omp-style.md)
- [send-all and the live round trip](14-send-all-and-live-check.md)
