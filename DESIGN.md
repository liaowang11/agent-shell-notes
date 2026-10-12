# Design: agent-shell-notes

Status as of 2026-10-11. Nothing is built. This is the hand-off from the
wayfinder map in `docs/wayfinder/map.md`: every decision below was made in a
closed ticket under `docs/wayfinder/tickets/`, and this document states the
final shape only. Where tickets superseded each other, the later one wins
and the earlier wording is not repeated. A few gaps no ticket closed are
settled here and listed in [section 13](#13-calls-made-in-this-document).

This supersedes the earlier design: `git show 0e6b22c:DESIGN.md`.

Facts were re-checked against agent-shell (Bill's fork,
`~/Repositories/forks/agent-shell`, `70616c4a`) and Magit 4.7.0 (`67f2038`,
the straight build). `docs/research/` is the fact base for everything else
(package survey, agent app wire formats, compose-buffer facts).

## 1. What it is

An Emacs package. Bill selects text in a Magit diff, a file, a dired
listing, an agent-shell transcript, or any other buffer, writes a remark,
and keeps going. The remarks collect in one global **review**. From the
review he marks some or all, picks a live agent-shell session, and sends
them as one prompt rendered in the wire format of a chosen agent app
(Claude desktop, Codex, omp), optionally with a free-text request. Two
workflows weigh the same: a quick pass over the agent's last reply, and a
broad pass across files, diffs and several sessions.

Vocabulary is `GLOSSARY.md`: Note, Capture, Source, Review, Mark, Send,
Request, Style, Client, Target session, Archived note.

### Out of scope (v1)

- Persistence across Emacs restarts.
- Re-anchoring notes after a Magit refresh or a transcript re-render.
- Highlights on source text (needs re-anchoring; attach points recorded in
  ticket 007).
- difftastic buffers, PDFs, plans as artifacts.
- Doom configuration: leader keys, `set-popup-rule!`. The package is
  Doom-agnostic.
- Notes written by the agent, MCP tools, parsing the agent's reply, threads.

## 2. Package

- File `agent-shell-notes.el`, feature `agent-shell-notes`, prefix
  `agent-shell-notes-`, repo `agent-shell-notes` (rename of this repo and
  its clone at the start of implementation; GitHub redirects). No alias
  prefix.
- `Package-Requires: ((emacs "29.1") (agent-shell) (markdown-mode))`.
- Markdown parent: the review and the popup derive from `markdown-ts-mode`
  when it can run (the mode exists, Emacs 31 and later, and
  `treesit-ready-p` with QUIET accepts both `markdown` and
  `markdown-inline`; without the inline grammar the mode falls back to
  `text-mode` itself), else from `markdown-mode`, which stays a
  dependency. Option `agent-shell-notes-markdown-mode`: `auto` (default),
  `markdown-ts-mode` (same, but warns on fallback), `markdown-mode`. Read
  once when the package loads; a change needs a reload
  (`load-library`) and reopened buffers.
- Mechanism: `agent-shell-notes--markdown-mode` is a `defalias` to the
  chosen mode, and both modes are `define-derived-mode` children of that
  alias. Calling the alias runs the real mode, so its body and hooks run
  (`markdown-ts-mode-hook`, not `markdown-mode-hook`, under the
  tree-sitter mode). `derived-mode-p` follows a parent that is an alias
  on 29.1 (`provided-mode-derived-p`) and on 31
  (`derived-mode-all-parents`), so it reports the real mode. The package
  maps get the chosen mode's map as parent at load, explicitly, so a
  reload moves them. Each mode body turns off markdown-ts-mode's
  `markdown-ts-code-block-context-mode`: its map takes `TAB` inside code
  blocks, and the quotes are read-only code blocks whose `TAB` folds.
  Magit is a soft dependency via `declare-function`; the Magit source type
  is skipped when Magit is not loaded.
- Buffers: `*agent-shell-notes*` (the review) and
  `*agent-shell-notes capture*` (the popup).
- Global entry commands: `agent-shell-notes-capture`,
  `agent-shell-notes-review`, `agent-shell-notes-send-all`. No bindings
  outside the package's own buffers, no prefix keymap, no keys added to
  Magit or agent-shell maps. The README suggests bindings.

## 3. Data model

One global in-memory list, `agent-shell-notes--notes`, newest appended.
Nothing is read back from a buffer; the review is redrawn from this list.
A note is an alist:

```elisp
((:id . 7)                    ; monotonic per Emacs session
 (:source . transcript)       ; transcript | magit | dired | file | buffer
 (:project . "/abs/root/")    ; project root at capture (default-directory
                              ;  fallback), used for grouping and paths
 (:location . <per source, below>)
 (:quote . "...")             ; text copied at capture; nil for dired
 (:text . "Bill's remark")    ; may be ""
 (:markers . (BUF BEG END))   ; for jumping only; BUF may be dead
 (:archived . nil)            ; nil, or the name of the last target session
 (:created . <time>))
```

Per-source `:location`:

| Source | Fields |
| --- | --- |
| `magit` | `:file` (relative to project), `:side` (`new`/`old`), `:start`/`:end` (line numbers on that side), `:hunks` (full text of every hunk touched, header line first, in order), `:type` (`staged`/`unstaged`/`committed`), `:rev` (for committed), `:mixed` (t when the selection held both `+` and `-` lines) |
| `file` | `:file` (absolute), `:start`/`:end` |
| `dired` | `:files` (absolute paths), `:directory` |
| `transcript` | `:session-id`, `:shell` (buffer name), `:turn` (1-based), `:kind` (`message`/`thought`/`tool`/`plan`/`prompt`/`permission`/`mixed`), `:prompt` (first line of the turn's prompt), `:turn-end` (for a region across turns) |
| `buffer` | `:buffer` (name), `:mode` (major mode), `:start`/`:end` |

The quote is a snapshot. Markers keep a best-effort way back to the
source; if the text moved, the jump lands on whatever is there now.

## 4. Capture

`agent-shell-notes-capture` works in any buffer. It never asks for a
target session and never fails for lack of a shell.

### 4.1 Source types

`agent-shell-notes-sources` is an ordered list of
`(SYMBOL PREDICATE EXTRACT)`; the first whose predicate matches captures.
Default order: `transcript`, `magit`, `dired`, `file`, `buffer` (the
fallback, always matches). A user adds a new mode (eww, Info) as an entry
before the fallback.

| Source | Predicate | Extent |
| --- | --- | --- |
| transcript | `agent-shell-mode`, or a `[viewport]` buffer (its shell via `agent-shell-viewport--shell-buffer`, `agent-shell-viewport.el:2040`) | region, else current line. A region quotes whatever it covers, across blocks and turns; prompts and permission dialogs included |
| magit | `magit-section-mode` with a `hunk` section at point or under the region | see 4.2; point on a file heading with no region: `user-error "Point is not in a hunk"` |
| dired | `dired-mode` | marked files, else file at point; with a region, files on the lines it touches. Paths only, no quote |
| file | `buffer-file-name` | region, else current line |
| buffer | always | region, else current line |

Capturing during a streaming turn is allowed.

### 4.2 Magit extent and line mapping

- Region inside one hunk: its lines. No region: the line at point. Point on
  a `@@` header: the whole hunk.
- A region may cross hunks within one file: one note, range from the first
  to the last selected line, every touched hunk in `:hunks` as full text
  (the hunk section's `buffer-substring`, heading included). Crossing
  files is a `user-error`.
- Side: `new` unless every selected line is a deletion (`-`), then `old`.
  A selection holding both `+` and `-` lines is `new` with `:mixed t`;
  every style treats it as a new-side selection (`codex` writes `Side: R`,
  never `L-R`).
- Line numbers come from `magit-diff-hunk-line SECTION GOTO-FROM`
  (`magit-diff.el:2041`) at the first and last selected line, `GOTO-FROM`
  nil for the new side and `t` for the old; never from parsing `@@` text.
  The hunk section is `magit-current-section` or the section at each
  region end (`magit-section-at`).
- `:file` is `magit-file-at-point` (`magit-git.el:1367`), relative to
  `magit-toplevel`. `:type` is `magit-diff-type` (`magit-diff.el:3526`);
  `committed` records `magit-buffer-diff-range` (`magit-diff.el:979`) or
  `magit-buffer-revision` (`magit-mode.el:584`) as `:rev`.
- The quote keeps every selected line with its `+`/`-`/space prefix.
  Styles strip, keep or filter them at render (section 8).

### 4.3 Transcript facts

- Block kind: the fragment's `:qualified-id` under the `agent-shell-ui-state`
  text property (`agent-shell-ui.el:190`, `:714`) is `<namespace>-<block-id>`.
  Block ids contain `-agent_message_chunk` (`agent-shell.el:4071`),
  `-agent_thought_chunk` (`:4184`; a subagent's thought has a trailing
  index), `-plan` (`:4142`), `-user_message_chunk` (`:4243`); a tool
  call's block id is the tool call id itself (`:3872`). A region over
  several kinds is `mixed`.
- Turn: in a shell buffer, `agent-shell--turn-position`
  (`agent-shell.el:11803`) gives `:current`. In a viewport view page,
  `agent-shell-viewport--page-cursor`'s `:index` (`agent-shell-viewport.el:121`,
  set by `--show-page` at `:1383`) is the 1-based turn; the shell's
  `agent-shell--turns` (`agent-shell.el:11732`) gives the prompt text.
  Whether the turn is still the latest is decided at render, not stored
  (8.3).
- Quote: `agent-shell--buffer-markdown-substring BEG END`
  (`agent-shell.el:2511`, the function behind `agent-shell-copy-as-markdown`):
  original Markdown for whole constructs, chrome rendered as headings (a
  turn `#`, a tool call `###`), partial constructs verbatim.
- Session id: `(map-nested-elt (agent-shell--state) '(:session :id))`, read
  in the shell buffer.

### 4.4 The popup

- Buffer `*agent-shell-notes capture*`, major mode
  `agent-shell-notes-capture-mode` derived from the Markdown parent (§2). Shown with
  `pop-to-buffer` and `agent-shell-notes-capture-display-action` (default:
  `display-buffer-at-bottom`, `window-height` 0.3). Evil insert state when
  evil is loaded (`evil-set-initial-state`, guarded by `featurep`). This
  is the only evil integration: the review ships no evil bindings, and
  evil users bind its commands in their own config.
- Top: read-only location line and quote (quote folded after 6 lines, `TAB`
  unfolds). Below: the note area, point there. Header line shows the keys.
- `C-c C-c` saves; an empty note is saved as a quote-only note. `C-c C-k`
  aborts without asking. Both close the window and restore the window
  configuration from before the capture.
- One popup at a time: a second `capture` while one is open switches to it.
- On save the note is appended to the list, and the review buffer, if
  live, is redrawn with the new note in place.

## 5. The review

`agent-shell-notes-review` opens `*agent-shell-notes*` with `pop-to-buffer`
and `agent-shell-notes-review-display-action` (default nil: whatever
`display-buffer` does), or switches to it if shown.

### 5.1 Display

Major mode `agent-shell-notes-review-mode`, derived from the Markdown
parent (§2).
The buffer is writable, but every span outside the request body carries
the `read-only` text property, so the single-letter keys in 5.2 act on
notes while the request body takes ordinary typing. The body carries no
`keymap` text property: such a property outranks every other map, evil's
state maps included, so under evil normal state it left every key in the
body dead. Instead the review map's printing keys, `RET` and `TAB` are
conditional bindings (5.2) that step aside in the body. Note commands
(`n`, `p`, `m`, ...) invoked with point in the request body `user-error`.
Redrawn from the note list on every change (the request body is kept).
Layout:

````markdown
# src/foo.el — ~/Repositories/personal/x
                                             <- group: file + project
**lines 42-44** `unstaged`                   <- note: bold range, tags
```elisp
+  (let ((cache (make-hash-table)))
+    (puthash key value cache)
```
the cache is created on every call; hoist it

**line 120**
...

# Claude Agent @ x — turn 3 — reply       <- group: session + turn + kind
**reply**  `sent to Claude Agent @ y`       <- archived tag
> I removed the retry loop because it was never reached.

it is reached when the socket closes early

# Request

<free text, editable>
````

- Groups: file + project (`magit`, `file`), directory + project (`dired`),
  session + turn + kind (`transcript`), buffer name (`buffer`). Groups
  are ordered by the capture time of their first note; notes inside a
  group by line (or turn position) ascending. A new note lands in place,
  not at the end.
- Tags: `staged` / `unstaged` / `commit <rev>`, `before changes` (old
  side), `sent to <session>` (archived). The turn index is shown and never
  sent.
- The quote is folded after 6 lines (invisible overlay with `...`), `TAB`
  on a note toggles it.
- Archived notes are dimmed (`agent-shell-notes-archived` face).
- The package faces are overlays, not `face` text properties: font-lock
  from the Markdown parent repaints text properties (`**line 7**` turned
  `markdown-bold-face`). The location line gets
  `agent-shell-notes-location`, each tag `agent-shell-notes-tag`, an
  archived note `agent-shell-notes-archived` above both, so it dims them
  too. The popup's location line works the same way. Every redraw starts
  with `remove-overlays`, so the overlays never pile up.
- Marks: `agent-shell-notes-mark-indicator` picks `fringe` (default; a
  margin `*` on a tty) or `background` (a face overlay on the whole note).
  Marks are overlays, never text.
- `# Request` is the last section. Its body is always editable (no edit
  mode needed; see the mechanism above). Empty means notes only.
- Writable regions (the request body, the popup's note area, edit-mode
  note texts) open after read-only text through the character before
  them, which must not pass `read-only` on. Its text property is
  `agent-shell-notes-rear-nonsticky`, an alias of `rear-nonsticky` in
  `char-property-alias-alist`: markdown-mode's font-lock strips
  `rear-nonsticky` and markdown-ts-mode's strips `category`, but neither
  touches the package's own property.
- The other half: every read-only character in the review is
  `front-sticky (read-only)`, so nothing is inserted before it whatever
  the character before says. Font-lock makes characters rear-nonsticky in
  a `> ` quote: markdown-mode puts `rear-nonsticky t` on link markup and
  URLs, markdown-ts-mode gives link buttons the `default-button` category,
  which carries it. Neither font-lock manages `front-sticky`. An
  edit-mode note text loses it along with `read-only`, so typed text never
  carries it, and so does the newline that ends the text: that newline is
  the one read-only character left not front-sticky, so the text takes
  typing at its end.
- Every note's extent is recorded as text properties
  (`agent-shell-notes-id` on the whole note, `agent-shell-notes-field` on
  `location`, `quote`, `text`) so keys, marks and edit mode know the
  boundaries.

### 5.2 Keys (`agent-shell-notes-review-mode-map`, customizable)

| Key | Command | Effect |
| --- | --- | --- |
| `n` / `p` | `-next-note` / `-previous-note` | move between notes |
| `m` / `u` | `-mark` / `-unmark` | note at point, or every note the region touches, then move to the next |
| `t` | `-toggle-marks` | toggle all; from none, marks all; archived notes skipped |
| `U` | `-unmark-all` | |
| `k` | `-delete` | delete the note at point, no confirmation |
| `D` | `-delete-marked` | delete marked notes, confirming |
| `x` | `-purge-archived` | delete every archived note, no confirmation |
| `e` | `-edit` | enter edit mode with point in this note's text |
| `C-c C-e`, `C-x C-q` | `-edit-mode` | wdired-style edit mode (5.3) |
| `RET`, `mouse-1` | `-jump` | on a location line or group heading: jump to the source (section 9) |
| `TAB` | `-toggle-quote` | fold/unfold the quote |
| `C-c C-c` | `-send` | send marked notes (else the note at point) to a picked target (section 6) |
| `C-u C-c C-c` | `-send` with prefix | render and append to the target's compose buffer instead |
| `w` | `-copy` | copy the rendered text of the same notes to the kill ring; changes nothing |
| `C-c C-r` | `-restore-last` | undo the review-side effect of the last send or compose (7.3) |
| `g` | `-redraw` | |
| `q` | `quit-window` | |

`C-c C-c` or `w` with no marks and point in the request section or on no
note: `user-error "No note at point"`.

Every printing key above, plus `RET` and `TAB`, is bound as a `menu-item`
whose `:filter` returns nil when point is in the request body. The key
then falls through to the next active map: an evil state map, else the
global map, so letters insert. A void binding also skips the review map's
parent, so `RET` and `TAB` return the Markdown parent's binding in the
body instead (newline and cycling, as in any Markdown buffer). `C-c C-c`,
`C-c C-r`, `C-c C-e`, `C-x C-q` and `mouse-1` stay plain bindings, so they
work from the body too. The public predicate
`agent-shell-notes-in-request-p` is the filter's test; users apply it to
their own review bindings (an evil `j`, say) the same way.

### 5.3 Edit mode

`agent-shell-notes-edit-mode`, a minor mode like wdired: it lifts the
`read-only` property from the note texts; headings, locations and quotes
stay read-only and fence the notes. Its local map,
`agent-shell-notes-edit-mode-map`, replaces the review map, so letters
insert in the note texts and in the request body alike. `C-c C-c` commits every changed text back to the notes and leaves
edit mode; `C-c C-k` reverts and leaves. Emptying a text keeps the note as
quote-only. The mode line shows `Edit`. Marks and other keys are inactive
while editing.

## 6. Send

### 6.1 Target picker

The picker shows every live shell across all projects (fork and sidechat
sessions included), via `agent-shell--read-shell-buffer :buffers
SORTED :prompt "Send notes to: "` (`agent-shell.el:2140`; it renders icon,
name, status and session title). `SORTED` is `agent-shell-buffers`
(`agent-shell.el:2054`) ordered: the last target first, then shells whose
project is among the selected notes' projects, then the rest, most
recently used first within each band. The function offers no extra
column, so the project shows through the buffer name; this is noted in
section 13. No live shell: `user-error "No agent-shell session"`, review
untouched.

### 6.2 Client seam

`agent-shell-notes-client` is a plist of functions; v1 ships one value,
the agent-shell client:

| Slot | Signature | agent-shell client |
| --- | --- | --- |
| `:read-session` | `(hint) → session` where `hint` is `(:projects LIST :last SESSION)` | the picker above, returns the shell buffer |
| `:send` | `(session text)` | `(with-current-buffer session (agent-shell--prompt-send :prompt text :disposition agent-shell-notes-agent-shell-disposition))` (`agent-shell-prompt-queue.el:450`) |
| `:compose` (optional) | `(session text)` | see 6.3 |
| `:name` | `(session) → string` | `buffer-name`, used for the `sent to` tag |
| `:project` | `(session) → directory` | the shell's `default-directory`; decides relative or absolute paths at render (8) |
| `:session-id` | `(session) → string` | `(:session :id)` of the shell's `agent-shell--state`; decides "own session" at render |
| `:turn-count` | `(session) → integer` | `(length (agent-shell--turns))`; decides "last reply" at render |

`agent-shell-notes-agent-shell-disposition`: nil (default, defers to
`agent-shell-busy-submit-default-function`), `queue` or `steer`. A client
without `:compose` offers send and copy; `C-u` gives
`user-error "Client %s cannot fill a compose buffer"`.

`:send` counts as done when `agent-shell--prompt-send` returns normally,
whatever the disposition; `:on-delivered` is not used (it never fires for
a queued prompt, and nil disposition runs a user function). Any error
(gone session, "Starting agent, please wait", explicit `steer` refused)
propagates and changes nothing in the review.

### 6.3 Compose (`C-u C-c C-c`)

```elisp
(let ((disposition
       (when-let* ((vp (agent-shell-viewport--buffer :shell-buffer session
                                                     :existing-only t)))
         (buffer-local-value 'agent-shell-viewport--compose-disposition vp))))
  (agent-shell-viewport--show-buffer :append text :shell-buffer session
                                     :edit t :disposition disposition))
```

(`agent-shell-viewport.el:168`, `:1105`.) `:append` must be given, or `--show-buffer`
pulls in `agent-shell--context` (`:199`); `:disposition` must be read back
and passed, or the draft's queue/steer choice resets to nil (`:259-262`);
`:edit t` keeps a busy shell's viewport in edit mode. The text lands after
any existing draft, and the viewport window is selected (the function
cannot avoid focus). After-send applies as for a send.

### 6.4 Copy (`w`)

Renders the same notes and request, `kill-new`, message
`"Copied N notes"`. Nothing else changes.

### 6.5 `agent-shell-notes-send-all`

Sends every note that is not archived, as if all were marked and `C-c C-c`
pressed in the review, without opening it: marks are ignored, a non-empty
request follows, after-send and restore-last apply. `C-u` fills the compose
buffer. No unarchived notes: `user-error` before the picker. The review
buffer, if live, is redrawn.

## 7. After send

### 7.1 `agent-shell-notes-after-send`

`remove` (default), `archive` or `keep`; `agent-shell-notes-set-after-send`
changes it for the session. Applied by `C-c C-c`, `C-u C-c C-c` and
`send-all` once the client's `:send` or `:compose` returns. `w` never
applies it.

- `remove`: the sent notes leave the list.
- `archive`: they stay in place, dimmed, `:archived` set to the target's
  name (tag `sent to <session>`). An archived note can be marked and sent
  again, which updates the tag. `t` skips them, `x` purges them.
- `keep`: nothing changes on the notes.

### 7.2 Marks and request

Marks clear after every send or compose in every mode. The request goes
with every send (even of some marked notes) and clears after a send or
compose; `w` leaves it.

### 7.3 Restore last

The package keeps one level: the sent notes with their prior `:archived`
values, their list positions, the marks and the request.
`agent-shell-notes-restore-last` (`C-c C-r` in the review, also a global
command) undoes the review-side effect: under `remove` the notes return to
their positions, under `archive` their old tags come back; in every mode
the request and marks are restored. It does not unsend anything. A second
call with nothing stored: `user-error`.

## 8. Rendering

Text exists only at send or copy. `agent-shell-notes-style` picks `claude`
(default), `codex` or `omp`; `agent-shell-notes-set-style` changes it for
the session. Each style copies its app's wire text, wrapper included, from
`docs/research/agent-apps/` (`claude-desktop-diff-comments.md` and ticket
008 for `claude`, `codex-opencode.md` for `codex`, `omp-claude.md` for
`omp`). No preamble of our own. Numbers restart at 1 on every send.

Shared rules:

- Paths are relative to the note's `:project`. When that differs from the
  target session's project (`default-directory` of the shell), the path is
  made absolute (`claude`, `omp`) or a `Workspace:` line is added (`codex`).
- `staged` / `unstaged` / `commit` are never sent.
- Fence: backticks, one more than the longest backtick run inside the
  quote, minimum three. Info string: the language of the file, from
  `agent-shell-notes-fence-languages` (an extension → language alist with
  the common cases: `el` → `elisp`, `ts` → `typescript`, `md` →
  `markdown`, `py` → `python`, ...), else the file's `auto-mode-alist`
  major mode name without `-ts-mode` / `-mode`, else `text`.
- A quoted line is trimmed of trailing whitespace.
- Mixed batch order: `claude` puts own-session reply blocks first, then the
  rest in review order, then the request; `codex` follows its section
  order; `omp` is review order with the request last.
- "Own session": a transcript note whose `:session-id` equals the target's.
  Any other transcript note is a quote from another session.

### 8.1 `claude`

Diff and file notes:

````
In `<path>` at line <N>:                      (or `at lines S-E`)
                                              (+ ` (before changes)` on the old side)
```<lang>
<lines of the note's side, prefixes stripped; a mixed
 selection keeps only its +/space lines>
```
<note text>
````

Sanitizing, as the bundle does: quote lines that start like `In … at
line`, `Reply…:` or `<!-- attach` get a `> ` prefix; in the path, newlines
become spaces, backticks `'`, and an `@` that looks like a mention `＠`.
With an empty note text the block ends at the closing fence. Blocks are
joined by one blank line.

Own-session reply blocks, before the diff and file notes, two blank lines
apart (Claude's `withReplies` serializer, confirmed in ticket 008):

```
<!-- reply K -->                 (K = number of reply blocks, max 99;
> <quote line 1>                  later blocks use `<!-- reply -->`)
> <quote line 2>

<note text>                       (3+ newlines squeezed to 2; `<!-- reply`
                                   inside the text becomes `&lt;!-- reply`)
```

The quote is the note's Markdown via `agent-shell--buffer-markdown-substring`
(section 4.3), every line `> `-prefixed. No turn or prompt is named.

Quote from another session: a plain `> ` quote block, blank line, note
text. Dired: ``About `a.el`, `b.el`:`` then the note. Fallback:
``In buffer `*Help*` (help-mode) at lines S-E:``, fence, note. The request
goes last after two blank lines; with no notes, only the request is sent.

Worked example (one diff note, one own-session note, request):

````
<!-- reply 1 -->
> I removed the retry loop because it was never reached.

it is reached when the socket closes early; check `foo-connect`


In `src/foo.el` at lines 42-43:
```elisp
  (let ((cache (make-hash-table)))
    (puthash key value cache)
```
the cache is created on every call; hoist it


fix both, then run make check
````

### 8.2 `codex`

Sections in the app's order: `# Response annotations:` (own-session
notes), other-session quotes (plain `> ` quote + note, our placement),
`# Diff comments:` (diff, file, dired and fallback notes, one `## User
Comment N` each, numbered across the section), `## My request:`.

````
# Response annotations:
Each item contains text selected from an earlier Codex response and may include a user comment. Treat items as Annotation 1, Annotation 2, and so on in array order. Use every selection as context and address every comment. For every annotation you address, include its inline directive `:codex-annotation{index="N"}`, where N is its one-based array position (for example, `:codex-annotation{index="1"}`). Do not use unstructured annotation labels.
<response-annotations>
[{"text":"<quote>","annotation":"<note text>"}]
</response-annotations>

# Diff comments:

## User Comment 1
File: src/foo.el
Workspace: /abs/project            (only when the project differs)
Side: R                            (L for the old side; mixed is R)
Lines: 42-43                       (or 42)
Diff hunk:
```diff
@@ -40,6 +40,7 @@ (defun foo
 ...every hunk in :hunks, whole, in order...
```
Comment:
the cache is created on every call; hoist it

## User Comment 2
File: docs/plan.md
Lines: 10-12
```markdown
<quote>
```
Comment:
<note text>

## User Comment 3
Files: a.el, b.el                  (dired; fallback uses `Buffer: *Help* (help-mode)` and `Lines:`)
Comment:
<note text>

## My request:
<request>
````

The `source` field of a response annotation is dropped (its shape is
unknown). `annotation` is omitted when the note text is empty. The hunk text is the
note's `:hunks`, captured whole (4.2).

### 8.3 `omp`

Review order; each group of notes opens its own heading, numbers run
across the send.

Diff notes (`/annotate code-review` paste mode):

````
## Code Review Annotations

Use these annotations as review notes; they are not independently validated findings.
### src/foo.el — new 42-43              (old 42-43 for the old side)
Path: `src/foo.el`                      (absolute when the project differs)

Hunk: `@@ -40,6 +40,7 @@ (defun foo`     (one Hunk: line per touched hunk)

```diff
+  (let ((cache (make-hash-table)))
+    (puthash key value cache)
```
the cache is created on every call; hoist it
````

The `diff` fence holds the selected lines with their prefixes, every side.
The ranges (`new S-E`) are ours; omp labels single lines. `Occurrence:` is
dropped. Own-session notes: `# Feedback on your last reply` when the
note's `:turn` equals the target shell's turn count (`agent-shell--turns`)
at render, else `# Feedback on Assistant message <turn>`; then `## N. Feedback on:`, the quote inline in `"…"` unless it
holds a newline or backtick (then a `text` fence), then the note text. No
`## Source`. File notes: `# Feedback on <path>` with the same `## N.`
shape. Dired: `# Feedback on a.el, b.el`. Fallback: `# Feedback on *Help*`.
Other-session quotes: plain `> ` quote + note. The request follows the
notes after one blank line.

## 9. Jump (`RET` in the review)

Best effort, nothing stored beyond the markers:

1. The source buffer is live and the markers are valid: show it
   (`pop-to-buffer`), go to the marker, flash the range with
   `pulse-momentary-highlight-region`.
2. `magit` or `file` note with a dead buffer: `find-file` the file in the
   project (worktree version), go to `:start` (new side), flash the line
   range. Old-side and `committed` notes with a dead buffer: `user-error`.
3. `dired`: `dired` the directory, move to the first file.
4. `transcript` captured in a viewport whose viewport buffer is dead
   while its shell lives: reopen the shell's viewport, show the note's
   turn page, go to the quoted location and flash it.
5. `transcript` with a dead shell, or `buffer` with a dead buffer:
   `user-error "Source buffer is gone"`.

On a group heading, jump to the first note of the group. Flashing a moved
range flashes what is there now.

## 10. Commands and options (complete list)

Commands: `agent-shell-notes-capture`, `-review`, `-send-all`,
`-restore-last`, `-set-style`, `-set-after-send`, plus the review and popup
keys in 5.2, 5.3 and 4.4.

Functions: `agent-shell-notes-in-request-p`, the request-body test of the
review's key filter (5.2).

Options: `agent-shell-notes-markdown-mode`, `-sources`, `-style`, `-after-send`,
`-mark-indicator`, `-fence-languages`, `-capture-display-action`,
`-review-display-action`, `-client`,
`-agent-shell-disposition`.

Faces: `agent-shell-notes-location`, `-tag`, `-archived`, `-mark`, all
applied through overlays (5.1).

## 11. Tests and CI

Harness as agent-shell-side's `Makefile`: `make check` byte-compiles with
warnings as errors, then runs batch ERT under `emacs -Q` with
`load-prefer-newer`. Tests live under `tests/`; dependency directories are
Makefile variables listed once and shared by local runs and CI
(`AGENT_SHELL_DIR`, `ACP_DIR`, `SHELL_MAKER_DIR`, `MARKDOWN_MODE_DIR`,
`MAGIT_DIR` and Magit's dependencies).

- **agent-shell is real.** Tests load the fork and build transcript buffers
  with its real fragment rendering (`agent-shell--update-fragment` on a
  fake state). Only the process boundary is stubbed:
  `agent-shell--prompt-send`, `agent-shell--read-shell-buffer`,
  `agent-shell-buffers`. `agent-shell-viewport--show-buffer` runs for real
  (as the compose-buffer research did in batch, with only
  `--update-header` and `--position` stubbed), so the compose tests cover
  the `:disposition` read-back and the existing-draft append. No ACP
  process starts.
- **Magit is real.** Diff buffers come from `magit-diff-setup-buffer` on a
  temporary git repo. Cases: region inside a hunk, line at point, point on
  `@@`, region across hunks (one note, every hunk), across files
  (`user-error`), old-side and mixed selections, staged and unstaged tags,
  committed with `:rev`.
- **Rendering**: golden files `tests/golden/<style>-<case>.txt`, rendered
  from note data built in the test, not from buffers. Cases per style:
  diff, diff-old-side, diff-mixed, file, reply-own-session, reply-other-
  session, dired, fallback, request-only, mixed-batch, cross-project,
  numbering (two sends). Plus the `claude` sanitizing cases and the fence
  length rule.
- **Review**: drive the real commands, assert behavior (order, text
  properties, note list), not the display string: grouping and in-place
  insertion, quote folding, edit mode (only text editable, `C-c C-k`
  reverts, emptied text keeps the note), marks and `t` skipping archived,
  `x`, the three after-send modes for send and compose, `w` leaving
  everything, request clearing, restore-last for each mode, a failing
  `:send` changing nothing, `send-all` with no unarchived notes.
- **Popup**: capture, insert, save or abort; quote-only save, one popup at
  a time, window configuration restored. The evil tests (popup insert
  state; `i` and `j` in the request body under normal state) skip when
  evil is not on the load path.
- **Markdown parent**: the parent is fixed at load, so one run covers one
  parent. `make check` (and CI) runs the suite under the markdown-mode
  fallback; `make test-ts` runs it again on Emacs 31 with the grammar
  directory (`TREESIT_TS_DIR`) on `treesit-extra-load-path`, so the
  modes derive from markdown-ts-mode, and fails early when the grammars
  do not load. Parent-specific tests (outline cycling on headings) skip
  in the fallback run.
- **Live**: `make live-check`, by hand, outside `check` and CI. Starts a
  real claude-agent-acp session through agent-shell, sends a two-note
  review with `C-c C-c` and asserts the transcript's user prompt equals the
  rendered `claude` text; then `C-u C-c C-c` and asserts the compose buffer
  holds the text after an existing draft. No assertions on model output.
- **CI**: GitHub Actions, `make check` on push and pull request, matrix
  Emacs `29.1` and `snapshot` via `purcell/setup-emacs`. Shallow clones at
  head of: the agent-shell fork `main` (no pin: a rebase should show
  breakage), the acp fork, shell-maker, markdown-mode, Magit with
  `transient`, `with-editor`, `llama`, `compat`, `cond-let`. No JUnit report
  workflow.

## 12. Checks before coding

1. A viewport buffer carries `agent-shell-ui-state` and
   `agent-shell-markdown-source` text properties at runtime (read in
   source: `agent-shell--turns` copies with properties). Confirm with
   `get-text-property` in a live viewport.
2. `agent-shell-viewport--page-cursor` is set on the live mirror
   (`view-last`, `agent-shell-viewport.el:918`) and not only after
   `--show-page`. If nil there, the viewport's turn is the shell's latest.
3. The capture popup under evil: insert state on open, `C-c C-c` reachable
   from insert state.
4. `magit-diff-hunk-line` on a hunk in a `magit-status` buffer whose
   section is partially hidden.
5. `agent-shell--read-shell-buffer` with a pre-sorted `:buffers` list keeps
   the order in the completion UI (vertico, default completion).
6. `agent-shell--buffer-markdown-substring` on a region that starts inside
   a tool-call body and ends in the next message: headings for both.
7. Fork and sidechat shells appear in `agent-shell-buffers`.

## 13. Calls made in this document

Settled here, not in a ticket; low risk, cheap to change:

- Group order is by the capture time of the group's first note (Claude and
  Codex both group by first appearance).
- Cross-project paths are absolute in `claude` and `omp`.
- Fence language: extension table, then major mode name, then `text`.
- `omp` writes one `Hunk:` line per touched hunk.
- `codex` places file, dired and fallback notes under `# Diff comments:`
  with shared numbering; other-session quotes go between the response
  annotations and the diff comments.
- `omp` numbers run across the whole send, not per heading.
- The review and popup modes derive from markdown-ts-mode when it can
  run, else `markdown-mode` (§2); edit mode is a
  wdired-style minor mode using the `read-only` text property.
- The target picker has no project column; order carries the hint.
- Jump ladder (section 9).
- `TAB` folds quotes; `g` redraws; `q` quits; `C-c C-r` restores last.
- Default popup placement: bottom, height 0.3.
