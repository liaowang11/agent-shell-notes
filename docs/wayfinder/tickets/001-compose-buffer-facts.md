---
title: Can agent-shell's compose buffer hold a review?
type: research
status: closed
assignee: claude (agent-shell-annotations-f4)
blocked-by: []
---

## Question

What does agent-shell (Bill's fork, `~/Repositories/forks/agent-shell`) offer
as a per-session place for a long draft, and would it work as the review
buffer for that session? Find out:

- Is there one compose/draft buffer per session (viewport compose buffer,
  the shell's prompt region, `agent-shell-side`'s compose flow)? How is it
  created, found from another buffer, and killed?
- Does a draft survive the shell being busy, a turn finishing, the viewport
  paging, and the compose buffer being closed and reopened?
- How does a draft get submitted, queued, or steered, and can a caller append
  to it without stealing focus?
- What happens for a shell used without the viewport?
- How Bill's private Doom config (`config.org`) sets up
  viewport and compose usage today.

Answer with file:line citations. Facts only; the choice is the next ticket.

## Resolution

Findings: `docs/research/05-compose-buffer-facts.md` on local branch
`research/compose-buffer-facts` (45eb875, not pushed). Sources: agent-shell
70616c4a, agent-shell-side 68a950fb, and Bill's private Doom config.

- Each session has one compose surface, `<shell> [viewport]`, shared with the
  history viewer and linked to the shell by buffer name only. With Bill's
  `agent-shell-prefer-viewport-interaction t`, insert, send-region,
  send-dwim, prompt-compose, queue edit and agent-shell-side all write into
  that one buffer; queue edit erases it without asking.
- A caller cannot append without taking focus: `:no-focus` and `:submit`
  signal "Not yet supported"; each append also resets the queue/steer choice.
- A draft survives streaming, turn end and paging. It is lost on send, on
  viewport or shell kill/restart/rename, and on a busy-shell show path that
  switches to view mode without saving (run).
- It is `text-mode` with a two-space prefix, not Markdown.
- Sending needs no compose buffer: `agent-shell--prompt-send` sends text from
  code and routes busy shells (steer by default, queue as fallback).
- Correction to 03a: `agent-shell-insert` from a Magit or file buffer takes
  focus under prefer-viewport; agent-shell-side calls
  `agent-shell--insert-to-shell-buffer` directly instead.

Runs used a fake shell with stubs, not a live ACP session.
