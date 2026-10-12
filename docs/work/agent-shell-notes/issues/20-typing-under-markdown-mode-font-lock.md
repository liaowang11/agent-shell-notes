---
title: Typing survives markdown-mode font-lock
status: closed
labels: [ready-for-agent]
assignee: claude
blocked-by: []
---

## What to build

With the markdown-mode parent and `font-lock-mode` on, typing into an empty
review request signals `text-read-only`; with font-lock off, or under
markdown-ts-mode, it types. Reproduced in batch (2026-10-12):
`(setq agent-shell-notes-markdown-mode 'markdown-mode)`, open the review,
`font-lock-ensure`, `self-insert-command` at `point-max`. The writable
request body and the capture popup's note area rely on a text property
(the `rear-nonsticky (read-only)` trick in
`agent-shell-notes--insert-request`) that markdown-mode's font-lock
appears to strip. Edit-mode note slots may be hit too. Find the root cause,
fix it for every writable region, and keep markdown-ts-mode working.
Design: §4.4, §5.1, §5.3.

## Acceptance criteria

- [x] With font-lock on under the markdown-mode parent, typing works in an empty and a non-empty request, in the capture popup's note area, and in edit-mode note texts (empty and non-empty).
- [x] Same tests pass under markdown-ts-mode (`make test-ts`).
- [x] Read-only parts (headings, locations, quotes) still refuse edits with font-lock on.
- [x] Tests run real font-lock and fail on the current code.

## Comments

Found 2026-10-12 by the Doom config agent's probes; confirmed in batch.

2026-10-12 (claude): root cause. markdown-mode's `font-lock-defaults`
list `rear-nonsticky` in `font-lock-extra-managed-props`, so
`font-lock-unfontify-region` strips it from every fontified character.
Verified: the request boundary newline had `rear-nonsticky (read-only)`
before `font-lock-ensure` and lost it after. The same pattern opened the
popup's note area and edit-mode slots, so all three refused typing at
their start. markdown-ts-mode does not manage `rear-nonsticky` (so it
worked), but it does manage `category`, which ruled out a category symbol
as the fix (tried; `make test-ts` went red).

Fix (080d9cf): `agent-shell-notes--open-after` puts
`agent-shell-notes-rear-nonsticky` on the boundary character, and
`agent-shell-notes--markdown-setup` makes it an alias of `rear-nonsticky`
in a buffer-local `char-property-alias-alist`. No font-lock manages the
package's own property. DESIGN §5.1 records the mechanism.

Verified: three new tests run real font-lock (fontify, type, fontify,
type again): request empty/start/end, popup note area empty/start,
edit-mode non-empty and empty texts plus commit; each also checks
heading, location and quote stay read-only. They failed with
`text-read-only` on the old code under markdown-mode. `make check`
(170 tests, 5 skipped), `make test-ts` (2 skipped), and `make check`
with TMPDIR under $HOME pass. /tmp/asn-ro repros type under both parents.
A position-by-position probe after font-lock found no writable spot
outside the slots and the request.

Unverified: interactive typing with jit-lock in a live Emacs (only batch
`font-lock-ensure`); the new tests are not red-first under markdown-ts-mode,
since the old code already passed there.
