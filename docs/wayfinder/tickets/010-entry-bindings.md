---
title: Which entry commands and bindings ship, and what Doom adds
type: grilling
status: closed
assignee: claude
blocked-by: []
---

## Question

Keys inside the review and the capture popup are decided
([What one captured note looks like](004-entry-format.md),
[How the capture popup behaves](005-capture-popup.md)). Still open: the
global entry points (capture, open the review, send) and where their
bindings live. Decide what the package ships (no global bindings, a prefix
keymap for the user to bind, or bindings in source-mode maps such as
Magit's and agent-shell's) and what Bill's Doom config adds on top: leader
or localleader keys, and `set-popup-rule!` entries for the capture popup
(Doom's org-capture rule, `:size 0.42 :quit nil :select t`, is prior art)
and for the review buffer.

## Resolution

Grilled with Bill, 2026-10-11. The package is standalone: it knows nothing
of Doom, leader keys or popup rules. Bill's Doom bindings and
`set-popup-rule!` entries are his config's business, out of scope here.
Facts checked: agent-shell, agent-shell-side, -vertico, -tramp and
-bookmark ship no global bindings and no `*-command-map`; Magit's
`C-c C-<letter>` space is crowded.

- **Global entry commands**: `agent-shell-notes-capture`,
  `agent-shell-notes-review` (opens the review or switches to it) and
  `agent-shell-notes-send-all`. `agent-shell-notes-send` is the review's
  `C-c C-c` command, not a global entry point.
- **`agent-shell-notes-send-all`**: picks a target session and sends every
  note that is not archived, without opening the review, as if all of
  them were marked and `C-c C-c` pressed in the review: marks are ignored,
  a non-empty request follows the notes, and `after-send`, restore-last
  and the clearing of marks and request apply as they do for `C-c C-c`.
  With `C-u` it fills the target's compose buffer instead, like
  `C-u C-c C-c`. No confirmation beyond the picker. No unarchived notes:
  `user-error` before the picker; no live shell: the same `user-error`
  as `C-c C-c`. A client without `compose`: `C-u` gives a `user-error`
  naming the client and changes nothing.
- **Bindings**: none outside the package's own buffers (review, capture
  popup). No prefix keymap, no keys in Magit or agent-shell maps, no
  transient suffixes. The README suggests bindings.
- **Display**: the capture popup keeps its customizable display action
  from [How the capture popup behaves](005-capture-popup.md); the review
  opens with plain `pop-to-buffer` through a customizable display action.
