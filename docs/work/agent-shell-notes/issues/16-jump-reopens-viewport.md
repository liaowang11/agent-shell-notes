---
title: Jump reopens a closed viewport
status: closed
labels: [ready-for-agent]
assignee: claude
blocked-by: [011]
---

## What to build

Jumping to a transcript note captured in a viewport, after that viewport
buffer was killed while its shell still lives, reopens the shell's
viewport, shows the note's turn page, goes to the quoted location and
flashes it. Today it signals "Source buffer is gone". Design: §9 step 4.

## Acceptance criteria

- [x] Viewport dead, shell live: the shell's viewport is reopened on the page of the note's `:turn`, point is at the quote, the range is pulsed.
- [x] Viewport dead and shell dead: `user-error "Source buffer is gone"`, as before.
- [x] A note whose turn page no longer exists (or has no turn) falls back to the viewport's latest page without error.
- [x] Tests use a real shell buffer and real viewport code; only the process boundary is stubbed (§11).

## Blocked by

- [Jump from the review back to the source](11-jump.md)

## Comments

Decision by Bill, 2026-10-12, after the code review flagged the §9 gap.

claude, 2026-10-12. Commits: 6e5ae8c (claim), 3ae82ae (reopen on the
note's turn), 8870d62 (fallbacks, quote search by line, draft parking).

- `--jump-dead` has a `transcript` arm: the shell is the one among
  `agent-shell-buffers` whose `agent-shell-session-id :shell-buffer`
  equals the note's `:session-id` (so a renamed shell still counts) →
  `agent-shell-notes--jump-viewport`; no such shell, or a note with no
  session id, → `user-error "Source buffer is gone"`. A shell under the
  note's name on another session counts as gone. Nothing tells whether
  the dead source was a viewport; none is needed, since a live shell as
  source takes the live path.
- Reopen: `agent-shell-viewport--buffer :shell-buffer` (creates it),
  `agent-shell-viewport-view-mode`, `agent-shell-viewport--show-page`
  with `:turn` when 1 <= turn <= turns, else the last turn. `--show-page`
  rather than `view-last`: same page code, and it signals on a bad
  index, so the bound is checked first. No turns at all: an empty view
  page (`--initialize`), no flash.
- A compose draft in a viewport opened after the old one was killed is
  parked in `--compose-snapshot` before paging erases it, as `view-last`
  does.
- Locating the quote: the markers died with the buffer, so this is a
  search. `:quote` is Markdown and the page is rendered, but the page is
  a `buffer-substring` of the shell (agent-shell.el:11777-11778), so
  rendered spans keep `agent-shell-markdown-source`
  (agent-shell-markdown.el:614-616). `agent-shell-notes--page-markdown`
  rebuilds the page's Markdown with each char mapped back to its buffer
  range (a span maps to the whole span). Search order: the whole quote,
  then each of its lines (synthesized `### [label]` headings never
  match); each first in the Markdown, then in the visible text, since a
  region that began inside a span gets that span's visible text. The
  match range is flashed; nothing found → page start, no flash.
- Fork finding, not fixed here: `agent-shell--update-fragment` renders
  no Markdown, tags no field and stamps no message id when
  `agent-shell-section-functions` is nil and there is no late prompt.
  `tracked-ranges` (agent-shell.el:7570-7577) is nil then and sits in
  the same `when-let*` as the range, so the whole post-insert step is
  skipped. That is why earlier fixtures kept `**bold**` literal. The
  rendered-markup test binds `agent-shell-section-functions` to
  `(list #'ignore)` while building its shell. Whether live shells hit
  this depends on that hook being set; not checked.
- No stubs: the jump tests run `--show-page`, `--initialize`,
  `--position` and `--update-header` for real on the fake shell, so §11
  needs no new entry.

Second round: 1e9e426 (shell by session id), f3f4e7e (Markdown-source
search).

Verified: `make check` green (155 tests, evil test skipped). Seven tests
through `RET` in the review: reopen on turn 1 while the shell's point is
on turn 2 (page, mode, point, one pulse); viewport and shell dead; `:turn`
9 and nil → latest page; turn 2 deleted from the shell and an empty
shell; heading-led and absent quotes; draft parking; a rendered
`**bold**` page (whole-line quote via the source, a quote starting inside
the span via visible text); a renamed shell on the note's session
reopens, the note's name on another session is gone. Mutations (no
bound check, no zero-turn branch, no draft parking, first-line-only
search, no visible-text fallback) each fail a test; the by-name lookup
and the visible-only search failed the new tests before the change.

Unverified: a live viewport (constructs other than bold, e.g. code
blocks, tables, links, carry the same property but are not tested);
quotes with `###` headings and `...` from `--buffer-markdown-substring`
fall back to their first matching line; the real flash in a GUI frame.
