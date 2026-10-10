# Annotations in agent protocols and agent apps (research, 2026-10-10)

Scope: (A) ACP + MCP, how ACP agents consume quote/file/range context, and how
Bill's agent-shell fork builds prompts today; (B) other agent apps and
review-comment loops. Verification markers: **[src]** verified in source,
**[docs]** verified in docs, **[artifact]** seen in a real public artifact,
**[unverified]**.

Sources read:

- ACP spec: `github.com/agentclientprotocol/agent-client-protocol` @ `f4b7c8d`
  (2026-10-10), cloned locally.
- Zed (reference ACP client): `~/Repositories/refs/zed` @ `53e4d34` (2026-06-29,
  shallow) plus Zed commit `415f384ff` via the GitHub API.
- claude-agent-acp: `~/Repositories/forks/claude-agent-acp` @ `4704134`.
- codex-acp (TS, agentclientprotocol org): `~/Repositories/refs/codex-acp` @ `ba5bcc3`;
  codex: `~/Repositories/refs/codex` @ `2df67054`.
- gemini-cli: cloned @ `9b6e026` (2026-10-09).
- omp: `~/Repositories/forks/oh-my-pi` @ `47281d5276`; pi-acp: `~/Repositories/forks/pi-acp` @ `7a64e8d`.
- agent-shell fork `~/Repositories/forks/agent-shell` @ `70616c4a`; acp.el fork @ `c7b060c`.

---

## Bottom line

1. **ACP has no annotation, comment, review, or range primitive.** Prompt
   content is MCP's `ContentBlock` (text, image, audio, `resource`,
   `resource_link`). Nothing carries a line range, a quote, or an anchor as a
   structured field. [src: `schema/v1/schema.json`, `docs/protocol/v1/content.mdx`]
2. **MCP `annotations` (audience / priority / lastModified) are irrelevant
   for this.** They are display or routing hints. None of the five agent
   adapters reads them when it converts a prompt (zero references in each
   prompt converter). [src]
3. **No open RFD, PR, issue, or discussion proposes ranges or review comments
   on prompt content** (searched issues/PRs/discussions for annotation,
   selection, range, resource_link, comment, review, embedded). The nearest
   items are listed in A.3. [src: GitHub search 2026-10-10]
4. **The de facto range convention is Zed's URI fragment**
   `file:///abs/path#L<start>:<end>` (1-based, inclusive) on a `resource`
   block whose `text` is the selected lines, or on a `resource_link` when the
   agent lacks `embeddedContext`. [src: zed `crates/acp_thread/src/mention.rs`]
5. **Recommendation: put the citation and quote in a `text` block; treat
   resource blocks as optional extras.** Only the text block survives every
   target unchanged. omp drops the URI of a text resource, and drops the URI
   of a `resource_link` too, sending only its name. pi-acp disables
   `embeddedContext` by default. Gemini turns a `file://` `resource_link` into
   a real file read, which fails on a `#L` fragment. Claude and Codex render
   resources as `[@name](uri)` plus `<context ref="uri">…</context>`. Details
   and a template are in A.5.

---

## A. Protocols

### A.1 ACP content model [src]

- `session/prompt.prompt` is `ContentBlock[]`. "All Agents MUST support text
  content blocks"; the schema says the baseline is `Text` + `ResourceLink`;
  `image`, `audio`, and `embeddedContext` (the `resource` block) need
  `promptCapabilities` opt-in (`PromptCapabilities` in `schema/v1/schema.json`;
  in v2 these are objects: `capabilities.session.prompt.{image,audio,embeddedContext}`).
- `resource` = `{type:"resource", resource:{uri, text|blob, mimeType?, _meta?}, annotations?, _meta?}`.
  The docs call it "the preferred way to include context in prompts, such as
  when using @-mentions".
- `resource_link` = `{type:"resource_link", uri, name, title?, description?, mimeType?, size?, annotations?, _meta?}` (v2 draft adds `icons`).
- `Annotations` = `{audience?: ("user"|"assistant")[], priority?: number, lastModified?: string, _meta?}`.
  No range or anchor field.
- v2 draft: custom content block types are allowed if they begin with `_`
  ("Custom content block types MUST begin with `_`", `docs/protocol/v2/draft/content.mdx`).
  An `_annotation` block type would be legal in v2, but no agent would
  understand it.
- `_meta` is allowed on every block and on `TextResourceContents`. It is the
  only legal place to attach structured anchor data (for example
  `_meta: {"annotation": {"path":…, "side":"new", "lines":[10,20], "id":…}}`).
  No agent reads it today [src: grep of every prompt converter], so it would
  serve only as a round-trip channel for Bill's own client.

### A.2 MCP `annotations` [docs + src]

MCP defines `annotations` on content, resources, and resource links as
`audience`, `priority` (0–1), and `lastModified`: "hints" for clients choosing
what to show or include. ACP copies the type verbatim. It does not model an
anchor and does not reach the model: claude-agent-acp, codex-acp, gemini-cli
ACP, omp ACP, and pi-acp all ignore `annotations` during prompt conversion.
Verdict: **not relevant**. The most you could do is set
`audience:["assistant"]` on a context resource. It would cost nothing and
would change nothing.

### A.3 Proposals and discussions that come close (none cover annotations)

| Item | What it does | Relevance |
|---|---|---|
| RFD `next-edit-suggestions.mdx` (merged, #571) | NES request carries `uri`, `position`, `selection:{start:{line,character},end:…}` | Editor state sent to an NES provider, not prompt content. A useful shape to copy for a range object. |
| PR #895 "HITL Editing" (open) | `fs/write_text_file` response gets `action`, `userModification{diff, finalContent}`, `feedback` string | User feedback on an agent's write. The nearest thing to "comment on a diff" in ACP, but only at write-approval time. Cites Cline/Roo `user_edits`. |
| Discussion #929 | Adds `source: agent/tool/file/user/external` to `TextContent` | Provenance, not anchors. |
| PR #2315 (open, 2026-10-06) | Negotiated `text/org` / Portable Org format for agent output | Not anchors, but relevant to an Org-based Emacs client. |
| PR #1849 embedded views, #1237 client-provided system prompt | — | Not relevant. |

Searches for "line range", "code selection", "review comment", and
"resource_link range" returned nothing. [src: `gh search` / GraphQL, 2026-10-10]

### A.4 How each agent turns blocks into model text [src]

Example input (Zed's shape): `text("Fix this:")`,
`resource{uri:"file:///p/a.rs#L2:3", text:"line 2\nline 3\n"}`, `text("please")`.

| Agent | `embeddedContext` | `resource` (text) becomes | `resource_link` becomes | Notes |
|---|---|---|---|---|
| claude-agent-acp (`src/acp-agent.ts` `promptToClaude`, ~L10961) | `true` (+image) | inline text `[@a.rs#L2:3](file:///p/a.rs#L2:3)`; then **at the end of the whole message** `\n<context ref="file:///p/a.rs#L2:3">\nline 2\nline 3\n\n</context>` | `[@<basename>](uri)` (drops `name`) | Blob resources are dropped silently. The `<context>` blocks sit apart from the inline link. |
| codex-acp TS (`src/CodexAcpClient.ts` `buildPromptItems`) | `true` | one text item in place: `[@a.rs#L2:3](uri)\n<context ref="uri">\nline 2\nline 3\n\n</context>` | `[@<name>](uri)` (keeps `name`) | Blobs become `<context ref mimeType encoding="base64">`; image blobs become images. Every item has `text_elements: []`. Codex `TextElement` is a UI placeholder byte range (`codex-rs/protocol/src/user_input.rs:58`), not a file anchor. |
| gemini-cli (`packages/cli/src/acp/acpSession.ts` `#resolvePrompt` ~L952) | `true` | inline `@file:///p/a.rs#L2:3`; at end `\n--- Content from referenced context ---` then `\nContent from @<uri>:\n` + text | `file://` link becomes `fileData` → **runs a real `read_many_files` tool call** (sends `tool_call_update`) and appends `--- Content from referenced files ---` / `Content from @<path>:` with the **whole file**. Non-file links become `@<uri>`. | A `#L2:3` fragment stays in the path, so `fs.stat` fails, the path is logged and skipped (`continue`) [src read; runtime unverified]. |
| omp (`packages/coding-agent/src/modes/acp/acp-agent.ts` `#convertPromptBlocks` ~L2179) | `true` | **only `resource.text`; the URI is dropped** | `title ?? name ?? uri` (URI dropped whenever `name` is set, and `name` is required) | Parts are joined with `\n\n`. Any anchor carried only in a URI is lost. |
| pi-acp (`src/acp/translate/prompt.ts`) | **`false` unless `PI_ACP_ENABLE_EMBEDDED_CONTEXT=true`** (`src/acp/agent.ts:270`) | `\n[Embedded Context] <uri> (<mime>)\n<text>` | `\n[Context] <uri>` | Text blocks are concatenated with no separator. |

None of them reads `annotations` or block `_meta` for prompt content.

### A.5 Recommendation: quote + file + range to an ACP agent today

**Primary carrier: one `text` block per note batch.** It is baseline-required
and is the only form whose citation reaches the model intact on all five
agents. Use a stable, greppable layout that models already handle, close to
what the agents themselves produce:

````text
Review notes (3). Address each; cite the note id in your reply.

[N1] modules/foo.nix:12-14 (new side, HEAD 1a2b3c4)
```nix
  services.foo.enable = true;
  services.foo.port = 80;
```
Comment: port 80 needs root; use 8080 behind the proxy.

[N2] agent transcript, turn 7 (assistant)
> I'll skip the tests because the build is slow.
Comment: don't skip; run tests/foo.nix only.
````

- Path relative to the session `cwd` with `:start-end`, 1-based inclusive.
  This matches agent-shell's existing `path:12-14` label and Zed's
  `line_range_suffix`.
- For diffs, state the side (old/new) and the revision. Quote the hunk lines
  with their `+`/`-`/space prefixes in a ```` ```diff ```` fence, because a
  new-side line number alone is ambiguous for deleted lines.
- Stable note ids (`N1`…) let the agent's reply be matched back to
  annotations. ACP has no structured reply channel for this.

**Optional extra, gated on `embeddedContext`:** for Zed-compatible clients and
for Claude/Codex, also send a `resource` block per quote,
`{uri:"file:///abs/path#L12:14", text:<the exact lines>}`, so the client
renders a mention chip and Claude/Codex see `<context ref=…>`. Avoid it for
omp (URI lost, text duplicated) and pi (off by default). Avoid
`resource_link` with `#L` for Gemini (triggers a file read that fails, or
reads the whole file). If Bill wants a lossless round trip for his own tools,
put structured anchors in `_meta` on the text block: harmless and ignored by
agents.

Do not rely on `annotations` or on line ranges in `resource_link`.

### A.6 Zed: the reference ACP client's selection and review features [src]

- **Add selection to thread** (`crates/agent_ui/src/mention_set.rs` ~L530):
  `MentionUri::Selection{abs_path, line_range}` →
  `file:///abs#L<start+1>:<end+1>`; content = raw selected text (no fence,
  no line numbers). It is sent as `resource` if `embeddedContext`, else as
  `resource_link{name:"a.rs (2:3)", uri}`
  (`crates/agent_ui/src/message_editor.rs` `mention_to_content_block`).
  Blocks interleave with the user's text in typing order.
- Other mention URIs: `file:///abs?symbol=Name#L10:20`,
  `zed:///agent/thread/<id>?name=…`, `zed:///agent/terminal-selection?lines=N`,
  `zed:///agent/git-diff?base=main`, `zed:///agent/untitled-buffer#L…`. Text
  form: `[@name](uri)`.
- **Review Diff** button (`agent_panel.rs` ~L535, `ReviewBranchDiff`): sends
  `text("Please review this branch diff carefully. Point out any issues,
  potential bugs, or improvement opportunities you find.\n\n")` followed by
  `resource{uri:"zed:///agent/git-diff?base=<ref>", text:<diff>}` and submits
  automatically.
- **Diff review comments → "Send Review to Agent (N)"** (commit `415f384ff`,
  PR #46669, Jan 2026, behind a feature flag at the time): the user adds
  comments per hunk in the project diff (anchored with `Range<Anchor>`, so
  they move with edits; `cleanup_orphaned_review_comments` deletes comments
  whose anchors become invalid). Comments are stored locally, then
  **batch-submitted**: `take_all_review_comments` clears the store, groups by
  identical range, and builds a selection crease per range where
  `code_text = format!("{}\n\n{}", code_text, comments.join("\n\n"))` and
  title `Review: <name>`. These are inserted into the message editor (not
  auto-sent). On the wire this is a Selection `resource` (`#Lx:y` URI) whose
  text is the code followed by the comments. [src at that commit] In the
  2026-06-29 checkout the storage/UI code and the `SendReviewToAgent` button
  still exist, but no handler for the action is registered (and
  `selections_creases` is gone). Current shipped state: [unverified].
  No resolve or reply lifecycle; comments disappear once sent.

### A.7 Bill's agent-shell fork today [src]

- `agent-shell--build-content-blocks` (`agent-shell.el` ~L11022): only
  `@path` mentions become structured blocks. Images become `image` when
  supported; text files under `agent-shell-embed-file-size-limit` become
  `resource{uri:"file://<abs>", text, mimeType}` when
  `agent-shell-text-file-capabilities` and `embeddedContext` are both on;
  otherwise `resource_link{uri, name:<relative path>, mimeType, size}`.
  These are **whole files; no ranges**. Everything else is `text`.
- Regions (`agent-shell-send-region` → `agent-shell--get-region-context`
  ~L13145) go as **plain text**: label `relpath:START-END` (verbatim text with
  a button property) + `\n\n` + numbered lines `"   N: <line>"`, shown capped
  at 5 lines with an "Expand..." button; `agent-shell--expand-truncated-regions`
  restores the full text before sending. A single-line region is sent without
  numbering.
- `agent-shell--get-decorated-region` (~L13490): `"<abs-file>#C<char-start>-C<char-end>\n\n```<lang>\n<content>\n```"` (character offsets).
- `agent-shell-quote-region` (~L14490, transcript quoting): Markdown block
  quote `> ` lines inserted at the prompt; no source citation.
- The public send path (`agent-shell-insert :text … :submit`,
  `agent-shell--send-command`) accepts **text only** and derives blocks from
  `@` mentions. No API takes raw content blocks. A new package that wants
  `resource` blocks or `_meta` must either add such an entry point or call
  `acp-make-session-prompt-request` (acp.el passes `:prompt` through as a
  vector of blocks) itself.

---

## B. Other agent apps and review-comment loops

NOT COMPLETED. Two background research passes were launched: (1) Aider
watch-mode, Gemini CLI IDE context, Amp, and Cline/Roo; (2) Copilot coding
agent, Devin, Jules, CodeRabbit "Prompt for AI Agents", Graphite, Bugbot, and
Greptile. Neither had returned when this report was handed back, so no Part B
findings are recorded here. Re-run them before relying on Part B.
