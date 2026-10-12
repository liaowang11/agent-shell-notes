---
title: Prefer markdown-ts-mode, fall back to markdown-mode
status: closed
labels: [ready-for-agent]
assignee: claude
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

- [x] With the grammar available, a new review and capture buffer derive from `markdown-ts-mode`; without it (or with the option set to `markdown-mode`), from `markdown-mode`.
- [x] The full suite passes under both parents: in CI (fallback), and locally on Emacs 31 with the grammar on `treesit-extra-load-path` (the ts run is a separate Makefile target or a variable, documented; tests needing the grammar skip when it is absent).
- [x] Faces, folding, request typing, jump, edit mode and send behave the same under both parents (tests per behavior, parameterized over the parent where cheap).
- [x] DESIGN.md, README.md (requirements, customization, Q&A) describe the choice and the fallback.

## Comments

Decision by Bill, 2026-10-12.

Claude, 2026-10-12, implementation.

- SHAs: 23d4fa7 claim; 5846e63 feat (code, tests, Makefile `test-ts`);
  86df9c9 docs (DESIGN §2, §4.4, §5.1, §5.2, §10, §11, §13; README
  requirements, customization, Q&A, Development); f60dcf4 reload fix.
- Mechanism: `agent-shell-notes--markdown-mode` is a `defalias` to the
  mode `agent-shell-notes--choose-markdown-mode` picks at load, and both
  modes are `define-derived-mode` children of the alias. The package
  maps get the chosen mode's map as parent explicitly at load (the
  edit map lost its `:parent markdown-mode-map`). Chosen because it is
  one alias and needs no `eval` or duplicated mode forms. Evidence:
  - Emacs 29 follows an alias parent: 29.1's `provided-mode-derived-p`
    (lisp/subr.el at tag emacs-29.1) maps a parent whose
    `symbol-function` is a symbol to that symbol. So "derived-mode-p does
    not follow function aliases on 29.1" does not hold for the parent
    link. Emacs 31's `derived-mode-all-parents` follows it too.
  - Batch prototype (/tmp/asn-proto/proto.el) on 31.1.50 and on
    emacs-nox 29.4 (nixos-24.05; no 29.1 binary here): under
    markdown-mode the hooks were `text-mode-hook markdown-mode-hook
    child-hook`, `derived-mode-p 'markdown-mode` t, map parent
    `markdown-mode-map`, TAB `markdown-cycle`; under markdown-ts-mode
    (31) `text-mode-hook markdown-ts-mode-hook child-hook`,
    `derived-mode-p` t for both `markdown-ts-mode` and `markdown-mode`,
    map parent `markdown-ts-mode-map`.
  - Reload trap, fixed in f60dcf4: Emacs 30+ caches each mode's parent
    chain, the alias's included, and `defalias` does not flush it. After
    `load-library` with a new choice the review still reported
    markdown-mode, and `markdown-ts-code-block-context-mode -1` raised
    "valid only in markdown-ts-mode buffers". `(derived-mode-set-parent
    'agent-shell-notes--markdown-mode nil)` flushes it (guarded by
    `fboundp` for 29). Test added; it failed without the flush.
- Other decisions:
  - "Can run" checks `(require 'markdown-ts-mode nil t)` (not autoloaded
    in 31's -Q) and `treesit-ready-p '(markdown markdown-inline) t`.
    Both grammars, not only `markdown`: without `markdown-inline` the
    mode warns and switches the buffer to `text-mode`.
  - `markdown-ts-mode` as the option value warns (`display-warning`)
    and falls back; it never errors at load.
  - Each mode body turns off `markdown-ts-code-block-context-mode`. Its
    minor map takes `TAB` in code blocks, so `TAB` on a fenced quote
    ran `indent-for-tab-command` and hit `text-read-only` (the new
    command-loop test failed that way before the fix).
  - The request-body fall-through and the popup's `TAB` look up
    `agent-shell-notes--markdown-map`, the active parent's map.
- Features under markdown-ts-mode (README Q&A lists them):
  - `markdown-shifttab` (`S-TAB` anywhere folds all groups): no
    equivalent. Replaced by outline cycling on headings, which
    markdown-ts-mode turns on: `TAB` on a group heading folds the group,
    `S-TAB` on a heading cycles all. Under markdown-mode `TAB` on a
    heading is a no-op. A redraw unfolds groups (the draw removes all
    overlays). Covered by a ts-only test.
  - Body and note-area `TAB`/`RET` are markdown-ts-mode's
    (`markdown-ts-outline-cycle`, `markdown-ts-newline`).
  - Code-block command context: dropped in both buffers (above).
  - Fence highlighting: on by default under ts; markdown-mode needs
    `markdown-fontify-code-blocks-natively`. One test checks the text
    face under both (`get-text-property`: ts lays a block overlay with
    its own face over the code).
  - `markdown-mode-hook` does not run under ts (`derived-mode-p` still
    says markdown-mode).
- Verified: `make check` green on 31.1.50 (167 tests, 162 pass, 5 skip:
  2 evil, 3 ts-only), also with `TMPDIR` under $HOME. `make test-ts`
  (grammars from ~/.config/emacs/.local/etc/tree-sitter, Doom's
  directory) 165 pass, 2 evil skips, also with `TMPDIR` under $HOME;
  with evil on the load path 167/167. `make check EMACS=<29.4>`
  (compile with error-on-warn, then suite) green: 162 pass, 5 skip. The
  new choice and parent tests failed first; the TAB and reload tests
  failed against the code without their fix.
- Unverified: Emacs 29.1 itself (29.4 ran; the alias code path in
  `provided-mode-derived-p` is the same at 29.1 by source), CI snapshot
  (not pushed), interactive GUI use under markdown-ts-mode.
- Open, for the Doom config: its `[remap markdown-cycle]` in the review
  map does nothing under markdown-ts-mode (`TAB` there is
  `markdown-ts-outline-cycle`), so ticket 17's open item only matters
  under markdown-mode now.
