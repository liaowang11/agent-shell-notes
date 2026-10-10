# What a Code-tab diff comment looks like to Claude

## Answer
Update 2026-10-11: a real session confirmed the template and showed the reply-comment format; see [Confirm the Claude desktop diff-comment template from a real session](../../wayfinder/tickets/008-confirm-claude-template.md). The rest of this note predates that.

No real transcript sample exists locally. I searched all local desktop Code-tab sessions (mapped to `~/.claude/projects/*/<cliSessionId>.jsonl`) and every other transcript. No user turn has diff-comment structure. Everything below comes from the claude.ai web bundle cached by the desktop app [bundle]. The Code tab is codename "epitaxy". Its JS is served from `assets-proxy.anthropic.com/claude-ai/v2/assets/v1/*.js`. Cache entries are zstd-compressed and were decompressed for reading.

## Template (newest build, cached 2026-10-10 14:53) [bundle]
Serializer: `ch(annotations, userText, frameUntrusted)` in the newest cached bundle.

```
In `<filePath>` at line <N>[ (before changes)][ — review comment from ＠<login>]:
<fence><lang>
<snippet>
<fence>
<comment body>
```

- Line text: `line N`, or `lines S-E` for a range (ASCII hyphen).
- Side: ` (before changes)` is added only when `side==="deletions"`. When you pick a deleted line, the UI first maps it onto the additions side if it can (`Xo`/`Yo`). So most comments show new-file line numbers and no side marker.
- Author suffix: only for comments that have `author` (GitHub PR comments). Your own comments have no author.
- Snippet: the raw lines of that side's file version, with no `+`/`-` markers and trailing whitespace trimmed (`Mr`). It is not a diff hunk. The fence is backticks, one longer than the longest run inside, minimum 3. The info string is `lang` from the diff parser; I did not confirm the exact values, e.g. `typescript` vs `ts` [unverified]. The fence block is left out when the snippet can't be resolved.
- Snippet sanitizing: lines that start like `In … at line(s) N`, `Reply…:` or `<!-- attach` get a `> ` prefix. An `@` that looks like a mention becomes fullwidth `＠`.
- Path sanitizing: newlines become spaces, backticks become `'`, and mention-like `@` becomes `＠`.
- Body: verbatim for your own comments. PR comments get extra handling: an untrusted-author frame, truncation, and `Reply from ＠x:` lines.

## Ordering and joining [bundle]
- Comments are grouped by `filePath`, in the order each file first appears, then sorted by `startLine` within a file.
- Each comment block's lines are joined with `\n`. Blocks are joined with `\n\n` (one blank line).
- Your typed message goes last, after `\n\n\n` (two blank lines), and is trimmed. If it's empty, only the comments are sent. If there are no comments, only your text is sent.
- There is no preamble or heading.

The full outgoing text is `filePrefix + prContext + withReplies(ch(...))` (`k7`). `filePrefix` covers attached files and `prContext` covers a linked PR. I did not trace what `withReplies` does [unverified]. Comments are staged and ride along with the next message you send.

## Example (reconstructed from code)
````
In `src/auth.ts` at line 47:
```typescript
  } catch (e) {
```
don't catch the error here

In `src/auth.ts` at lines 60-61 (before changes):
```typescript
  log(e);
  return null;
```
keep this logging


also add a test
````

## History [bundle]
- In builds from 2026-09-05 and earlier, the template had no `(before changes)`, the author was written with an ASCII `@`, and there was no sanitizing. Joining was the same.
- Builds from 2026-05/06 used a different format: `### path:lines`, then the fenced snippet, `Review comment:`, and the fenced text.

## Related format, not the diff path [bundle]
A shared bundle chunk contains a second serializer. It produces XML: `<claudeai_review_comments>`, `<review_group container="…">`, and `<review_comment path=… lines=…>` with `<snippet>`/`<request>`/`<thread>`, plus preambles about collaborators and selected text. Its anchors are document-oriented (text-quote, rendered-HTML element, plaintext line range). Its store uses the localStorage prefix `diff-comments-`, which is confusing. Which UI surfaces use this format and not `ch` is [unverified]. The epitaxy send path calls `ch`.

## Web (claude.ai/code)
It is the same bundle, so it most likely uses the same template [unverified: no web session was inspected]. The docs only say "at `src/auth.ts:47`" [docs], which does not match the bundle wording.
