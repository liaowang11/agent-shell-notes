# How IDE-hosted agents handle annotations (researched 2026-10-10)

Scope: VS Code (Agents window and classic Copilot Chat), Zed, Cursor, Windsurf (Devin Desktop), Google Antigravity, JetBrains (Junie, AI Assistant, Air) and Kiro.

## Evidence labels

- **[src]**: verified in source at the commit below.
- **[docs]**: verified in official docs, a changelog or a vendor blog.
- **[forum-staff]**: a staff reply on the vendor forum.
- **[prompt]**: an extracted system prompt. The source and how reputable it is are given each time.
- **[proto]**: a client protobuf reverse-engineered from Cursor. Two independent extractions agree.
- **[observed]**: a real GitHub API payload.
- **[3p]**: a third-party article.
- **[unverified]**: inference, or no source found.

## Sources checked

- **vscode:** `microsoft/vscode` @ `959031245ebb` (2026-10-10). The task's pointer to `microsoft/vscode-copilot-chat` is stale. That repo is archived (last commit "Add archive notice", 2026-05-20). Copilot Chat now lives at `vscode/extensions/copilot`.
- **zed:** `zed-industries/zed` @ `f16f9652ec57` (2026-10-09).
- Both are blobless sparse clones.
- Cursor and the other closed apps were researched on the web by two sub-agents.

Paths below are relative to the repo root. `AF` = `src/vs/sessions/contrib/agentFeedback/browser`. `AH` = `src/vs/platform/agentHost`.

---

## 1. VS Code + GitHub Copilot

VS Code now has two separate surfaces. They should not be blended.

- **(A) The Agents window** ("sessions", `src/vs/sessions/…`). Sessions run in an *agent host* process that speaks Microsoft's own **Agent Host Protocol (AHP)**, `github.com/microsoft/agent-host-protocol`. Types are synced into `AH/common/state/protocol/` by `scripts/sync-agent-host-protocol.ts`. AHP is not ACP. Copilot CLI, Claude and Codex agents run behind it [src].
- **(B) The classic Chat view plus the Copilot extension** (`src/vs/workbench/contrib/chat`, `extensions/copilot`).

### 1A. Agents window "Add Feedback" (the most complete annotation system in this survey)

**1. Entry surface**
- In a changed file (in the Changes diff view), select a range and choose **Add Feedback**, then type a comment.
- Markdown files work in **Locked** mode [docs] https://code.visualstudio.com/docs/agents/run/review-code-edits
- **Submit Feedback** is bound to `Cmd/Ctrl+Enter` when the editor has focus and unsubmitted feedback exists (`AF/agentFeedbackEditorActions.ts:81-90`) [src].
- There is a "Submit Feedback (N)" title action (`agentFeedback.contribution.ts:71`), Next/Previous feedback navigation, and Clear [src].

**2. What can be annotated**
- Diff ranges on either side, ranges in a file, and Markdown/plan files.
- PR review comments and in-product code-review comments can be converted into feedback.
- Terminal output and images cannot be annotated in this subsystem [src: `AgentFeedbackKind` = `user | codeReview | prReview`, `AF/agentFeedbackModel.ts`].
- Agent *responses* get a separate feature: see "Response selection" below.

**3. Anchor model**
- `IAgentFeedback` fields [src]:
  - `id`, `text`, `resourceUri`
  - `range` (one-based start/end line and column)
  - `sessionResource`, `kind`, `state`
  - optional: `codeSelection` (the quoted text), `diffHunks` (unified-diff text of the hunks the selection covers, rendered with 3 lines of context), `suggestion` (`{edits:[{range, oldText, newText}]}`), `sourcePRReviewCommentId`, `sourcePullRequest {owner, repo, number}`, `replies[] {text, author}`
- Both the quote and the hunks are captured at creation time from the live models (`AF/agentFeedbackEditorUtils.ts:createAgentFeedbackContext`) [src].
- On the AHP wire, the item becomes an `Annotation` [src, `AH/common/state/protocol/channels-annotations/state.ts`]:
  - fields: `{id, origin {session, chat?, turnId?}, resource, range? (0-based TextRange; omitted = whole file), resolved, entries[] {id, text, _meta}, _meta}`
  - Feedback semantics live under `_meta["vscode.agentFeedback"]`.
  - Each entry's author (`user | agent | prReviewer | unknown`) is stored in `entry._meta` (`AH/common/meta/vscode/agentFeedbackAnnotations.ts`).
- **No content hash.** `origin.turnId` records which turn produced the file version.
- **Relocation:** I found no tracked-decoration or re-anchor logic in the agentFeedback widgets. The only decoration is a range highlight (`agentFeedbackEditorWidget.ts:135`).
  - The protocol allows re-anchoring through `AnnotationsUpdatedAction {resource?, range?}`. Its doc says it is for "re-anchor / resolve" [src].
  - The docs say Markdown feedback "stays in sync if you reopen the file" [docs].
  - Verdict: re-anchoring exists at protocol level, but I found no automatic drift repair at this commit [unverified beyond grep].

**4. Batching and submit boundary**
- Each item moves through **Created → Accepted → Submitted → Resolved** (`AgentFeedbackState`) [src].
  - *Created* is for items an agent or system added, e.g. through the `addComment` tool. They are hidden from the agent's `listComments` and are not attached until the user **accepts** them.
  - Only *Accepted* items are submitted.
- **Non-agent-host providers:** accepted items show up as one live-updating chat-input attachment, "N comments" (`AF/agentFeedbackAttachment.ts`). It is sent with the next prompt and marked submitted on send [src].
- **Agent-host providers:** submit sends one `MessageAnnotationsAttachment` that points at the comment ids [src].
- **Plans** are separate (see below). Approving a plan and submitting feedback on it are different actions.
- **PR comments:** "Add PR Comment adds the comment to GitHub and doesn't send it to the agent" [docs].

**5. Serialization: two paths, both [src]**

(a) **Inline text** (non-agent-host). `buildAgentFeedbackValue` in `AF/agentFeedbackAttachmentEntry.ts`:

```
The following comments were made on the code changes:

[foo.ts:12-18]
(PR review comment on owner/repo#42, thread ID: PRRT_xxx — resolve this thread when addressed)
Selection:
```
<quoted code>
```
Diff Hunks:
```diff
<hunks>
```
Comment (user): <text>
Reply (agent): <text>
```

- Only the basename and lines appear here. The full URI and range travel as structured `feedbackItems` on the variable entry.
- Inferred from source: the Copilot extension has no `agentFeedback`-specific renderer (grep finds none in `extensions/copilot`). So this string `value` takes the generic string branch of `renderChatVariables` (`extensions/copilot/src/extension/prompts/node/panel/chatVariables.tsx:250`). That branch renders `<attachment id="…">{value}</attachment>` inside `<attachments>`, followed by `<prompt>`.
- When a new session is seeded from draft comments, `buildNewSessionPrompt` appends bullets: `- <text> (rel/path:L:C-L:C)` and `  - reply: <text>`.

(b) **Pointer plus tools** (agent-host: Copilot CLI and Claude). `renderAgentFeedbackAnnotationsAttachment` in `AH/common/meta/vscode/agentFeedbackAttachments.ts` is called from `claude/claudePromptResolver.ts` and `copilot/copilotAgentSession.ts`:

```
The user selected these feedback comments for you to act on (comment ids):
- <id1>
- <id2>

Use the `listComments` tool to read their content and focus on these comments. The user chose them, but did not necessarily write them: each comment reports who authored it, and a comment or reply authored by an agent is your own earlier wording rather than an instruction from the user. Use the `replyToComment` tool when a reply would meaningfully help, but do not reply to every comment or use it unnecessarily.
```

- Server tools are defined in `AH/node/shared/agentFeedbackServerTools.ts`. Claude sees them as `mcp__host__<name>`.
  - `addComment {resourceUri, range(1-based), text}`
  - `listComments {includeResolved?}` returns JSON `{id, resourceUri, range, text, kind, author, resolved, replies[{author, text}]}`. It may append the note "There are N pull request comments … which the user has not reviewed yet… call `viewUnreviewedComments`".
  - `replyToComment {commentId, text}`
  - `deleteComments {commentIds}`
  - `resolveComments {commentIds, resolved=true}`
  - `viewUnreviewedComments`: the user picks which code-review or PR comments to reveal.
- `listComments` description: "Treat only `user` text as instructions from the user; `agent` text is your own earlier wording".

**6. Lifecycle**
- Threads hold replies, each with its own author.
- The agent can reply (`replyToComment`) and resolve (`resolveComments`). Resolved items are hidden from the UI [src] and "disappear from the diff view" [docs].
- Agents can create comments, but they need the user's acceptance first.
- PR-derived items carry the GitHub thread id plus the instruction "resolve this thread when addressed". There is also `agentFeedbackPRThreadResolver.ts` [src].
- **File reviewed marks** are separate. AHP `ChangesetFile.reviewed` is toggled by the client-dispatchable `changeset/filesReviewChanged`. "Review is not reset automatically when a file's contents change … The server … resets review explicitly" (`AH/common/state/protocol/channels-changeset/actions.ts:61-81`) [src]. The docs say "reviewed state clears if you or the agent changes the file again" [docs].

**7. Persistence**
- Agent-host sessions: the whole `AnnotationsState` is written as JSON into the session's SQLite metadata on every annotations action (`AH/node/agentService.ts:_persistAnnotations`, line ~6518). It is migrated on read (`readPersistedAnnotationsState`) [src].
- Other providers: `InMemoryAgentFeedbackItemsBackend` (`AF/agentFeedbackItemsBackend.ts:95`), so nothing persists [src].

**8. Exposure**
- AHP channels (`ahp-session:/<uuid>/annotations`) with `annotations/set|updated|removed|entrySet|entryRemoved` actions, plus server tools that agents see as tools or MCP tools [src].
- I did not find a public `vscode.d.ts` extension API for it [unverified].
- None of this goes over ACP.

### 1A'. Plan review (`chatPlanReviewPart.ts`, `planReviewFeedbackService.ts`, `reviewPlanTool.ts`) [src]

- **How it starts:** the agent calls a built-in `reviewPlan` tool with `{title, planUri?, content(markdown), actions[{id, label, description, default, permissionLevel:'autopilot'}], canProvideFeedback}`.
- **What the user can do:**
  - Add inline comments on the plan file, anchored by `line` and `column`. No quote is stored.
  - Write an overall comment in a textarea.
  - Pick an approval action, or reject.
- **Before submit:** the plan file is saved first, so the user's direct edits to the plan count too.
- **What the tool returns:** `JSON.stringify({action, actionId, rejected, feedback, feedbackOverall, feedbackInlineMarkdown})`, where `feedback` is:

```
<overall comment>

Inline comments on `plan.md`:
- **Line 12:** <text>
- **Line 30, Column 5:** <text>
```

- After submit, the inline items are removed.
- Approving and revising are separate: `submitPlanAction(action)` versus `submitAllFeedback()`.

### 1A''. Response selection (annotating agent messages) [src]

- Selecting text in the transcript shows a menu with **Ask in a Side Chat**, **Quote** and **Copy** (`src/vs/sessions/contrib/chat/browser/responseSelectionSideChatController.ts`).
- **Quote** appends a Markdown blockquote (`> line`) to the chat input.
- **Ask in a Side Chat** forks a side chat from the response's `turnId`, carrying `selection {text, responsePartId?}`. The agent host prepends this block (`AH/node/chatContributions/sideChat/sideChatContext.ts`):

```
<side-chat-context>
length=<n>
This is a side conversation. Prefer explanation over action; do not make changes or carry out work unless the user explicitly asks.

Selected text:

<selection>

Source conversation up to the branching point:

User request: … Agent response: …   (capped at 20k chars, middle-truncated)
</side-chat-context>

<user question>
```

- The `length=` header lets the host parse the seed back out reliably.

### 1B. Classic Chat view and Copilot extension

- **Selections:** `Add Selection to Chat` and #-attachments render as `<attachment id="…">Excerpt from foo.ts, lines 10 to 20: ```lang …```</attachment>` inside `<attachments>`, then `<prompt>…</prompt>` (`extensions/copilot/src/extension/prompts/node/panel/fileVariable.tsx:269-272`, `chatVariables.tsx`) [src].
- **Diagnostics** render as `<error path line code severity>` [src].
- **Images** go in as binary image parts [src].
- **Chat-edits keep/undo per hunk:** not examined in depth [unverified].
- **Copilot code review** (`extensions/copilot/src/extension/review/node/githubReviewAgent.ts`) [src]:
  - Sends base and head file contents, or a selection range, to a server-side CAPI review agent.
  - Gets back a stream of `{path, line, body}` comments. The body may contain a ```` ```suggestion ```` block.
  - These become editor review comments with `kind: 'bug'`. In the Agents window they can become `codeReview`-kind feedback that carries a `suggestion` with edits.
  - On GitHub, Copilot PR review uses ordinary PR review threads.

---

## 2. Zed agent panel (no comment model; only "context" and keep/reject)

**1. Entry surface**
- `agent::AddSelectionToThread` (`cmd->`) works in Editor, Terminal and AcpThread contexts.
- There is a `+` menu with a "Selection" item, `@`-mentions, and `agent::PasteRaw` (`cmd-shift-v`).
- Review uses `agent::OpenAgentDiff` (`shift-ctrl-r`), `Keep` (`cmd-y`), `Reject` (`cmd-alt-z`), and `KeepAll` / `RejectAll` (`shift-alt-y` / `shift-alt-z`).
- Sources: `assets/keymaps/default-macos.json`, `docs/src/ai/agent-panel.md` [src/docs].
- Pasting a multi-line selection copied from a buffer turns it into an @-mention automatically [docs].

**2. What can be annotated**
- Buffer selections, terminal selections, files, directories, symbols, threads, diagnostics, a branch diff (`GitDiff{base_ref}`), merge conflicts, fetched URLs, skills, and images (`MentionUri` in `crates/acp_thread/src/mention.rs`) [src].
- `AgentContextSource` is only `Editor | TerminalView | TerminalPanel` (`crates/agent_ui/src/completion_provider.rs:51`). Agent messages cannot be a source.
- No comments on diff hunks; you can only Keep or Reject them [src/docs].

**3. Anchor model**
- `Selection {abs_path?, line_range, column?}` becomes the URI `file:///abs#L<a>:<b>?column=` (or `zed:///agent/untitled-buffer`).
- `TerminalSelection {line_count}` becomes `zed:///agent/terminal-selection?lines=N`. **It has no anchor at all**, just a line count.
- Mentioned content is captured as a snapshot when the message is sent.
- On send, the buffers behind those mentions are marked *read* in the action log (`thread_view.rs:2059`). The edit tool then refuses edits with "The file has changed on disk since you last read it." (`crates/agent/src/tools/edit_session.rs:971`).
- So drift is detected only from the agent's side. Mentions are never relocated [src].

**4. Batching and submit**
- Mentions build up as chips in the message editor and go with the next message. Messages can be queued, steered or edited.
- There is no separate feedback batch [src/docs].

**5. Serialization [src]**

- **External ACP agents:** each mention becomes an ACP `ContentBlock::Resource(EmbeddedResource{TextResourceContents{text, uri}})` if the agent supports embedded context. Otherwise it becomes a `ResourceLink{name, uri}` (`crates/agent_ui/src/message_editor.rs:mention_to_content_block`).
- **Images** become `ContentBlock::Image`.
- **Native Zed agent:** inline text becomes `[@name](uri)`. Context is appended as a separate block (`crates/agent/src/thread.rs:330-585`):

```
<context>
The following items were attached by the user. They are up-to-date and don't need to be re-read.

<selections>
```rs /abs/path/foo.rs:10-20
<code>
```
```console
<terminal lines>
```
</selections>
<diffs>
Branch diff against main:
```diff …```
</diffs>
</context>
```

- Other blocks follow the same pattern: `<files>`, `<symbols>`, `<threads>`, `<fetched_urls>`, `<diagnostics>`, `<merge_conflicts>`, `<skills>`, and the legacy `<rules>`.
- The fence tag is `"<ext> <path>[:L1[-L2]]"` (`codeblock_tag`).

**6. Lifecycle**
- No resolve, replies or reviewed marks.
- Keep and Reject apply per hunk. `UndoLastReject` exists.
- Restore-checkpoint and edit-message exist [src/docs].

**7. Persistence**
- Threads, including user-message mentions stored as `MentionUri` plus content, are kept in the agent's thread database (`crates/agent/src/db.rs`) [src, not read in detail].

**8. Exposure**
- Zed is the reference ACP client. Annotations reach external agents only as resource blocks with a `#L` URI fragment.
- ACP has no review-comment type [src + agentclientprotocol.com/protocol/content, docs].

---

## 3. Cursor (closed; market leader)

**Bottom line:** Cursor has no comments on local agent diffs and no comments on plans. Feedback means "select something, Add to Chat, type a prompt". Line-anchored threads exist only on PRs: GitHub, Bugbot, and Cursor's Origin.

**Client → server wire [proto]**
- Two extractions agree: oh-my-pi `packages/ai/src/providers/cursor/proto/agent.proto` and leookun/cursor-byok `protocols/cursor/agent_v1.proto`.
- The message is `UserMessage{text, message_id, selected_context, mode, rich_text}`.
- `SelectedContext` has: `selected_images`, `files`, `code_selections`, `terminals`, `terminal_selections`, `git_diff`, `git_diff_from_branch_to_main`, `git_commits`, `git_pr_diff_selections`, `selected_pull_requests`, `ui_elements`, `console_logs`, `past_chats`, `invocation_context`.
- Key anchor types:
  - `SelectedCodeSelection{content, path, relative_path, range}`
  - `SelectedTerminalSelection{content, title, path, range}`
  - `SelectedGitPRDiffSelection{pr_url, file_path, start_line, end_line, diff_content}`
  - `SelectedUIElement{element, xpath, text_content, component, component_props_json}`
  - `InvocationContext_GithubPR{title, description, comments: string, ci_failures}`. PR comments arrive as **one flat string**.
- Anchors are snapshots (content + path + range) with no relocation.

**Server → model [prompt]**
- TensorZero captured real traffic through a proxy in June 2025 (high reputability): https://www.tensorzero.com/blog/reverse-engineering-cursors-llm-client/
  - Tags seen: `<additional_data>`, `<current_file>` (`Path:`, `Line:`, `Line Content:`), `<attached_files><file_contents>```path=…, lines=1-46```…`, `<manually_added_selection>```path=nginx/nginx.conf, lines=1-16```…`, and `<user_query>`.
- x1xhlol dumps (medium reputability) show the same shape.
- Agent prompts mention `LINE_NUMBER|LINE_CONTENT` inline numbering and citations of the form ```` ```start:end:path ````.
- No dump shows how terminal selections are rendered [unverified].

**Surfaces**
- **Agent diff / Review panel:** Cmd+Return accepts all, Cmd+Shift+Backspace rejects all.
  - Staff reply, 2026-06-18: select lines in the Review panel diff and click "Add to Chat". Per-hunk comments and batched review are "not available yet" [forum-staff] https://forum.cursor.com/t/allow-commenting-diffs-when-reviewing-changes/163482
- **Agent Review / "Find Issues":** runs after a task, via `/agent-review`, from Source Control, or after each commit. Quick or Deep. Reads `BUGBOT.md` [docs].
  - 3.7+ adds `/review` and `/review-bugbot`. They store the git patch-id so Bugbot skips the same diff on the PR [docs].
  - Finding anchors and resolve behaviour: [unverified].
- **Bugbot:** runs on each PR update, or on `cursor review` / `bugbot run` [docs].
  - Comments are GitHub review comments, so GitHub relocates them. One sample showed `original_line 75` becoming `line 96` [observed].
  - Hidden markers in the body: `<!-- DESCRIPTION START/END -->`, `<!-- BUGBOT_BUG_ID: <uuid> -->`, `<!-- LOCATIONS START\npath#L54-L75\nLOCATIONS END -->`, and the footer "Reviewed by Cursor Bugbot for commit <sha>" [observed].
  - "Fix in Cursor" = `cursor.com/open?link=<base64url>`. It decodes to `{"type":"BUGBOT_FIX_IN_CURSOR","data":{"redisKey":"bugbot:<uuid>","encryptionKey":…,"branch",…}}`. **The comment text is not in the link**; it is a pointer to an encrypted blob stored on Cursor's server [observed].
  - Staff: the line "appears as inline code selections automatically rather than text in the prompt" [forum-staff].
  - Resolve state comes from GitHub. The analytics API has `resolution_status`. The check passes only when no unresolved Bugbot comments remain [docs].
  - Learned rules come from `@cursor remember …` or repo activity. Autofix runs a cloud agent [docs].
- **Origin PRs:** line comments and Request Changes; mobile can "ask an agent to resolve review comments" [docs].
- **Plan Mode:** Shift+Tab or `/plan`. The plan "opens as a virtual file you can read and edit", then you click **Build** [docs].
  - No plan comments; several open feature requests ask for Antigravity-style comments [forum].
  - On the wire, Build sends `ExecutePlanAction{plan, plan_file_uri "cursor-plan://<composerId>/plan.md", plan_file_content}` [proto].
- **Design Mode** (3.0+, Cmd+Shift+D): click an element, Shift+drag a region, or draw on "a frozen frame of the viewport". The agent receives xpath, component, styles and props plus a screenshot [docs]. This is Cursor's richest annotation surface.
- **Images:** paste or drag in. The Cloud Agents API takes `prompt.images` (at most 5) [docs].
- **Hooks:**
  - `beforeSubmitPrompt` receives only `{prompt, attachments:[{type:file|rule, file_path}]}`. Selections, ranges, terminal text and images are **not** exposed.
  - `stop` can return `followup_message`, which is auto-submitted (`loop_limit` 5) [docs] https://cursor.com/docs/hooks.md
- **ACP:** `agent acp` over stdio. Cursor extension methods:
  - `cursor/create_plan` blocks until the client returns `{outcome:"accepted", planUri?} | {outcome:"rejected", reason?} | {outcome:"cancelled"}`. This is the only structured approve/revise channel, and it has no anchored comments.
  - Also `cursor/ask_question`, `cursor/update_todos`, `cursor/task` [docs] https://cursor.com/docs/cli/acp.md
- **CLI review:** Ctrl+R opens it, `i` adds follow-up instructions [docs].
- **Persistence:** plans live in the home directory, or in the workspace via "Save to workspace". The `.cursor/plans/*.plan.md` path comes from forum reports only. Bugbot state lives on GitHub and Cursor's servers.

---

## 4. Windsurf / Cascade (now "Devin Desktop"; docs.windsurf.com redirects to docs.devin.ai/desktop)

**1. Entry surfaces [docs]**
- Cmd/Ctrl+L opens Cascade. Editor or terminal selections are "automatically included".
- In the terminal: highlight part of a stack trace and press Cmd/Ctrl+L, or @-mention the terminal.
- Previews have a "Send element" button. Elements "land in that agent's message box as pending context" as `@` mentions; several can be added.
- You can @-mention conversations and Codemaps.

**2. What can be annotated**
- Selections, terminal, DOM elements, console errors, conversations, Codemaps.
- Hunks only through accept/reject [3p].
- No inline comments.

**3. Anchors:** chip internals are not documented [unverified].
- The Wave 11 prompt says: "Along with each USER request, we will attach additional metadata about their current state, such as what files they have open and where their cursor is." [prompt, x1xhlol `Windsurf/Prompt Wave 11.txt`]

**4. Submit:** chips build up and go with the message. Messages can be queued. The Todo list is changed only through chat. Terminal commands need approval ("will NOT execute until the user approves it") [docs/prompt].

**5. Serialization:** no comment or selection tag appears in the dumps.

**6. Lifecycle:** reverts and checkpoints only [docs].
- Windsurf PR Reviews is a GitHub bot triggered by `/windsurf-review` [docs]. It is now superseded by Devin Review [3p/docs].

**7. Persistence:** server-side Codemaps; PR comments live on GitHub.

**8. Exposure:** MCP client.
- Devin Desktop hosts ACP agents; "all agent operations are delegated to the agent" [docs] https://docs.devin.ai/desktop/acp.md
- How pending context is encoded over ACP: [unverified].

## 5. Google Antigravity (clearest split between approving and revising)

**1. Entry surfaces**
- Artifacts: task.md, implementation_plan.md, walkthrough.md, screenshots, browser recordings.
- The "Review Changes" pane: "you can comment on any of the file diffs to communicate with the agent" [docs] https://antigravity.google/docs/ide/review-changes-editor
- CLI Artifact Picker (Ctrl+R) [docs].

**2. What can be annotated**
- Plans and other text artifacts [docs].
- Screenshots ("comment on them to give feedback") [docs].
- File diffs [docs].
- Press coverage: "Google Doc-style comments on text Artifacts or select-and-comment feedback on screenshots" [3p].

**3. Anchors**
- CLI: line-level. `c` adds a comment, `Esc` saves, the line shows a 💬 marker, `d` deletes [docs].
- Desktop anchors and relocation are not documented [unverified].

**4. Submit**
- **Proceed** (in the conversation and the artifact header) advances the work, even when comments exist.
- **Review** opens a view to "examine all comments and leave a message as feedback instead of directly proceeding" [docs] https://antigravity.google/docs/artifact-review
- Review policy options: "Request review" or "Always proceed", planning mode only [docs].
- CLI: `y`/`n` per file, `Shift+A` / `Shift+R` bulk, and `Esc` "submits approvals/rejections back to the agent thread" [docs].

**5. Serialization**
- From the planning-mode dump [prompt, x1xhlol `Google/Antigravity/planning-mode.txt`]:
  - "Use notify_user to request review, update based on feedback, and repeat until user approves before proceeding to EXECUTION."
  - "If user requests changes to your plan, stay in PLANNING mode, update the same implementation_plan.md, and request review again via notify_user until approved"
- The plan template has a `## User Review Required` section.
- Edit tools carry `ArtifactMetadata{ArtifactType}` and `Complexity: "A 1-10 rating of how important it is for the user to review this change"`.
- The comment payload format is not in the dump.

**6. Lifecycle:** the plan is revised in place and review is requested again. No resolve or replies are documented.

**7. Persistence:** artifacts live in `~/.gemini/antigravity/brain/<conversation-uuid>/` [prompt]. Comment persistence is unknown.

**8. Exposure:** MCP client and a Python SDK. No ACP found.

## 6. JetBrains: Junie, AI Assistant and Air

**1. Entry surfaces**
- AI Assistant chat: the selection is added automatically; @selection, @thisFile, @localChanges [docs].
- Air in IDEs: "Add to Agent Context" on a selection, file, console, test or VCS change; screen capture [docs] https://www.jetbrains.com/help/air-ides/air-interact-with-the-agent.html

**2. What can be annotated**
- AI Assistant: per-file Accept/Discard.
- Junie plan (requirements, design and delivery tabs): edit it directly, then press Confirm (Shift+Tab for Plan mode) [docs].
- Junie code review: inline accept/reject [docs].
- Brave mode skips approvals [docs].

**3. Anchors (Air)**
- A note covers a gutter line or selected lines ("a range of lines to an entire changed block"); Alt+Shift+K adds one.
- **No automatic relocation.** The docs tell users to check whether a note still applies after the agent rewrites the lines [docs] https://www.jetbrains.com/help/air-ides/air-review-agent-changes.html

**4. Submit**
- Air in IDEs: notes go "back to the agent in your next message". Each file with notes becomes **one diff attachment** that shows the file name, note count and lines covered.
  - Notes can be edited or deleted before sending. Removing the attachment drops that file's notes [docs].
- Standalone Air: "Add Comment" collects, "Send Comments" sends the batch, and a Comments tool lists them [docs] https://www.jetbrains.com/help/air/review-changes.html
- Agentic review: accepted comments go back "as follow-up instructions" [docs-snippet].

**5. Serialization:** not documented.
- The Junie dump shows only `<issue_description>` and "INITIAL USER CONTEXT" [prompt, x1xhlol `Junie/Prompt.txt`].

**6. Lifecycle:** after sending, notes "remain on the sent message as a read-only attachment" [docs]. No replies.

**7. Persistence:** notes are scoped to a session and do not carry over to other sessions [docs]. Junie plans are saved in `.junie/plans` [docs].

**8. Exposure**
- Junie's IDE integration was rebuilt on ACP. Air drives Claude, Codex, Gemini and Junie over ACP [docs].
- So review notes almost certainly travel in `session/prompt`, flattened into text or resource blocks [unverified]. ACP has no comment or range field.

## 7. Kiro (approval gates enforced in the prompt)

**1. Entry surfaces**
- Specs in `.kiro/specs/<name>/{requirements|bugfix, design, tasks}.md`.
- Context mentions: #File, #Folder, #Problems, #Terminal, #Git Diff, #Codebase; images.
- Steering files in `.kiro/steering`; hooks [prompt, x1xhlol `Kiro/Spec_Prompt.txt`].

**2. What can be annotated**
- The three spec documents. Each phase gate loops on "Edit/Request changes" [docs] https://kiro.dev/docs/specs/feature-specs.md
- "Refine" on design.md and "Sync Files" on tasks.md [3p].

**3. Anchors:** the IDE uses chat with no anchors. The CLI has line comments [docs].

**4. Submit**
- CLI: at a checkpoint, Ctrl+X stages line comments. Answering the checkpoint "sends your comments to the agent as one revision request" [docs] https://kiro.dev/docs/specs.md
- Quick Spec runs "without approval gates" [docs].

**5. Serialization [prompt]**
- "The 'userInput' tool MUST be used with the exact string 'spec-requirements-review' as the reason" (also `spec-design-review` and `spec-tasks-review`).
- "MUST NOT proceed to the design document until receiving clear approval (such as "yes", "approved", "looks good", etc.)"
- "MUST make modifications … if the user requests changes or does not explicitly approve"
- Context tags: `<OPEN-EDITOR-FILES>`, `<ACTIVE-EDITOR-FILE>`.
- In short, the model decides approval versus revision from the user's free-text answer.

**6. Lifecycle:** documents are rewritten in place. Task status is tracked [docs].

**7. Persistence:** spec files live in the repo. CLI ACP sessions are stored at `~/.kiro/sessions/cli/<id>.json(l)` [docs].

**8. Exposure:** `kiro-cli acp` implements the standard methods plus `_kiro.dev/*` extensions. There is no spec-review or comment method [docs] https://kiro.dev/docs/cli/acp/

---

## Comparison

| App | Diff/file comments | Plan comments | Agent-message annotation | Batch submit | Serialization | Agent replies/resolve | Persisted | Protocol |
|---|---|---|---|---|---|---|---|---|
| VS Code Agents window | yes (range, quote, hunks) | yes (line/col + overall) | Quote / side chat | Submit Feedback; accept gate | inline text **or** ids + `listComments` tool | yes (tools) | SQLite (agent host) | AHP annotations channel |
| VS Code classic chat | no (selection attach) | n/a | no | next message | `<attachment>` excerpt | no | chat history | VS Code API |
| Zed | no (keep/reject) | n/a | no | next message | `<context><selections>` / ACP resource `#L` | no | thread DB | ACP client |
| Cursor | no locally; PR only | no (edit file, Build) | Add to Chat | next message | `<manually_added_selection>` etc. | PR: GitHub resolve | GitHub / server | ACP `cursor/create_plan` |
| Windsurf | no | no | no | next message | metadata (undocumented) | no | n/a | hosts ACP agents |
| Antigravity | yes | yes (+ screenshots) | no | Review vs Proceed | undocumented | revise-and-rerequest | brain dir | MCP |
| JetBrains Air | yes (line ranges) | Junie: edit + Confirm | no | per-file attachment / Send Comments | undocumented | read-only after send | per session | ACP |
| Kiro | CLI line comments | spec gates | no | checkpoint batch | free text via `userInput` | rewrite in place | repo files | ACP (no comment method) |

## Design patterns worth borrowing for the Emacs package

1. **An explicit lifecycle with an accept gate.** Use Created → Accepted → Submitted → Resolved (VS Code). Notes the agent proposes stay hidden until the user accepts them. "Sent" and "resolved" are different states.
2. **Author on every entry.** Record `kind` (where the thread came from) and `author` (`user`, `agent`, `reviewer`) per entry. Tell the model to treat only `user` text as instructions. This matters when agent-shell transcripts quote earlier agent text.
3. **Pick one of two delivery modes.** Either inline text (path:lines, quote, diff hunks, comment) or ids in the prompt with content fetched through tools (`listComments` / `replyToComment` / `resolveComments`). The second suits an MCP server the Emacs package could expose.
4. **Store the quote and the hunk next to the range.** `codeSelection` and `diffHunks` are captured at creation. Nobody does real relocation; JetBrains tells users to check notes themselves. Crit's drift detection would go beyond every app here.
5. **External thread linkage.** "(PR review comment on o/r#N, thread ID: X — resolve this thread when addressed)" ties a note to an external thread the agent can close.
6. **Keep approving separate from revising.** VS Code plan review offers approve actions *or* overall plus inline feedback, and returns structured JSON. Antigravity has Review vs Proceed. Cursor's ACP has `cursor/create_plan` accepted/rejected(reason).
7. **Ready-made prompt shapes.** Zed: `<context>` "up-to-date and don't need to be re-read" and the fence tag `ext path:L1-L2`. Cursor: `<manually_added_selection>`. The VS Code side-chat seed block with a `length=` header can be parsed back reliably, which helps when annotating agent messages.
8. **Group notes by file.** JetBrains Air sends one attachment per file with notes and line counts, editable until sent and read-only after.
9. **Hidden machine-readable markers in human text.** Bugbot uses `<!-- BUGBOT_BUG_ID -->` and `<!-- LOCATIONS -->` to round-trip anchors through Markdown.
10. **ACP has no annotation type.** Over agent-shell, notes must be flattened into text or `resource` blocks with `file://…#L<a>:<b>` URIs, as Zed does. A richer channel would need an MCP server or an ACP `_meta` extension.
