---
title: How the capture popup behaves
type: grilling
status: closed
assignee: claude
blocked-by: [002]
---

## Question

Pin the capture interaction: what the popup shows (quote, location), its
keys (save, abort), what is captured with no active region in files and
transcripts (Magit is settled in
[What one captured note looks like](004-entry-format.md)), a region that spans several hunks or
transcript blocks, and how evil state and Doom's popup rules should treat
the window.

Also: how the `claude` style frames transcript fragments other than a
reply (thinking, tool call `<title>`) and whether "your last reply" is used
for the latest turn; the resolved format only fixes
`In your reply to "<prompt…>":`.

Existing notes are edited in the review's edit mode, not in this popup
([What one captured note looks like](004-entry-format.md)).

## Resolution

Grilled with Bill, 2026-10-11. Facts from agent-shell 70616c4a: block kinds
come from the block-id suffix; `agent-shell--turn-position` gives the turn
index and whether it is the latest; `agent-shell-markdown-reconstruct BEG END`
returns Markdown only for whole constructs; transcript text changes after it
renders; the viewport carries the same text properties.

- **Sources**: an ordered defcustom of source types; the first whose
  predicate matches captures. Default order: agent-shell transcript (shell
  buffer or `[viewport]`, whose note belongs to the viewport's shell and the
  page's turn), Magit diff, dired, file, generic buffer fallback. A new mode
  (eww, Info) is an entry before the fallback.
- **Extent**:
  - File: the region, or the current line.
  - Magit: as in [What one captured note looks like](004-entry-format.md).
    A region may cross hunks in one file: one note, range from first to
    last selected line, every touched hunk recorded. Crossing files is a
    `user-error`.
  - Dired: the marked files, else the file at point; with a region, the
    files on the lines it touches. Paths only, no quote; the review groups
    them by directory.
  - Transcript: the region, or the current line. A region quotes whatever
    it covers, across blocks and turns, rendered as
    `agent-shell-copy-as-markdown` does (tool calls under their headings).
    No block kind is excluded, prompts and permissions included.
  - Fallback: the region or the current line; records buffer name, major
    mode, line range and the project from `default-directory`. `RET` jumps
    if the buffer still lives, else says it is gone.
- **Snapshot**: the quote is copied at capture; markers are kept only for
  jumping. Capturing during a streaming turn is allowed.
- **`claude` framing** (decided at send):
  - One block: `In your reply to "<prompt…>":`, `In your thinking for
    "<prompt…>":`, `In your tool call "<title>" for "<prompt…>":`,
    `In your plan for "<prompt…>":`.
  - Other kinds, or a region across blocks: the turn's
    `In your reply to "<prompt…>":`. Across turns:
    `In your replies from "<p1…>" to "<p2…>":`.
  - `your last reply` (`your last thinking`, ...) when the target is the
    note's own session and its single turn is still the latest.
  - Dired: ``About `a.el`, `b.el`:``. Fallback:
    ``In buffer `*Help*` (help-mode) at lines S-E:``.
  - `codex` and `omp` render dired and fallback notes in our own format
    (`Files:` line; `# Feedback on <paths>` / `<buffer>`), as no app has one.
- **Popup**:
  - A package-owned Markdown buffer with a stable name, shown with
    `pop-to-buffer` and a customizable display action (default: a small
    bottom window), in evil insert state when evil is loaded.
  - Read-only location and quote at the top (quote folded after 6 lines),
    the note area below, key hints in the header line.
  - `C-c C-c` saves; an empty note is saved as a quote-only note.
    `C-c C-k` aborts without asking.
  - One popup at a time: a second capture switches to the open one. The
    window layout is restored on close.
  - The Doom popup rule belongs to the map's Doom-config fog item (Doom's
    org-capture rule, `:size 0.42 :quit nil :select t`, is prior art).
- Glossary: Capture and Source added.

## Comments

- 2026-10-11: [Confirm the Claude desktop diff-comment template from a real
  session](008-confirm-claude-template.md) replaces the `claude` sentences
  above (`In your reply to …`, `your last reply`, per-kind and cross-turn
  forms) for notes on the target session's own transcript with Claude's
  native `<!-- reply N -->` quote blocks. Quotes from another session are
  unchanged.

- 2026-10-11: [Which entry commands and bindings ship, and what Doom
  adds](010-entry-bindings.md) rules Doom popup rules and leader keys out of
  scope: the package is Doom-agnostic and keeps only its display action.
