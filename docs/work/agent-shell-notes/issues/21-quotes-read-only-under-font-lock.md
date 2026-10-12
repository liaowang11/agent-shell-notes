---
title: Quotes stay read-only under font-lock
status: closed
labels: [ready-for-agent]
assignee: claude
blocked-by: []
---

## What to build

In the review, with font-lock on, text can be typed into a `> ` transcript
quote next to a link or URL, in edit mode and outside it. Bill hit it in
edit mode. Reproduced in batch (2026-10-13) under both parents with default
settings: a quote holding `[l](http://x.y)`, a bare URL and `<http://a.b>`
takes insertions at 39 positions under markdown-mode and 21 under
markdown-ts-mode. Fenced quotes, headings and locations refuse every edit;
deletion is refused everywhere. Only note texts and the request body may
take edits. Follows [Typing survives markdown-mode
font-lock](20-typing-under-markdown-mode-font-lock.md), whose position probe
had no links in its quotes. Design: §5.1.

## Acceptance criteria

- [x] With font-lock on, no position outside the note texts and the request body takes an insertion or a deletion, links and URLs in a `> ` quote included.
- [x] Note texts (empty and non-empty) still take typing at both ends.
- [x] Text typed at the start of a note text carries no `front-sticky`.
- [x] The test fails on the current code under both parents (`make test`, `make test-ts`).

## Comments

2026-10-13 (claude): root cause. When something is inserted, Emacs checks
only the `front-sticky` of the character after and the `rear-nonsticky`
of the character before (`verify_interval_modification`). The review
relied on the second check alone, and font-lock breaks it in a `> `
quote: markdown-mode puts `rear-nonsticky t` on link markup
(`markdown--markup-props`) and URLs (`markdown-fontify-plain-uris`);
markdown-ts-mode gives link buttons `category default-button`, which
carries `rear-nonsticky t` and is read before the alias. Fenced quotes
are safe because neither mode looks for links in code blocks. Doom's
markdown settings make no difference.

Fix: `agent-shell-notes--review-draw` makes every read-only character
`front-sticky (read-only)`, and so does the `# Request` heading. Edit
mode removes `front-sticky` from each note text and from the newline that
ends it, so a text takes typing at both ends and typed text carries no
`front-sticky`. Neither font-lock manages `front-sticky`. DESIGN §5.1
records the rule.

Verified: the new test checks every position outside the texts and the
request after real font-lock (insertion and one-character deletion), both
ends of an empty and a non-empty text, and that text typed at a text's
start carries no `front-sticky`. It failed on the old code under both
parents (position 177 under `make test`, 178 under `make test-ts`), and
the `front-sticky` check failed until the texts lost the property.
`make compile`, `make test` (172 tests, 5 skipped) and `make test-ts` (2
skipped) pass.

Unverified: live Emacs with evil and jit-lock (batch only).
