---
title: Prefer markdown-ts-mode, fall back to markdown-mode
status: open
labels: [ready-for-agent]
assignee:
blocked-by: [018]
---

## What to build

Bill's decision: the review and the capture popup use `markdown-ts-mode`
when it is available (the mode is defined and the `markdown` tree-sitter
grammar is ready, `treesit-ready-p` with QUIET), else `markdown-mode`.
markdown-ts-mode ships in Emacs 31 (disabled there by default, but
present); Emacs 29.1 and machines without the grammar keep markdown-mode,
which stays a dependency. Design: §2, §4.4, §5.

Constraints:
- The chosen parent is decided when the package loads, through a
  defcustom (e.g. `agent-shell-notes-markdown-mode`, values `auto`
  default, `markdown-ts-mode`, `markdown-mode`); document that changing it
  needs a reload. Keep byte-compile clean with warnings as errors on
  Emacs 29.1 (no markdown-ts-mode there) and on snapshot.
- The chosen parent's mode hook must run, its keymap must be the parent of
  the review and capture maps, and `derived-mode-p` must report the real
  parent, on 29.1 and on 31.
- Everything markdown-mode-specific in the package keeps working under
  either parent: quote folding (`TAB`, the package's own invisibility),
  the request-filtered `RET`/`TAB` fall-through (ticket 17 looks up
  `markdown-mode-map` explicitly; use the active parent's map), fence
  language highlighting, the capture popup, edit mode, the faces from
  [Location and tag faces survive font-lock](18-faces-survive-font-lock.md).
  List any markdown-mode feature that has no markdown-ts equivalent (e.g.
  `markdown-shifttab` group folding) and what replaces it or why it is
  dropped.
- Known trap: markdown-ts-mode registers markdown-mode as a parent with
  `derived-mode-add-parents`, but `markdown-mode-hook` does not run under
  it (memory note markdown-ts-mode-emacs-31).

## Acceptance criteria

- [ ] With the grammar available, a new review and capture buffer derive from `markdown-ts-mode`; without it (or with the option set to `markdown-mode`), from `markdown-mode`.
- [ ] The full suite passes under both parents: in CI (fallback), and locally on Emacs 31 with the grammar on `treesit-extra-load-path` (the ts run is a separate Makefile target or a variable, documented; tests needing the grammar skip when it is absent).
- [ ] Faces, folding, request typing, jump, edit mode and send behave the same under both parents (tests per behavior, parameterized over the parent where cheap).
- [ ] DESIGN.md, README.md (requirements, customization, Q&A) describe the choice and the fallback.

## Comments

Decision by Bill, 2026-10-12.
