---
title: Hide archived notes, show them in their own section
status: closed
labels: [ready-for-agent]
assignee: claude
blocked-by: []
---

## What to build

Under `archive`, sent notes stay in place among the live notes, so the
review grows with every send. Hide archived notes by default; `a` shows
them, below the live notes, under an `# Archived` heading just above
`# Request`. Supersedes "stays in place in its group" from
[What happens to a review after it is sent](../../../wayfinder/tickets/006-after-send.md).

Decided with Bill, 2026-10-18: hidden by default; the setting lasts for
the Emacs session, like `set-after-send`; inside `# Archived` the notes
keep their source groups as `##` headings.

## Acceptance criteria

- [x] `agent-shell-notes-show-archived` (defcustom, default nil) decides whether the review draws archived notes; `a` in the review toggles it for the session and redraws.
- [x] Shown, archived notes leave their source groups and appear under `# Archived`, after the live groups and before `# Request`, grouped by source with `##` headings. They stay dimmed and tagged.
- [x] Hidden, nothing archived is drawn. With no live note left, the review says how many sent notes are hidden.
- [x] The header line counts live notes and groups, then `N sent`, with `(hidden)` while hidden, and hints `a show sent` / `a hide sent` when there are archived notes.
- [x] Marks on hidden notes are ignored: send, copy, `D` and the header's marked count only see shown notes. The marks come back with `a`.
- [x] `x`, `C-c C-r`, `send-all` and `t` behave as before.

## Comments

2026-10-18 (claude): done.

Order inside `# Archived` is capture order, like the live groups, not
"newest send first" as first proposed: `:archived` holds only the target
name, and a send time would need its own field and restore-last support.

`D` now drops only the deleted ids from the marks; it used to clear all
marks, which would also have dropped the marks of hidden notes. When the
note at point gets hidden, point lands where the old position falls,
possibly in the request, as after `k`.

Verified: four new tests (`agent-shell-notes-review-hides-archived-notes-by-default`,
`-a-shows-archived-in-own-section`, `-says-when-all-notes-are-hidden`,
`-ignores-marks-on-hidden-notes`) and the updated header-count test failed
first. Five tests that look at archived notes in the review now set
`agent-shell-notes-show-archived`; `after-send-archive-tags-and-dims` now
expects the archived notes below the live one. `make compile` passes;
`make test` (180, 5 skipped) and `make test-ts` (180, 2 skipped) pass
except `compose-appends-after-the-draft` and `send-all-composes-with-prefix`,
which fail the same way on the previous commit: the agent-shell fork's
compose buffer now has two extra blank lines after the draft.

Unverified: the live review in a GUI frame.

2026-10-18 (claude): follow-up after merging origin/main (4e895ee).

Send time: an `archive` send now sets `:sent` (the send time) next to
`:archived`; restore-last puts both back. `# Archived` groups go newest
send first (notes archived before this change, with no `:sent`, last),
the heading says `# Archived — newest first`, and the tag reads
`sent to <session>, 11:52` (`Oct 17 09:30` on another day).

Where it went: the tag already names the target session. A turn number
in the target was checked and left out: `:turn-count` is the count at
send time, but a queued prompt lands later and a compose may be edited
or never sent, so "turn N" would often be wrong. Possible later: record
the session id and let `RET` on the tag open the target shell.
