---
title: "Review buffer: own buffer or the session's compose buffer"
type: grilling
status: closed
assignee: claude
blocked-by: [001]
---

## Question

Where does a session's review live? Options to weigh: a package-owned
Markdown buffer per session that is sent as one prompt, or appending notes
straight into the session's agent-shell compose draft so agent-shell's own
submit sends it. Decide which, and what "send as is" and "edit then send"
mean in that choice.

## Resolution

Grilled with Bill, 2026-10-11.

- Each target session gets its own package-owned Markdown review buffer.
  agent-shell's compose buffer is never touched: capture would need focus to
  append to it, and queue edit, insert and agent-shell-side overwrite it.
- Bill edits the review in that buffer. Three ways to finish:
  - **send** (`C-c C-c`): deliver the review as one prompt. "Send as is"
    means sending with no edits.
  - **copy-and-discard**: put the exact text send would deliver on the kill
    ring, then kill the review without asking. Also the fallback for any
    client the package does not integrate.
  - **discard** (`C-c C-k`): kill the review, confirming if it holds notes.
- Sending goes through a client seam with two customizable steps: resolve
  the target session, then send text to it. v1 ships only the agent-shell
  client. Its send step calls `agent-shell--prompt-send`
  (`agent-shell-prompt-queue.el:450`, agent-shell 70616c4a), wrapped in one
  place. `:disposition` comes from a defcustom: nil (default, defers to
  `agent-shell-busy-submit-default-function`), `queue` or `steer`. The option
  belongs to the agent-shell client only.
- If the target session is gone, the review buffer stays and send signals an
  error; the text is kept. Killing a review buffer with unsent notes asks
  for confirmation.
- Glossary: Note, Review, Send, Client, Target session (`GLOSSARY.md`).

## Comments

- 2026-10-11: Superseded in part by
  [When a review picks its target session](003-target-session.md): one
  global review instead of one per target session; the target is picked at
  send; dired-style `S` / `w` replace the three finishing keys. The client
  seam, `agent-shell--prompt-send`, the disposition defcustom and the
  gone-target error still stand.
- 2026-10-11: [What one captured note looks like](004-entry-format.md)
  brings `C-c C-c` back as send (`S` is gone), adds `C-u C-c C-c` to fill
  the compose buffer and an optional `compose` step in the client seam.
