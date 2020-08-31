;;; xref-babylon.el --- Jump to references/definitions using ag & js2-mode's AST -*- lexical-binding: t; -*-

;; Copyright (C) 2016 Nicolas Petton

;; Author: Nicolas Petton <nicolas@petton.fr>
;; URL: https://github.com/NicolasPetton/xref-js2
;; Keywords: javascript, convenience, tools
;; Version: 1.0
;; Package: xref-js2
;; Package-Requires: ((emacs "25"))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; xref-babylon adds an xref backend for JavaScript files.
;;
;; Instead of using a tag system, it relies on `ag' to query the codebase of a
;; project.  This might sound crazy at first, but it turns out that `ag' is so
;; fast that jumping using xref-babylon is most of the time instantaneous, even on
;; fairly large JavaScript codebase (it successfully works with 50k lines of JS
;; code).

;;; Code:

(require 'subr-x)
(require 'xref)
(require 'seq)
(require 'map)
(require 'vc)

(defcustom xref-babylon-search-program 'ag
  "The backend program used for searching."
  :type 'symbol
  :group 'xref-babylon
  :options '(ag rg))

(defcustom xref-babylon-ag-arguments '("--js" "--noheading" "--nocolor")
  "Default arguments passed to ag."
  :type 'list
  :group 'xref-babylon)

(defcustom xref-babylon-js-extensions '("js" "mjs" "jsx" "ts" "tsx")
  "Extensions for file types xref-babylon is expected to search.
warning, this is currently only supported by ripgrep, not ag.

if an empty-list/nil no filtering based on file extension will
take place."
  :type 'list
  :group 'xref-babylon)

(defcustom xref-babylon-rg-arguments '("--no-heading"
                                   "--line-number"    ; not activated by default on comint
                                   "--pcre2"          ; provides regexp backtracking
                                   "--ignore-case"    ; ag is case insensitive by default
                                   "--color" "never")
  "Default arguments passed to ripgrep."
  :type 'list
  :group 'xref-babylon)

(defcustom xref-babylon-ignored-dirs '("bower_components"
                                   "node_modules"
                                   "build"
                                   "lib")
  "List of directories to be ignored when performing a search."
  :type 'list
  :group 'xref-babylon)

(defcustom xref-babylon-ignored-files '("*.min.js")
  "List of files to be ignored when performing a search."
  :type 'list
  :group 'xref-babylon)

(defcustom xref-babylon-definitions-regexps '("\\b%s\\b[\\s]*[:=][^=]"
                                          "function[\\s]+\\b%s\\b"
                                          "class[\\s]+\\b%s\\b"
                                          "(?<!new)[^.]%s[\\s]*\\(")
  "List of regular expressions that match definitions of a symbol.
In each regexp string, '%s' is expanded with the searched symbol."
  :type 'list
  :group 'xref-babylon)

(defcustom xref-babylon-references-regexps '("\\b%s\\b(?!\\s*[:=][^=])")
  "List of regular expressions that match references to a symbol.
In each regexp string, '%s' is expanded with the searched symbol."
  :type 'list
  :group 'xref-babylon)

;;;###autoload
(defun xref-babylon-xref-backend ()
  "Xref-Babylon backend for Xref."
  'xref-babylon)

(cl-defmethod xref-backend-identifier-at-point ((_backend (eql xref-babylon)))
  (symbol-name (symbol-at-point)))

(cl-defmethod xref-backend-definitions ((_backend (eql xref-babylon)) symbol)
  (xref-babylon--xref-find-definitions symbol))

(cl-defmethod xref-backend-references ((_backend (eql xref-babylon)) symbol)
  (xref-babylon--xref-find-references symbol))

(defun xref-babylon--xref-find-definitions (symbol)
  "Return a list of candidates matching SYMBOL."
  (seq-map (lambda (candidate)
             (xref-babylon--make-xref candidate))
           (xref-babylon--find-definitions symbol)))

(cl-defmethod xref-backend-identifier-completion-table ((_backend (eql xref-babylon)))
  "Return a list of terms for completions taken from the symbols in the current buffer.

The current implementation returns all the words in the buffer,
which is really sub optimal."
  (let (words)
    (save-excursion
      (save-restriction
        (widen)
        (goto-char (point-min))
        (while (re-search-forward "\\w+" nil t)
          (add-to-list 'words (match-string-no-properties 0)))
        (seq-uniq words)))))

(defun xref-babylon--xref-find-references (symbol)
  "Return a list of reference candidates matching SYMBOL."
  (seq-map (lambda (candidate)
             (xref-babylon--make-xref candidate))
           (xref-babylon--find-references symbol)))

(defun xref-babylon--make-xref (candidate)
  "Return a new Xref object built from CANDIDATE."
  (xref-make (map-elt candidate 'match)
             (xref-make-file-location (map-elt candidate 'file)
                                      (map-elt candidate 'line)
                                      0)))

(defun xref-babylon--find-definitions (symbol)
  "Return a list of definitions for SYMBOL from an ag search."
  (xref-babylon--find-candidates
   symbol
   (xref-babylon--make-regexp symbol xref-babylon-definitions-regexps)))

(defun xref-babylon--find-references (symbol)
  "Return a list of references for SYMBOL from an ag search."
  (xref-babylon--find-candidates
   symbol
   (xref-babylon--make-regexp symbol xref-babylon-references-regexps)))

(defun xref-babylon--make-regexp (symbol regexps)
  "Return a regular expression to search for SYMBOL using REGEXPS.

REGEXPS must be a list of regular expressions, which are
concatenated together into one regexp, expanding occurrences of
'%s' with SYMBOL."
  (mapconcat #'identity
             (mapcar (lambda (str)
                       (format str symbol))
                     regexps) "|"))

(defun xref-babylon--find-candidates (symbol regexp)
  (let ((default-directory (xref-babylon--root-dir))
        matches)
    (with-temp-buffer
      (let* ((search-tuple (cond ;; => (prog-name . function-to-get-args)
                            ((eq xref-babylon-search-program 'rg)
                             '("rg" . xref-babylon--search-rg-get-args))
                            (t ;; (eq xref-babylon-search-program 'ag)
                             '("ag" . xref-babylon--search-ag-get-args))))
             (search-program (car search-tuple))
             (search-args    (remove nil ;; rm in case no search args given
                                     (funcall (cdr search-tuple) regexp))))
        (apply #'process-file (executable-find search-program) nil t nil search-args))

      (goto-char (point-max)) ;; NOTE maybe redundant
      (while (re-search-backward "^\\(.+\\)$" nil t)
        (push (match-string-no-properties 1) matches)))
    (seq-map (lambda (match)
               (xref-babylon--candidate symbol match))
             matches)))

(defun xref-babylon--search-ag-get-args (regexp)
  "Aggregate command line arguments to search for REGEXP using ag."
  `(,@xref-babylon-ag-arguments
    ,@(seq-mapcat (lambda (dir)
                    (list "--ignore-dir" dir))
                  xref-babylon-ignored-dirs)
    ,@(seq-mapcat (lambda (file)
                    (list "--ignore" file))
                  xref-babylon-ignored-files)
    ,regexp))

(defun xref-babylon--search-rg-get-args (regexp)
  "Aggregate command line arguments to search for REGEXP using ripgrep."
  `(,@xref-babylon-rg-arguments
    ,@(if (not xref-babylon-js-extensions)
          nil ;; no filtering based on extension
        (seq-mapcat (lambda (ext)
                      (list "-g" (concat "*." ext)))
                    xref-babylon-js-extensions))
    ,@(seq-mapcat (lambda (dir)
                    (list "-g" (concat "!"                               ; exclude not include
                                       dir                               ; directory string
                                       (unless (string-suffix-p "/" dir) ; pattern for a directory
                                         "/"))))                         ; must end with a slash
                  xref-babylon-ignored-dirs)
    ,@(seq-mapcat (lambda (pattern)
                    (list "-g" (concat "!" pattern)))
                  xref-babylon-ignored-files)
    ,regexp))

(defun xref-babylon--root-dir ()
  "Return the root directory of the project."
  (or (ignore-errors
        (projectile-project-root))
      (ignore-errors
        (vc-root-dir))
      (user-error "You are not in a project")))

(defun xref-babylon--candidate (symbol match)
  "Return a candidate alist built from SYMBOL and a raw MATCH result.
The MATCH is one output result from the ag search."
  (let* ((attrs (split-string match ":" t))
         (match (string-trim (mapconcat #'identity (cddr attrs) ":"))))
    ;; Some minified JS files might match a search. To avoid cluttering the
    ;; search result, we trim the output.
    (when (> (seq-length match) 100)
      (setq match (concat (seq-take match 100) "...")))
    (list (cons 'file (expand-file-name (car attrs) (xref-babylon--root-dir)))
          (cons 'line (string-to-number (cadr attrs)))
          (cons 'symbol symbol)
          (cons 'match match))))

(provide 'xref-babylon)
;;; xref-babylon.el ends here
