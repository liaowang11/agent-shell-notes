---
title: Confirm the Claude desktop diff-comment template from a real session
type: task
status: closed
assignee: claude
blocked-by: []
---

## Question

The `claude` style copies the Code-tab diff-comment template found only in
the cached claude.ai bundle
(`docs/research/agent-apps/claude-desktop-diff-comments.md`); no real
transcript has one, the fence info strings and `withReplies` are
unconfirmed, and the docs' wording ("at `src/auth.ts:47`") disagrees.

HITL: Bill submits one Code-tab diff comment on a range and one on a deleted
line, with and without a typed message. AFK: read that session's user turn
in its JSONL under `~/.claude/projects/` and record the exact text. Update
the `claude` row of
[What one captured note looks like](004-entry-format.md) if it differs.

## Resolution

Done 2026-10-11. Bill sent comments from the Code tab in a
Claude Code session in another repo.
The exact user turns:

````
In `README.md` at line 7:
```markdown
<!-- TEMP: diff-pane test edit, revert with `git checkout README.md` -->
```
This  line is added. Add a deleted line

In `README.md` at line 9:
```markdown
## Usage
```
This line is kept untouched
````

````
In `README.md` at line 5 (before changes):
```markdown
My personal NixOS and macOS configurations, managed with Nix Flakes.
```
This line is deleted
````

A comment on the agent's reply ("Pong"), with a typed message:

```
<!-- reply 1 -->
> Pong

check this


this is a prompt with comment
```

Facts:

- Diff template matches the bundle: `at line N` for one line, `at lines
  S-E` for a range (no range sample; the bundle's parser regex accepts
  both), ` (before changes)` only on the deleted side, the body right after
  the closing fence, one blank line between comments.
- The fence info string is the language (`markdown` for `.md`; the bundle
  falls back to `text`).
- The typed message goes last, after two blank lines (seen in the reply
  turn).
- `withReplies` is Claude's **reply-comment** serializer (`ve`/`be` in
  a chunk of the cached bundle): each
  quoted transcript selection with a comment becomes a marker line, the
  selection with every line `> `-quoted, a blank line and the trimmed
  comment (three or more newlines squeezed to two). The first marker is
  `<!-- reply K -->` where K is the number of such blocks (at most 99); later
  ones are `<!-- reply -->`. Blocks are joined by one blank line, and the
  whole set comes before the diff comments and typed message, two blank
  lines apart. No turn or prompt is named. `<!-- reply` lines inside a
  comment are escaped to `&lt;!-- reply`.
- Not seen in a sample: a range, a mixed selection, two files in one send,
  and whether the reply quote is the selection or the whole message ("Pong"
  was both; the code quotes the selection text).

Decision (Bill): the `claude` style uses the native reply format for notes
on the target session's own transcript, placed before diff and file notes;
it replaces the `claude` sentences in
[How the capture popup behaves](005-capture-popup.md) for those notes.
Quotes from another session keep their current form. The `claude` row of
[What one captured note looks like](004-entry-format.md) is updated.

