EMACS ?= emacs

# load-prefer-newer everywhere: `make compile' leaves .elc files behind, and
# without it a later `make test' silently runs the stale compiled copy
# instead of the source being edited.
BATCH = $(EMACS) -Q --batch --eval '(setq load-prefer-newer t)'

# Dependency checkouts, one variable per repo root.  The defaults are Bill's
# forks and Doom's straight repos; CI points both roots at its shallow clones.
FORKS_DIR ?= $(HOME)/Repositories/forks
STRAIGHT_REPOS ?= $(HOME)/.config/emacs/.local/straight/repos
AGENT_SHELL_DIR ?= $(FORKS_DIR)/agent-shell
ACP_DIR ?= $(FORKS_DIR)/acp
SHELL_MAKER_DIR ?= $(FORKS_DIR)/shell-maker
MARKDOWN_MODE_DIR ?= $(STRAIGHT_REPOS)/markdown-mode
MAGIT_DIR ?= $(STRAIGHT_REPOS)/magit
TRANSIENT_DIR ?= $(STRAIGHT_REPOS)/transient
WITH_EDITOR_DIR ?= $(STRAIGHT_REPOS)/with-editor
LLAMA_DIR ?= $(STRAIGHT_REPOS)/llama
COMPAT_DIR ?= $(STRAIGHT_REPOS)/compat
COND_LET_DIR ?= $(STRAIGHT_REPOS)/cond-let

DEPS_LOAD_PATH = \
	-L $(AGENT_SHELL_DIR) -L $(ACP_DIR) -L $(SHELL_MAKER_DIR) \
	-L $(MARKDOWN_MODE_DIR) \
	-L $(MAGIT_DIR)/lisp -L $(TRANSIENT_DIR)/lisp -L $(WITH_EDITOR_DIR)/lisp \
	-L $(LLAMA_DIR) -L $(COMPAT_DIR) -L $(COND_LET_DIR)

.PHONY: compile test check live-check clean

compile:
	$(BATCH) -L . $(DEPS_LOAD_PATH) \
		--eval '(setq byte-compile-error-on-warn t)' \
		-f batch-byte-compile \
		agent-shell-notes.el

test:
	$(BATCH) -L . -L tests $(DEPS_LOAD_PATH) \
		-l tests/agent-shell-notes-tests.el \
		-f ert-run-tests-batch-and-exit

check: compile test

# Deliberately not part of `check': this starts a real agent, spends real
# API tokens, and waits on model output that is not deterministic.  Run it
# by hand before tagging a release.  It needs claude-agent-acp on PATH
# and a logged-in Claude account.
live-check:
	$(BATCH) -L . -L tests/live $(DEPS_LOAD_PATH) \
		-l agent-shell-notes-live \
		-f agent-shell-notes-live-batch

clean:
	rm -f *.elc tests/*.elc tests/live/*.elc
