---
title: What happens to a review after it is sent
type: grilling
status: closed
assignee: Bill
blocked-by: [002]
---

## Question

After `C-c C-c` sends, `C-u C-c C-c` fills a compose buffer, or `w` copies
some notes from the one global review
([What one captured note looks like](004-entry-format.md)): do those
notes leave the review, stay marked as sent (and to which session), or stay
until Bill deletes them? What happens to their marks, and to the request section?

Busy-shell behavior is settled in
[Review buffer: own buffer or the session's compose buffer](002-review-buffer.md)
(a disposition defcustom, nil defers to agent-shell). Relevant fact:
`agent-shell--prompt-send`'s `:on-delivered` fires on submit and steer, never
on queue, so "clear only once delivered" cannot cover a queued review.

## Resolution

Grilled with Bill, 2026-10-11.

- **After-send option**: a defcustom `agent-shell-annotations-after-send`
  picks what a successful send does to the notes that went out: `remove`
  (default), `archive` or `keep`. A command sets it for the Emacs session.
  A failed send changes nothing.
- **Which actions apply it**: `C-c C-c` and `C-u C-c C-c` (fill compose)
  both apply the option. `w` always leaves notes, marks and request as they
  are.
- **When a send counts**: once `agent-shell--prompt-send` accepts the text,
  whatever the disposition. It does not wait for `:on-delivered`, which never
  fires for a queued prompt. agent-shell's queue edit is how Bill gets a
  queued review back.
- **Archived note** (superseded 2026-10-18 by
  [Hide archived notes, show them in their own section](../../work/agent-shell-notes/issues/23-hide-archived-notes.md):
  hidden by default, shown under `# Archived`): stays in place in its group, dimmed, tagged
  `sent to <session>` with the latest target. It can be marked and sent
  again, which updates the tag. `t` skips archived notes. `x` deletes every
  archived note without asking.
- **Marks** clear after a send in every mode, so the next `C-c C-c` doesn't
  resend by accident. Under `keep` the notes get no tag.
- **Request**: goes with every send, including a send of some marked notes,
  and clears after a send or compose in every mode. `w` copies it and
  leaves it in place.
- **Restore last**: the package keeps one level of the last send or compose
  (notes, their prior tags, marks, request) for the Emacs session. A command
  (also bound in the review) undoes that send's effect on the review: under
  `remove` it puts the notes back in place, under `archive` it restores their
  old tags. In every mode it restores the request and the marks.
- This drops the "copy-and-discard" of
  [Review buffer: own buffer or the session's compose buffer](002-review-buffer.md):
  copy never removes anything.
- Glossary: Archived note added.
