# agent-shell notes

Collecting remarks on code, diffs and agent transcripts in Emacs, then handing
chosen ones to an agent-shell session as one prompt.

## Language

**Note**:
One captured remark: a quote of the source text, its location, and what Bill
wrote about it.
_Avoid_: Annotation, comment

**Capture**:
Making a note from a source: Bill selects text or puts point on a line, then
writes his remark.
_Avoid_: Annotate, add

**Source**:
Where a note was captured: a Magit diff, a file, a dired listing, an
agent-shell transcript, or any other buffer.
_Avoid_: Origin, buffer type

**Review**:
All the notes collected so far, from any source, not tied to any session.
_Avoid_: Batch, draft

**Send**:
Delivering the marked notes of the review to a target session as one prompt,
or placing that prompt in the session's compose buffer for a final edit.
_Avoid_: Submit, flush

**Archived note**:
A note kept after it was sent, marked with the target session it last went
to. The review hides it unless asked to show it.
_Avoid_: Sent note, done

**Mark**:
Selecting a note in the review for the next send or copy.
_Avoid_: Highlight (that is drawn on the source text), select

**Client**:
A chat front end that can receive sent notes, such as agent-shell.
_Avoid_: Backend, integration

**Target session**:
The session within a client that Bill picks when sending notes from the
review.
_Avoid_: Destination, shell

**Style**:
The wire format a send renders notes in, named after the agent app whose
format it copies (claude, codex, omp).
_Avoid_: Template, format

**Request**:
Free text Bill writes at the end of the review, sent after the notes.
_Avoid_: Prompt, message
