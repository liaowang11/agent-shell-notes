---
title: Request body without its own keymap
status: closed
labels: [ready-for-agent]
assignee: claude
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

- [x] The request body has no `keymap` text property; `agent-shell-notes--request-map` is gone.
- [x] In the body, every printable key the review map binds resolves to the global binding (typing inserts); outside it, the note commands still run.
- [x] `C-c C-c` in the body sends; edit mode, after-send clearing and restore-last of the request behave as before.
- [x] With evil loaded and the buffer in normal state, `i` and `j` in the body resolve to evil's commands (test skips when evil is absent, like the popup test).
- [x] `agent-shell-notes-in-request-p` is public, documented, and covered by a test.
- [x] DESIGN.md and README.md describe the new mechanism; the README's evil Q&A no longer says the request needs Emacs state.

## Comments

Decision by Bill, 2026-10-12, while planning the Doom config. Probe facts:
~/PARA/projects/agent-shell-notes-impl/doom-config-plan.md §2 facts 1-2.

Claude, 2026-10-12, implementation.

- SHAs: 2eaa2cc claim; f2c38f3 feat (code + tests); b2dbda2 docs
  (DESIGN §5.1-5.3, §10, §11, README); 289bc80 docstring escape and a
  stale test comment.
- Decisions:
  - `agent-shell-notes--outside-request` wraps a command as
    `(menu-item "" CMD :filter ...)`. Wrapped: every printing key plus
    `RET` and `TAB`. Plain: `C-c C-c`, `C-c C-r`, `C-c C-e`, `C-x C-q`,
    `mouse-1` (same as before: the old request map let them through).
  - A filter returning nil skips the keymap's parent too (batch probe: a
    filtered child `RET` resolved to global `newline`, not the parent's
    binding). So in the body `RET` and `TAB` return
    `markdown-mode-map`'s binding (`markdown-enter-key`,
    `markdown-cycle`), as they did under the old request map. Printing
    keys return nil; markdown-mode-map binds none of them.
  - `agent-shell-notes--refuse-in-request` now calls the public
    predicate; M-x note commands from the body still `user-error`.
  - Four existing tests pressed `g`, `x`, `w` through the test helper
    with point in the body, which a real keypress could never do (the
    old request map typed the letter). They now move to a note first.
- Verified: `make check` green (compile with error-on-warn, 156 pass, 2
  evil tests skip), also with `TMPDIR` under $HOME. Evil ERT (evil from
  straight/build-31.1.50 on the load path): 2/2 pass; the new evil test
  failed first with `i` -> `undefined`. Manual batch probe (evil,
  evil-snipe, evil-markdown, Emacs 31.1.50), point in a non-empty body:
  normal `i` evil-insert, `j`/`k` evil-next/previous-line, `x`
  evil-delete-char, `C-c C-c` send, no `keymap` char property; insert and
  Emacs state `m`/`n` self-insert, `RET` markdown-enter-key; outside the
  body, Emacs state `n`/`m`/`RET` run the note commands; a user
  normal-state `J` wrapped with the predicate (README example) is
  evil-join in the body and next-note outside.
- Unverified: interactive GUI use; CI runs without evil, so the evil test
  skips there.
- Open, for the Doom config (plan §2 fact 3): its `[remap markdown-cycle]`
  -> `agent-shell-notes-toggle-quote` in the review map also remaps the
  body's `TAB` fallback, so `TAB` in the body runs toggle-quote, which
  `user-error`s. Wrap that remap with the same `:filter` (or drop it in
  the body). Package behavior without the remap is correct.
