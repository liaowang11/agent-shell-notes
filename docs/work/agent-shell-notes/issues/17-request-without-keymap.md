---
title: Request body without its own keymap
status: open
labels: [ready-for-agent]
assignee:
blocked-by: []
---

## What to build

The review's request body carries a `keymap` text property
(`agent-shell-notes--request-map`) that binds every printable key to
`self-insert-command`, so letters insert there instead of running note
commands. A text-property keymap outranks every other map, so under evil
normal state, which remaps `self-insert-command` to `undefined`, every key
in the body is dead, `i` and `j` included.

Drop the request keymap. Make the review map's single-letter (and other
printable) note bindings conditional instead: a `menu-item` binding with a
`:filter` that returns nil when point is in the request body, so the key
falls through to the next map (the global `self-insert-command`, or an
evil state map). Keep `C-c C-c` sending from the body. Export a public
predicate, `agent-shell-notes-in-request-p`, so a user can apply the same
filter to their own bindings. Design: §5.1, §5.2, §5.3.

## Acceptance criteria

- [ ] The request body has no `keymap` text property; `agent-shell-notes--request-map` is gone.
- [ ] In the body, every printable key the review map binds resolves to the global binding (typing inserts); outside it, the note commands still run.
- [ ] `C-c C-c` in the body sends; edit mode, after-send clearing and restore-last of the request behave as before.
- [ ] With evil loaded and the buffer in normal state, `i` and `j` in the body resolve to evil's commands (test skips when evil is absent, like the popup test).
- [ ] `agent-shell-notes-in-request-p` is public, documented, and covered by a test.
- [ ] DESIGN.md and README.md describe the new mechanism; the README's evil Q&A no longer says the request needs Emacs state.

## Comments

Decision by Bill, 2026-10-12, while planning the Doom config. Probe facts:
~/PARA/projects/agent-shell-notes-impl/doom-config-plan.md §2 facts 1-2.
