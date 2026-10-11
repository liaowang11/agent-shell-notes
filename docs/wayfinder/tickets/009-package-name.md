---
title: What the package and its symbol prefix are called
type: grilling
status: closed
assignee: claude
blocked-by: []
---

## Question

The package is `agent-shell-annotations`, but the glossary avoids
"annotation" (a captured remark is a **Note**), and the send seam lets
clients other than agent-shell plug in. Every command, defcustom and
buffer name in the new `DESIGN.md` carries the prefix, so decide it before
the design is written: keep `agent-shell-annotations`, or rename (the
package, the repo, the prefix), and whether a short alias prefix is used
for commands.

## Resolution

Grilled with Bill, 2026-10-11.

- **Name: `agent-shell-notes`.** It stays in the `agent-shell-` family,
  like `agent-shell-side` and `agent-shell-vertico`; agent-shell is the only
  v1 client, and a client-neutral name is a fresh decision if a second one
  lands. "Notes" is the glossary term for what each capture makes;
  `annotations` contradicted the glossary and `review` reads as code
  review by the agent. No upstream agent-shell symbol uses the prefix.
- **Renamed:** the package (`agent-shell-notes.el`, feature
  `agent-shell-notes`), the symbol prefix, the public GitHub repo and its
  local clone. The repo and directory rename happens at the start of
  implementation, so this map's paths stay valid until `DESIGN.md` is
  written; GitHub redirects the old URL.
- **No short alias prefix.** Entry commands are
  `agent-shell-notes-capture`, `agent-shell-notes-review` (opens the
  review) and `agent-shell-notes-send`; their bindings belong to
  [Which entry commands and bindings ship, and what Doom
  adds](010-entry-bindings.md).
- **Prose follows the name** in living docs (the glossary heading, the map
  title, the new `DESIGN.md`); closed tickets and `docs/research/` keep
  "annotations" as history.

## Comments

- 2026-10-11: [Which entry commands and bindings ship, and what Doom
  adds](010-entry-bindings.md) makes the global entry points `-capture`,
  `-review` and `-send-all`; `-send` is the review's `C-c C-c` command.
