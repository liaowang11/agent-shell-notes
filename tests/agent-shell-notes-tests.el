;;; agent-shell-notes-tests.el --- Tests for agent-shell-notes -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: MIT
;; Copyright (C) 2026 Bill and contributors

;;; Commentary:

;; Batch ERT against the real agent-shell fork, Magit and markdown-mode.
;; Run with `make test'; the Makefile puts the dependencies on the load path.

;;; Code:

(require 'ert)
(require 'agent-shell-notes)

(ert-deftest agent-shell-notes-loads-with-real-agent-shell ()
  (should (featurep 'agent-shell-notes))
  (should (featurep 'agent-shell))
  (should (featurep 'markdown-mode))
  ;; The fragment renderer the transcript tests will build buffers with.
  (should (fboundp 'agent-shell--update-fragment))
  ;; Only Bill's fork defines it; upstream agent-shell would fail here.
  (should (fboundp 'agent-shell-fork)))

(ert-deftest agent-shell-notes-magit-is-on-the-load-path ()
  ;; Magit is a soft dependency of the package but a hard one of the tests:
  ;; diff buffers come from the real `magit-diff-setup-buffer'.
  (should (require 'magit nil t))
  (should (fboundp 'magit-diff-setup-buffer)))

(provide 'agent-shell-notes-tests)
;;; agent-shell-notes-tests.el ends here
