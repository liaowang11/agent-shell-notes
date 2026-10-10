# Annotation support in OpenAI Codex, codex-acp, OpenCode, oh-my-opencode

Research date: 2026-10-10. Read-only. Evidence labels:

- **[src]**: verified in open-source code (path given)
- **[bundle]**: verified in the shipped minified JS of the Codex VS Code extension (closed source; this webview appears to be shared with the desktop app, see the `electronBridge` / `electron-*` messages)
- **[docs]**: verified in official docs or changelog
- **[unverified]**: inferred, or not found

## Sources used

| Source | Revision |
|---|---|
| github.com/openai/codex | 806d973, 2026-10-10 |
| github.com/zed-industries/codex-acp | 296069e, 2026-07-22; pins codex crates at `rust-v0.137.0` |
| github.com/sst/opencode, which now redirects to **anomalyco/opencode** | 055d95b, 2026-10-09 |
| github.com/code-yeongyu/oh-my-opencode | 78d4592, 2026-10-10 |
| VS Code Marketplace `openai.chatgpt` VSIX, v26.51007.21434 | bundle dated 2026-10-08 |
| learn.chatgpt.com docs (developers.openai.com/codex/* now redirect there) | fetched 2026-10-10 |

The stale refs under ~/Repositories/refs were not touched.

---

## TL;DR

1. **The Codex desktop app and IDE extension have the richest human-to-agent annotation model of the tools covered here, but it is client-side only.** The webview keeps diff comments, response-text annotations, selected text, and browser, PDF, image, and artifact comments as composer attachments. On send it flattens them into **one plain-text user message** made of markdown sections (`# Diff comments:` / `## User Comment N` / `File:` / `Side:` / `Lines:` / `Diff hunk:` / `Comment:` ... `## My request:`). The app-server protocol has no comment type. Any client can reproduce the format by sending text through `turn/start`. [bundle]
2. **Agent-to-human notes in Codex take two forms:**
   - core `/review` returns a structured JSON `ReviewOutputEvent` (findings with `title`, `body`, `confidence_score`, `priority`, `code_location{absolute_file_path, line_range{start,end}}`) [src];
   - the desktop app's own review does **not** use that. It sends a normal turn whose prompt asks the model for inline `::code-comment{title body file start end priority}` directives in markdown. The app parses these into the **same diff-comment objects** the user creates, so a model finding becomes an editable user comment and can round-trip back to the model. [bundle] The TUI also renders `::code-comment` directives. [src]
3. **Response annotations in the Codex app**: the user highlights text in an earlier Codex reply, adds an optional comment, and the app sends a JSON array inside `<response-annotations>`. The model must cite each annotation it addresses with `:codex-annotation{index="N"}`. [bundle]
4. **OpenCode (web and desktop app only; the TUI has none)** offers line comments on diff and file views. Each comment is sent as a synthetic text part, `The user made the following comment regarding lines A through B of PATH: COMMENT`, followed by a `file://PATH?start=A&end=B` file part. The server expands that part into a synthetic Read-tool call and its output. Structured metadata travels in `part.metadata.opencodeComment`. [src]
5. **codex-acp** maps `/review`, `/review-branch` and `/review-commit` to core `Op::Review` and returns findings to ACP **as flattened agent text only**. It drops ranges from ResourceLink and has no annotation channel. [src]
6. **oh-my-opencode** has no human annotation feature. [src, by grep]
7. Nothing in these tools stores content hashes or relocates anchors. Codex stores `{path, side, line, start_line, start_side}` plus an optional copy of the diff hunk. OpenCode stores `{file, start, end, side, endSide}` plus an optional preview.

---

## 1. OpenAI Codex: core `/review` (CLI/TUI, `codex exec review`, app-server `review/start`)

### 1.1 Entry surface
- TUI slash command `/review` opens a popup with these targets: uncommitted changes, base branch picker, commit picker, or custom instructions. [src] `codex-rs/tui/src/chatwidget/review_popups.rs`, `slash_command.rs`
- `codex exec review` takes `--uncommitted`, `--base`, `--commit`, `--title`, or custom instructions (`-` reads stdin). [src] `codex-rs/exec/src/cli.rs:180,297-326`
- **The TUI has no way for a human to annotate.** It has no diff, line or message comments. Its only review features are `/review` and rendering model-emitted `::code-comment` directives (section 2.6). [src: grep over `codex-rs/tui/src`]
- App-server v2 has `review/start` with `{threadId, target, delivery?: "inline"|"detached"}`. Detached delivery is deprecated. [src] `codex-rs/app-server-protocol/src/protocol/v2/review.rs`, `common.rs:1122`

### 1.2 Request side (prompt sent to the reviewer)
- The review runs in a one-shot sub-agent. Its base instructions are replaced by `REVIEW_PROMPT` = `codex-rs/prompts/templates/review/rubric.md`. Web search, collab and multi-agent are disabled, approval is set to `Never`, and the model is `review_model` if configured. [src] `codex-rs/core/src/tasks/review.rs:97-145`
- The user-turn text comes from `codex-rs/prompts/src/review_request.rs`. [src] Verbatim:
  - Uncommitted: `Review the current code changes (staged, unstaged, and untracked files) and provide prioritized findings.`
  - Base branch: `Review the code changes against the base branch '{{base_branch}}'. The merge base commit for this comparison is {{merge_base_sha}}. Run \`git diff {{merge_base_sha}}\` to inspect the changes relative to {{base_branch}}. Provide prioritized, actionable findings.` (A fallback asks the model to compute the merge base itself.)
  - Commit: `Review the code changes introduced by commit {{sha}} ("{{title}}"). Provide prioritized, actionable findings.`
  - Custom: the trimmed instructions, sent as-is.

### 1.3 Findings schema (agent to human): the reverse direction
Rubric output contract, verbatim from `codex-rs/prompts/templates/review/rubric.md` [src]:

```json
{
  "findings": [
    {
      "title": "<≤ 80 chars, imperative>",
      "body": "<valid Markdown explaining *why* this is a problem; cite files/lines/functions>",
      "confidence_score": <float 0.0-1.0>,
      "priority": <int 0-3, optional>,
      "code_location": {
        "absolute_file_path": "<file path>",
        "line_range": {"start": <int>, "end": <int>}
      }
    }
  ],
  "overall_correctness": "patch is correct" | "patch is incorrect",
  "overall_explanation": "<1-3 sentence explanation justifying the overall_correctness verdict>",
  "overall_confidence_score": <float 0.0-1.0>
}
```

Other rubric rules [src]:
- Prefix each title with `[P0]` to `[P3]`, and also set numeric `priority`.
- Keep ranges as short as possible (avoid more than 5 to 10 lines) and make them overlap the diff.
- Use one comment per distinct issue.
- Use ```` ```suggestion ```` blocks only for concrete replacement code, preserving leading whitespace.
- Output no prose and no fences. The rubric adds: "The comments will be presented in the code review as inline comments."

Rust types, from `codex-rs/protocol/src/protocol.rs:3596-3638` [src]:
`ReviewOutputEvent{findings, overall_correctness: String, overall_explanation: String, overall_confidence_score: f32}`;
`ReviewFinding{title, body, confidence_score: f32, priority: i32, code_location: ReviewCodeLocation}`;
`ReviewCodeLocation{absolute_file_path: PathBuf, line_range: ReviewLineRange{start: u32, end: u32}}` (inclusive range).

The model has no side, hunk or quote fields. Anchors are absolute path plus line range in the post-change file. Possible bug [src]: `priority` is a required `i32` in Rust, but the rubric says the model may "omit the field or use null". Then `serde_json::from_str::<ReviewOutputEvent>` fails, so the parser takes the substring from the first `{` to the last `}` (which also fails) and then falls back to putting the whole text into `overall_explanation` (`tasks/review.rs:193-208`). In that case the structured findings are silently lost. Not tested here.

### 1.4 What goes back into the main thread (serialization)
`exit_review_mode` (`core/src/tasks/review.rs:212-286`) [src] records two items.

(a) A **user**-role message rendered from `prompts/templates/review/exit_success.xml`:

```
<user_action>
  <context>User initiated a review task. Here's the full review output from reviewer model. User may select one or more comments to resolve.</context>
  <action>review</action>
  <results>
  {{results}}
  </results>
  </user_action>
```

`{{results}}` = `overall_explanation` + `\n` + `format_review_findings_block(findings, None)` (`codex-rs/protocol/src/review_format.rs`):

```

Full review comments:            (or "Review comment:" when there is 1 finding)

- [P1] Title — /abs/path/file.rs:10-12
  body line 1
  body line 2
```

The formatter also supports `- [x] Title — path:start-end` / `- [ ]` checkbox markers for a selection. Every caller passes `None`, so this selection UI is **not wired up in OSS** [src: only two call sites, both `None`]. Interrupted reviews use `exit_interrupted.xml` (`<results>None.</results>`). The `core/templates/review/history_message_*.md` files are near-duplicates that nothing references (dead code).

(b) An **assistant**-role message holding `render_review_output_text` (explanation + findings block), plus a `TurnItem::ExitedReviewMode{id, review_output}`.

### 1.5 Lifecycle, persistence, exposure
- Lifecycle: no resolve or reply threads and no stale-finding detection in core. "User may select one or more comments to resolve" is only prompt text. [src]
- Persistence: in the paginated history mode, the rollout JSONL (`~/.codex/sessions/...`) keeps `ItemCompleted` with the `ExitedReviewMode` turn item, including structured `review_output`. Legacy mode persists the `ExitedReviewMode` event. [src] `codex-rs/rollout/src/policy.rs:135-155`
- CLI JSON: `codex exec review --json` runs through app-server `review/start`. The JSONL processor maps only AgentMessage, Reasoning, CommandExecution, FileChange, McpToolCall, CollabAgentToolCall and WebSearch items; `ExitedReviewMode` falls into `_ => None` (`codex-rs/exec/src/event_processor_with_jsonl_output.rs:148-323`). A shell-out from Emacs therefore gets only the rendered text in the assistant message, not structured findings. [src]
- SDKs: the Python SDK's generated model is `ExitedReviewModeThreadItem{id, review: str}`, which is text only (`sdk/python/src/openai_codex/generated/v2_all.py:5550`). The TypeScript SDK (`sdk/typescript/src`) has no review types at all. [src]
- Exposure: app-server v2 **flattens** this. `ThreadItem::ExitedReviewMode{id, review: String}` carries only rendered text (`app-server-protocol/src/protocol/v2/item.rs:424,1024`). Structured findings are not on the v2 wire. [src] codex-acp also flattens to text (see section 4).

### 1.6 Generic client-context hook (relevant for an Emacs client)
`turn/start` and `turn/steer` accept the experimental `additionalContext: {[key]: {value, kind: "untrusted"|"application"}}` (`v2/turn.rs:211,327`). Core turns each new or changed entry into [src] `codex-rs/context-fragments/src/additional_context.rs`:
- untrusted: a **user** fragment `<external_{key}>{value}</external_{key}>`
- application: a **developer** fragment `<{key}>{value}</{key}>`

The value is middle-truncated to 1000 tokens, and an entry is re-sent only when its value changes (`core/src/state/additional_context.rs`). The 1000-token cap makes it a poor fit for a large batch of notes. Plain `UserInput::Text` has no such cap.

`UserInput::Text` also carries `text_elements: [{byte_range, placeholder}]`. These are UI spans persisted across resume without changing the text, so a client could use them to mark annotation spans. [src] `codex-rs/protocol/src/user_input.rs`

---

## 2. Codex desktop app / IDE extension (closed source; bundle evidence)

### 2.1 Entry surface [docs]
From learn.chatgpt.com/docs/code-review?surface=app:
- "Open the review pane. Hover over the line you want to comment on. Select the **+** button that appears. Write your feedback and submit it." Then "After you finish leaving feedback, send a message back to the chat."
- "Codex treats inline comments as review guidance."
- "Review findings appear as inline comments in the review pane."
- `/review` in the composer; per-hunk stage, unstage and revert.

Changelog [docs]:
- 2026-07-09 (26.707): "use inline annotations… Send inline review feedback"
- 2026-07-30 (26.727): comments across images
- 2026-08-26 (iOS): "optional comments to selected response annotations"
- 2026-09-11 (26.908): "Keep unfinished comments on response text when you switch chats and return"
- 2026-09-23 (iOS): "Side chats now carry over attachments, selected text, and review comments"
- 2026-04-16 (26.415): in-app browser page comments

### 2.2 Annotatable sources [bundle]
`nba()` sorts composer `commentAttachments` into `diffCommentAttachments`, `annotationCommentAttachments` (browser, PDF, artifact) and `designTweakCommentAttachments`. Separate fields cover `responseTextAnnotations` (text selected in an earlier Codex response, plus an optional comment), `selectedTextAttachments` (file selections with a range), image comments, and PR checks. So the app covers diff lines, files, prior agent responses, images, browser pages, PDFs, and artifacts. Plans and tool output have no dedicated type [unverified].

### 2.3 Anchor model [bundle]
A diff comment is a GitHub-style object:
`{content:[{content_type:"text", text}], position:{path, side:"left"|"right", line, start_line?, start_side?}, localDiffHunk?, localWorkspaceRoot?, localPullRequestUrl?, localPullRequestDiscussionUrl?, localPullRequestCommentGuidance?, ...}`.
`line` is the end of the range and `start_line` the start. Sides are encoded as `L`/`R`.

No content hash or relocation logic was found. The only drift aid is the optional copied `localDiffHunk`, which is sent with the comment. [unverified that nothing relocates]

### 2.4 Batching
Comments collect as composer attachment chips; there are "remove all" and edit handlers per kind. They go out with the next user message. Unfinished response comments survive a chat switch. [bundle + docs]

### 2.5 Exact serialization [bundle: `EE()`, `n9t()`, `wE()` in `webview/assets/app-initial-fee819fe4f22.js`]
All attachments become markdown sections prepended to one text user message. In code order the sections are:
worktree → response annotations → page or LaTeX context → `# Context from my IDE setup:` → `# Files mentioned by the user:` → `# Files pasted by the user:` → apps → prior conversation → PR repair instructions → **`# Diff comments:`** → `# Browser comments:` → `# Selected text:` → `# Failing PR checks:` → merge conflict → in-app browser state → then `wE()` appends `\n## My request:\n{prompt}\n`.

Diff comment block, reconstructed from `n9t` (exact literals, `\n` separators):

````
# Diff comments:

## User Comment 1
File: src/app.ts
Workspace: /repo                       (only if localWorkspaceRoot)
Pull request: https://…               (only for PR comments)
Side: R                               (or L, or "L-R" when start/end sides differ)
Lines: 10-12                          (or "12"; or "L5-R7" across sides)
Diff hunk:
```diff
@@ -8,6 +8,9 @@ …
```
Comment:
Rename this; it shadows the import.
Additional user guidance:             (optional)
…

## My request:
Address the comments, keep the scope minimal.
````

If the comment comes from a PR discussion rather than a line, the `File:`/`Side:`/`Lines:` lines are replaced by `Pull request discussion: <url>`. Browser, PDF and artifact comments use the same `## User Comment N` header (or `## Requested annotation N` for design tweaks). They add `Page URL:`, `Target:`, `Selected text:`, `PDF page: n/m`, `Artifact path:` and similar lines, plus labeled screenshots ("The next image shows … at the time of Comment N … marked by comment marker N.").

Response annotations (`$dt`, `g9t`, `eft`/`tft`), verbatim:

```
# Response annotations:
Each item contains text selected from an earlier Codex response and may include a user comment. Treat items as Annotation 1, Annotation 2, and so on in array order. Use every selection as context and address every comment. For every annotation you address, include its inline directive `:codex-annotation{index="N"}`, where N is its one-based array position (for example, `:codex-annotation{index="1"}`). Do not use unstructured annotation labels.
<response-annotations>
[{"text":"<selected response text>","annotation":"<user comment, optional>","source":{…}}]
</response-annotations>
```

The shape of `source` was not found in the minified code [unverified]. It presumably identifies the response turn or item.

Selected text: `# Selected text:\n\n## Selection 1: path (lines a-b)\n<text>`.

The app also parses these sections back out of sent user messages to render "sent comment" chips (`Qfn`, regex `^## (?:Comment|User Comment|Requested annotation) (\d+)$`). In other words, **the transcript itself stores sent comments**.

### 2.6 App review: agent-to-human notes as directives [bundle: `webview/assets/code-review-30179f433fd8.js`]
The app's quick review does **not** call core `review/start`. It sends an ordinary `turn/start` with `turnTrigger:"code_review"` and one text input:

`["## Code review guidelines:", <guidelines>, <target instructions>, "## My request:", "Please review my uncommitted changes"].join("\n")`

`turnTrigger` is a plain `TurnStartParams.turn_trigger: Option<String>` (`v2/turn.rs:182`). In core it only feeds the `x-codex-turn-metadata` Responses metadata (`core/src/responses_metadata.rs`, `turn_metadata.rs`); no instruction or tool switching keys off it [src]. So a client that sends the same text would get the same model-visible prompt, apart from that metadata header and any server-side handling [unverified].

Verbatim excerpt from the guidelines:

> Review the change and respond in normal Markdown. Do not return JSON, XML, a findings object, or any structured review schema.
> When feedback should be attached directly to a changed line, emit one `::code-comment{...}` directive for that issue. The directive creates an inline code comment in the review UI; keep the visible response as normal Markdown. Emit no directives when there are no actionable inline comments.
> Required `code-comment` attributes: `title`, `body`, and `file`. Optional attributes: `start`, `end`, and `priority`. Use the shortest useful line range. `file` should be an absolute path or include the workspace folder segment.

The target instruction is, for example, `Review the current code changes (staged, unstaged, and untracked files) and provide concise, actionable feedback in a normal Markdown response.`

`fSn`/`dSn` parse each `::code-comment{…}` directive into a diff-comment object:
- `position:{side:"right", path, line:end, start_line?}`
- title prefixed `[Pn]` when `priority` is given
- `start` clamped to ≥1 and `end` to ≥`start`

`mSn` then merges them into the per-conversation `diff_comments` store, deduplicating by key. The `diff_comments_from_model` subscriber does this for `codeComments` arriving from the host. **So model findings and user comments share one store and one serialization.**

The TUI parses the same directive, `::code-comment{title="…" body="…" file="…" start=10 end=12 priority=2}`, with backslash-escaped quotes. It renders it as `- [P2] title — rel/path:10-12\n  body` [src] `codex-rs/tui/src/git_action_directives.rs:92-140`, `assistant_directives.rs`. No OSS prompt asks for these directives; the instruction lives in the app bundle.

### 2.7 Lifecycle, persistence, exposure
- Lifecycle: user comments can be edited and removed. Model comments become regular comments. Artifact comments have thread and reply IDs ("post one reply per supplied Artifact comment reply ID"), but diff comments have no reply threads or resolve state [bundle; unverified that none exists]. No stale detection was found.
- Persistence: `diff_comments` is a "shared object" keyed by conversationId. It lives in the host's `sharedObjectRepository` (extension host or Electron main) and moves to the new id when a draft becomes a thread. Whether it is written to disk is [unverified]. Once sent, comments persist as text inside the user message in the Codex rollout.
- Exposure: **none as a protocol feature**. The app-server sees plain text. An Emacs ACP or app-server client can reproduce the format exactly, and the model was presumably tuned for this layout.

## 3. Codex cloud / GitHub PR review [docs]
- Trigger: comment `@codex review` (Codex reacts with 👀) or enable "Automatic review". `@codex security review` also exists.
- Codex "posts a review on the pull request, just like a teammate would" and "flags only P0 and P1 issues". The example shows `[P1]` tied to lines.
- Rules come from the `## Code Review Rules` section of the nearest `AGENTS.md`.
- `@codex fix the P1 issue` starts a cloud task with the PR as context and can push a fix. The docs say nothing about thread replies or resolution.
- The open-source `.github/codex/labels/codex-review.md` is a simple label-triggered prompt for the openai/codex-action workflow and has no structured findings. [src]
- I did not investigate whether the Codex cloud web UI (chatgpt.com/codex task diff view) has its own diff commenting [unverified / not covered]. This section covers only the GitHub bot.
- The model output schema for the GitHub bot is presumably the rubric JSON from section 1.3, mapped to GitHub review comments [unverified].

## 4. codex-acp (zed-industries) [src: `src/thread.rs`]
- Entry: ACP available commands `review`, `review-branch` and `review-commit` (lines 2905-2920) map to `Op::Review{ReviewRequest{target, user_facing_hint}}` (lines 3197-3236).
- Output: `review_mode_exit` (lines 1570-1599) sends **one agent text chunk**. That is `format_review_findings_block(findings, None)` when findings exist, which drops `overall_explanation`, correctness and confidence. Otherwise it sends the explanation or "Reviewer failed to output a response". It sends no `_meta` and no structured findings.
- Input mapping (`build_prompt_items`, lines 3696-3730):
  - Text → `UserInput::Text`
  - Image → data URL
  - ResourceLink → `[@name](uri)` text, which **drops any range**
  - Embedded text Resource → ``[@name](uri)\n<context ref="uri">\n{text}\n</context>``
  - Other blocks are skipped. `additional_context` is always the default (empty).
- Annotation support: none beyond what a client puts into text or embedded resources. It embeds codex-core directly; it does not speak app-server.

## 5. OpenCode (anomalyco/opencode, formerly sst/opencode)

### 5.1 Entry surface [src]
Web and desktop app (`packages/app`): line comments in the session review tab (diff, `origin:"review"`) and in file tabs (`origin:"file"`). See `pages/session.tsx:981-1004,1279,1322`, `pages/session/file-tabs.tsx`, UI `packages/ui/src/v2/components/line-comment-v2.tsx`, and e2e `packages/app/e2e/regression/review-line-comment.spec.ts`. **The TUI has no comment feature** (grep finds nothing in `packages/tui`). Assistant messages cannot be annotated [unverified; nothing found].

### 5.2 Anchor model [src] `packages/app/src/context/comments.tsx`, `context/file/types.ts`
`LineComment{id, file, selection:{start, end, side?:"additions"|"deletions", endSide?}, comment, time}`. The prompt context item adds `selection:{startLine, startChar, endLine, endChar}`, `commentID`, `commentOrigin`, and `preview` (copied selected lines). There is no hash and no relocation.

`formatCommentNote` ignores `side`, so a comment on a deleted line sends an old-file line number. The server then reads that range from the current file, which is a likely mis-anchor [inferred, not tested].

### 5.3 Batching
Each comment becomes a context chip in the prompt input; many can pile up. On submit, all comment items go out with the message and are removed from the prompt context; they are restored if the send fails. [src] `components/prompt-input/submit.ts:547-575`

### 5.4 Exact serialization [src] `packages/app/src/utils/comment-note.ts`, `components/prompt-input/build-request-parts.ts`
For each comment, the client sends these parts after the user's text part:
1. A text part with `synthetic: true` and the text
   `The user made the following comment regarding lines 4 through 8 of src/a.ts: Keep this stable`
   (or `line 4`, or `this file`), with `metadata.opencodeComment = {path, selection, comment, preview, origin}`.
2. A file part with `mime:"text/plain"` and `url: file:///abs/src/a.ts?start=4&end=8`.
3. A file part for each `@path` mentioned inside the comment.

Server side, in `packages/opencode/src/session/prompt.ts:830-900`, the file part becomes:
- a synthetic text `Called the Read tool with the following input: {"filePath":"/abs/src/a.ts","offset":4,"limit":5}`
- the Read tool's output as synthetic text, plus the file part

If start equals end, the range expands to the LSP symbol starting at that line.

### 5.5 `/review` [src] `packages/opencode/src/command/template/review.txt`, `command/index.ts`
A built-in command template run as a subtask. It asks for free-form markdown output only: no findings schema, no priorities, no file or line structure.

### 5.6 Lifecycle, persistence, exposure
- Lifecycle: add, update and remove only; no resolve, threads or agent replies. Sent comments show again in the timeline via `readCommentMetadata`, with `parseCommentNote` as a regex fallback on the text. [src]
- Persistence: comments are kept per server scope, directory and session through `persisted(Persist.serverScoped(…,"comments"))`, in localStorage (web) or the desktop app's store. At most 20 comment sessions are cached. [src] `context/comments.tsx`, `utils/persist.ts`
- Exposure: not a server feature. Any SDK, HTTP or ACP client can send the same parts. OpenCode's own ACP agent (`packages/opencode/src/acp/content.ts`) maps:
  - `resource_link` to a file part
  - embedded text `resource` with `file://…#L12` to `[path:12]\n{text}`

  A `?start=&end=` query on a resource_link URI would reach the same Read expansion [inferred from code paths, not tested].

## 6. oh-my-opencode (code-yeongyu) [src, by grep]
No human annotation or review-comment feature. `packages/comment-checker-core` is a hook that polices code comments the agent writes, not user notes. The ulw-loop "annotate_ledger" steering kind annotates the agent's own goal ledger. Nothing here is relevant to sending notes to an agent.

---

## Design takeaways for an Emacs annotation package
- **Proven wire format**: markdown sections prepended to a single user message, with a stable header per note (`## User Comment N`), key/value lines (`File:`, `Side:`, `Lines:`), an optional fenced `Diff hunk:`, then `Comment:`, and finally a `## My request:` divider. The vendor tunes this format and parses it back for display. Copying it needs no protocol support over ACP.
- **Anchors** in both apps are path + side + line range. Only Codex sends the hunk text as drift context. Neither hashes content or relocates anchors. An Emacs package that stores a quote or hunk and re-finds it would be ahead of both.
- **Reverse direction**: use either the core rubric JSON (`code_location.absolute_file_path` + `line_range` + `priority` + `confidence_score`) or the app's `::code-comment{title body file start end priority}` directive. The directive survives any text transport (ACP), so a client can parse it from agent text. Codex's design of turning model findings into user-editable comments in the same store is worth copying.
- **Response annotations**: a JSON array plus required back-references `:codex-annotation{index="N"}` give a cheap "did the agent address every note" check.
