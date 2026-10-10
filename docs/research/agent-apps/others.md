# Aider, Gemini CLI, Amp, Cline, Roo Code: annotation input

Researched 2026-10-10 (subagent report, saved by the parent session). Tags:
[src], [docs], [bin] strings from a compiled binary, [unv].

Summary: none has a user-to-agent diff-comment input with ids, replies or
resolve state. Each turns one location into plain text in the prompt. Amp's
desktop diff view has "request changes on specific sections", but its
serialization is closed and unverified.

## Aider (--watch-files), 5dc9490 2026-05-22
- Comments live in the files. Regex `(?:#|//|--|;+) *(ai\b.*|ai\b.*|.*\bai[?!]?) *$`
  (line comments only; `;` covers elisp). `watch.py:69-71` [src]
- Plain `AI` comments accumulate; `ai!` (edit) or `ai?` (ask) triggers. On
  trigger every AI comment in every chat file is included. `watch.py:181-253`
- Prompt (`aider/watch_prompts.py:1-12`) [src]:
```
I've written your instructions in comments in the code and marked them with "ai"
You can see the "AI" comments shown below (marked with █).
Find them in the code files I've shared with you, and follow their instructions.

After completing those instructions, also be sure to remove all the "AI" comments from the code too.
```
  Ask variant starts `/ask` and says the comments contain questions.
- Then per file `\n{rel_fname}:\n` + grep_ast TreeContext with marked lines of
  interest (`█`), pad 3, `⋮...` gaps; fallback `  Line {ln}: {comment}`.
- Lifecycle: resolved = comment deleted by the model (edit mode). No ids.
- Docs ("Behind the scenes", watch.md) quote an older prompt; source wins.

## Gemini CLI, 9b6e026 2026-10-09
- No annotation feature. IDE companion pushes active file, cursor (1-based),
  selectedText (no range), ≤10 files, ≤16 KiB selection. `core/src/ide/types.ts:12-44`
- Added as a separate user history entry each turn (full, then deltas):
  "Here is the user's editor context as a JSON object. This is for your
  information only." + fenced JSON. `client.ts:500-505, 610-615`
- `@file`: `--- Content from referenced files ---` … `Content from @path:` …
  `--- End of content ---`. ACP: resource_link → `@uri`; embedded resource →
  `--- Content from referenced context ---` / `Content from @uri:`.
- Diff accept/reject via companion MCP tools returns edited content, no comments.
- Companion spec: MCP over HTTP + port file + token, `ide/contextUpdate`.

## Amp (closed source; amp.nvim 01ede44)
- VS Code review panel (2025-10), review agent whose findings "can then be fed
  back into the main Amp agent" (2025-12), `amp review` CLI + `.agents/checks/`
  (2026-02), thread diffs with "request changes on specific sections"
  (2026-06). Serialization unverified. [docs]
- Amp's own open questions: "How do reviews map to threads? It's not 1-1";
  "When you accept or reject review comments, should Amp learn from that?";
  "Should there exist an editable review interface in the TUI?"
- IDE protocol (amp.nvim) [src]: `selectionDidChange` with 0-based ranges +
  content, `userSentMessage` (send now), `appendToPrompt` (stage). README
  reference syntax `@relpath#La-b`. Plugin marked unmaintained;
  `appendToPrompt` absent from current CLI binary [bin].

## Cline, bf71bf7 2026-10-09
- "Add to Cline" fills the input (accumulates); Fix/Explain/Improve send now.
- Add to Cline (`addToCline.ts:20-31`): `${fileMention}` + fenced selection
  (no line numbers) + optional `\nProblems:\n…`.
- Fix: "Fix the following code in ${fileMention}" + fence + "Problems:" list
  (`- [source Error] Line N: msg`).
- `@/path` expands at send time to the whole file:
  `<file_content path="…">…</file_content>`, so the model gets snippet + full file.
- `VscodeCommentReviewController` posted agent→user comment threads
  (`{filePath,startLine,endLine}`, `canReply=false`) for "Explain Changes"
  (added 3.39, removed 4.0). No user→agent diff comments.

## Roo Code, b867ec9 2026-05-15 (dormant ~5 months)
- `src/shared/support-prompt.ts`. ADD_TO_CONTEXT: `${filePath}:${startLine}-${endLine}`
  + fenced selection (1-based; ±1 line around cursor without a selection).
- FIX: "Fix any issues in the following code from file path ${filePath}:${startLine}-${endLine}"
  + diagnostics (no line numbers) + user input + fence + a 4-step checklist.
- Path bare (no @), so no file expansion. Templates overridable via
  `customSupportPrompts`.

## Design takeaways
- Clearest anchors: Roo `path:start-end` + fenced quote; Amp/Zed `@path#La-b`;
  Aider's context excerpt with marked lines.
- Cline's attach-the-whole-file is a cost trade-off to decide deliberately.
- Stage-then-send (Cline/Roo input box, Amp appendToPrompt, Aider `AI` + `AI!`)
  vs send-now are both established.
- None has ids, replies, resolve/stale state, a diff side marker, or anchor
  relocation.
