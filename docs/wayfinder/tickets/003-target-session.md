---
title: When a review picks its target session
type: grilling
status: closed
assignee: claude
blocked-by: []
---

## Question

With one review per target session, every capture has to pick a session.
From a transcript the session is obvious. From a Magit buffer or a file it
is not. Decide the rule: project's most recent shell, the last session
captured to, ask every time, ask once per buffer, or something else, and
how Bill changes the target mid-pass. Also: what happens when no shell
exists yet.

Also decide the resolve-target step of the client seam set by
[Review buffer: own buffer or the session's compose buffer](002-review-buffer.md):
how a client lists and picks its sessions, as a customizable function, with
agent-shell as the only v1 client.

## Resolution

Grilled with Bill, 2026-10-11. Bill wants notes sent to fork or sidechat
sessions too, so capture binds no target. This supersedes part of
[Review buffer: own buffer or the session's compose buffer](002-review-buffer.md):
there is no longer one review per target session.

- Capture picks no target and never fails for lack of a shell. All notes
  collect in **one global review**. A transcript note records the session it
  came from as part of its location, not for routing.
- The review buffer is read-only Markdown, each note shown in full as the
  exact text send delivers for it. Marks are a `*` in the left margin
  (overlay), never part of the text. Dired-style keys:
  - `m` / `u`: mark / unmark the note at point, or every note the region
    touches, then move to the next note.
  - `t`: toggle all marks (from none, marks all). `U`: unmark all.
  - `n` / `p`: next / previous note.
  - `k`: delete the note at point. `D`: delete marked notes, confirming.
  - `e` / `RET`: edit the note in the capture popup; `C-c C-c` writes it
    back in place, `C-c C-k` cancels. No wdired-style whole-buffer edit in
    v1: free editing would blur note boundaries, which marks hang on.
- `S` acts on the marked notes, or the note at point when none are marked:
  it asks for the target, then sends at once, no preview. `w` copies the
  same text to the kill ring and sends nothing. These replace the
  send / copy-and-discard / discard keys of ticket 002.
- Target picker: one picker over all live shells (fork and sidechat
  sessions included), with a project column, most recent first. Projects of
  the notes being sent sort first; the last target is the first candidate.
  Crossing projects is just typing.
- No live shell at send: `user-error`, review untouched.
- Client seam: a client supplies `read-session (hint)` and
  `send (session text)`. The package passes a hint with the projects of the
  selected notes and the last target. agent-shell's client wraps
  `agent-shell--read-shell-buffer` and the `agent-shell--prompt-send` call
  (with the `:disposition` defcustom) from ticket 002. Copying needs neither.
- Glossary: Review and Target session redefined, Mark added.

## Comments

- 2026-10-11: Superseded in part by
  [What one captured note looks like](004-entry-format.md): the review is a
  display, not the exact sent text; `C-c C-c` replaces `S`
  (`C-u C-c C-c` fills the compose buffer); `RET` jumps from a location;
  a wdired-style edit mode (`C-c C-e`) replaces popup edits; the client seam
  gains an optional `compose`.
