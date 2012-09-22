;;; current-project.el --- Support for projects in Emacs

;; Copyright (C) 2012 Victor Deryagin

;; Author: Victor Deryagin <vderyagin@gmail.com>
;; Created: 3 Aug 2012
;; Version: 0.0.1

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth
;; Floor, Boston, MA 02110-1301, USA.

;;; Commentary:

;;; Code:

(eval-when-compile
  (require 'cl))

(require 'find-cmd)

(require 'current-project-directory-predicates)
(require 'current-project-commands)

(defvar cpr-project nil
  "Current project.")
(make-variable-buffer-local 'cpr-project)

(defvar cpr-ignored-dirs
  '(".hg" ".git" ".bzr" ".svn" "_darcs" "_MTN" "CVS" "RCS" "SCCS" ".rbx")
  "List of names of directories, content of which will not be considered part of the project.")

(defvar cpr-ignored-files
  '("*.elc" "*.rbc" "*.py[co]" "*.a" "*.o" "*.so" "*.bin"
    "*.class" "*.s[ac]ssc" "*.sqlite3" "TAGS" ".gitkeep")
  "List of wildcards, matching names of files, which will not be considered part of the project.")

(defvar cpr-type-specs
  '((:type "Ruby on Ralis application"
     :test cpr-rails-app-p
     :ignored-dirs ("tmp"))
    (:type "Generic Git project"
     :test cpr-git-repo-p)
    (:type "Generic Mercurial project"
     :test cpr-mercurial-repo-p)
    (:type "Generic Darcs project"
     :test cpr-darcs-repo-p)
    (:type "Generic Subversion project"
     :test cpr-subversion-repo-p)
    (:type "Generic CVS project"
     :test cpr-cvs-repo-p))
  "A list of plists describing project types.")

(defvar cpr-history nil "List of visited projects.")

(defun cpr-project (&optional property)
  "When PROPERTY argument is provided - returns that property of
`cpr-project', otherwise returns full object."
  (if property
      (plist-get cpr-project property)
      cpr-project))

(defun cpr-project-valid-p ()
  "Check whether current project is valid."
  (let ((root (cpr-project :root))
        (name (cpr-project :name))
        (type (cpr-project :type)))
    (and
     (stringp root)
     (stringp name)
     (stringp type)
     (not (equal root ""))
     (not (equal name ""))
     (not (equal type ""))
     (file-directory-p root))))


(defun cpr-name-from-directory (dir)
  "Extract project name from its root directory path."
  (file-name-nondirectory
   (directory-file-name dir)))

(defun cpr-fetch (&optional force)
  "Populate `cpr-project'"
  (when force
    (setq cpr-project nil))                ; reset it first
  (unless (cpr-project-valid-p)
    (let ((current-dir (file-name-as-directory default-directory)))
      (flet ((reached-filesystem-root-p ()
               (equal current-dir "/"))

             (goto-parent-directory ()
               (setq current-dir
                     (file-name-as-directory
                      (expand-file-name ".." current-dir))))

             (identify-directory (dir)
               (loop
                  for spec in cpr-type-specs
                  for matches-p = (funcall (plist-get spec :test) dir)
                  for spec-type = (plist-get spec :type)
                  if matches-p return spec-type))

             (set-project-properties (&key root name type)
               (loop
                  for prop in '(root name type)
                  for key = (intern (concat ":" (symbol-name prop)))
                  for val = (symbol-value prop)
                  if val do
                    (setq cpr-project
                          (plist-put cpr-project key val)))))

        (loop
           (when (reached-filesystem-root-p)
             (error "Current buffer does not belong to any project"))
           (let ((type (identify-directory current-dir)))
             (when type
               (set-project-properties
                :root current-dir
                :type type
                :name (cpr-name-from-directory current-dir))
               (return)))
           (goto-parent-directory)))))
  (add-to-list 'cpr-history (cpr-project)))

(defun cpr-from-spec (param)
  (let ((spec
         (loop
            for spec in cpr-type-specs
            for spec-type = (plist-get spec :type)
            for found-spec-p = (equal spec-type (cpr-project :type))
            if found-spec-p return spec)))
    (plist-get spec param)))

(defun cpr-build-find-cmd ()
  "Construct find(1) command that returns all files, that belong to current project."
  (let ((ignored-dirs
         (append (cpr-from-spec :ignored-dirs)
                 cpr-ignored-dirs))
        (ignored-files
         (append (cpr-from-spec :ignored-files)
                 cpr-ignored-files)))
    (with-cpr-project
      (find-cmd
       `(prune (name ,@ignored-dirs))
       `(not (iname ,@ignored-files))
       '(type "f")
       '(print0)))))

(defun cpr-files ()
  "Get list of all files, that belong to current project."
  (delete ""
          (split-string
           (shell-command-to-string (cpr-build-find-cmd))
           "\0")))

(defun cpr-buffer-in-project-p (buffer-or-name)
  "Determines if BUFFER-OR-NAME is visiting a file which belongs to current project."
  (cpr-fetch)
  (let ((root (cpr-project :root))
        (buf (get-buffer buffer-or-name)))
    (with-current-buffer buf
      (and
       buffer-file-name
       (string-prefix-p root buffer-file-name)))))

(defun cpr-buffers ()
  "Returns list of buffers, visiting a files belonging to current project."
  (loop
     for buf in (buffer-list)
     if (cpr-buffer-in-project-p buf)
     collect buf))

(defun cpr-choose-project-from-history ()
  (loop
     with choices = (mapcar
                     (lambda (pr)
                       (let* ((cpr-project pr)
                              (root (cpr-project :root))
                              (name (cpr-name-from-directory root)))
                         (format "%-25s (%s)" name (abbreviate-file-name root))))
                     cpr-history)
     with choice = (ido-completing-read "Select project: " choices nil 'require-match)
     with root = (expand-file-name
                  (progn
                    (string-match "\(\\([/~].+\\)\)$" choice)
                    (match-string 1 choice)))
     for project in cpr-history
     if (equal root
               (let ((cpr-project project))
                 (cpr-project :root)))
     return project))

;;;###autoload
(defmacro with-cpr-project (&rest body)
  "Execute BODY with `default-directory' bound to current project's root."
  (declare (indent 0))
  `(progn
     (cpr-fetch)
     (let ((default-directory (cpr-project :root)))
       ,@body)))

(provide 'current-project)

;;; current-project.el ends here
