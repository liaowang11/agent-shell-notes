---
title: Send a review to an agent-shell session in the claude style
status: open
labels: [ready-for-agent]
assignee:
blocked-by: [003]
---

## What to build

From the review, `C-c C-c` renders the marked notes (or the note at point)
and the request in the `claude` style, asks for a live agent-shell session,
and sends the text as one prompt. `w` copies the same text instead.
Design: §5.1 (request body mechanism), §6.1, §6.2, §6.4, §8 shared rules,
§8.1 (file notes and request only).

## Acceptance criteria

- [ ] The request body is always editable; everything else stays read-only; typing `m` in the request inserts an `m`.
- [ ] `claude` rendering of file notes matches golden files: `In \`path\` at line N:` / `at lines S-E:`, fence one backtick longer than the longest run inside (min 3), language from the extension table then major mode then `text`, trailing whitespace trimmed, snippet-line and path sanitizing, request after two blank lines, request-only send.
- [ ] A note whose project differs from the target's uses an absolute path.
- [ ] The client is a plist (`:read-session`, `:send`, `:name`, `:session-id`, `:turn-count`); the agent-shell client picks over all live shells sorted last target, then matching projects, then the rest, and sends through the prompt-send seam with `agent-shell-notes-agent-shell-disposition`.
- [ ] No live shell: `user-error`, review untouched. No marks and no note at point: `user-error`.
- [ ] A send counts when the send seam returns normally; an error leaves notes, marks and request unchanged.
- [ ] `w` copies the rendered text and changes nothing.
- [ ] Tests stub only the process boundary (prompt-send, the shell picker, the shell list).

## Blocked by

- [Mark notes in the review](03-marks.md)
