# Issue tracker: Local Markdown under docs/

Issues, specs and wayfinder maps for this repo live as committed Markdown
files under `docs/`. The GitHub repo is public; nothing goes to GitHub Issues.

## Conventions

- One feature per directory: `docs/work/<feature-slug>/`.
- The spec is `docs/work/<feature-slug>/spec.md`.
- Issues are one file per ticket at
  `docs/work/<feature-slug>/issues/NNN-<slug>.md`, numbered from `001`, never a
  single combined tickets file.
- Every issue file starts with YAML frontmatter:

  ```yaml
  title: <name>
  status: open | closed
  labels: [<triage labels, see triage-labels.md>]
  assignee: <who claimed it, or empty>
  blocked-by: [<ids>]
  ```

- Refer to an issue by its title, linked to its file, not by a bare number.
- Comments and conversation history append to the bottom of the file under a
  `## Comments` heading.
- Commit tracker changes as they happen; concurrent sessions read the files.

## When a skill says "publish to the issue tracker"

Create a new file under `docs/work/<feature-slug>/` (creating the directory if
needed) and commit it.

## When a skill says "fetch the relevant ticket"

Read the file at the referenced path. The user will normally pass the path,
the title or the number directly.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a file with one **child** file per
ticket.

- **Map**: `docs/wayfinder/map.md` (Destination / Notes / Decisions so far /
  Not yet specified / Out of scope). A second effort gets its own directory,
  `docs/wayfinder/<effort>/`.
- **Child ticket**: `docs/wayfinder/tickets/NNN-<slug>.md`, numbered from
  `001`, with the question under `## Question`. Frontmatter:

  ```yaml
  title: <name>
  type: research | prototype | grilling | task   # the wayfinder:<type> label
  status: open | closed
  assignee: <who claimed it, or empty>
  blocked-by: [<ids>]
  ```

  Tickets carry no triage labels.
- **Blocking**: `blocked-by` lists ticket ids. A ticket is unblocked when every
  listed ticket is `closed`.
- **Frontier**: open, unblocked, unassigned tickets in
  `docs/wayfinder/tickets/`; lowest number first.
- **Claim**: set `assignee` and commit before any work.
- **Resolve**: append the answer under `## Resolution`, set `status: closed`,
  then append a context pointer (gist + link) to the map's Decisions so far.
- **Assets**: link them from the ticket. Research findings go in
  `docs/research/` on a local `research/<slug>` branch, not pushed; the ticket
  links the branch and file.
