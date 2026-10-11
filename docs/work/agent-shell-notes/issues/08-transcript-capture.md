---
title: Capture from an agent-shell transcript
status: open
labels: [ready-for-agent]
assignee:
blocked-by: [004]
---

## What to build

Capture in shell and viewport buffers, grouped by session, turn and block
kind, rendered in the `claude` style as Claude's native reply blocks when
sent to the note's own session. Design: §4.3, §5.1 (transcript groups),
§8.1 (reply blocks and other-session quotes).

## Acceptance criteria

- [ ] Block kind comes from the fragment's qualified id (message, thought, tool, plan, prompt, permission, mixed); a region may cross blocks and turns, prompts and permissions included.
- [ ] Turn index comes from the shell's turn position, or the viewport page cursor on a history page; the note records session id, shell name, turn and the prompt's first line.
- [ ] The quote is the agent's Markdown via the copy-as-markdown reconstruction; capture during a streaming turn works.
- [ ] Review groups by session + turn + kind, shows the turn index, never sends it.
- [ ] `claude`: notes on the target's own session render as `<!-- reply K -->` blocks (K = block count, max 99, later blocks `<!-- reply -->`), `> `-quoted, text with 3+ newlines squeezed and `<!-- reply` escaped, placed first, two blank lines before the rest; other-session notes render as a plain quote and text. "Own session" is decided at render from the client's session id.
- [ ] Tests render transcripts with the fork's real fragment code on a fake state, no ACP process.
- [ ] §12 checks 1, 2, 6 and 7 are answered in the ticket's comments.

## Blocked by

- [Send a review to an agent-shell session in the claude style](04-send-claude.md)
