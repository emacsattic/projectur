;;; -*- lexical-binding: t -*-
;;; projectur.el --- Support for projects in Emacs

;; Copyright (C) 2012 Victor Deryagin

;; Author: Victor Deryagin <vderyagin@gmail.com>
;; Created: 3 Aug 2012
;; Version: 0.0.3

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

;;; Code:

(eval-when-compile
  (require 'cl))

(defvar projectur-project-types
  '(("Version-controlled ruby project"
     :test projectur-ruby-project-under-version-control-p
     :tags-command "exuberant-ctags -e **/*.rb"
     :ignored-dirs ("tmp" "pkg"))
    ("Generic version-controlled project"
     :test projectur-version-controlled-repo-p))
  "A list with projects types descriptions.")

(defvar projectur-ignored-dirs
  '(".hg" ".git" ".bzr" ".svn" ".rbx" "_darcs" "_MTN" "CVS" "RCS" "SCCS")
  "List of names of directories, content of which will not be
considered part of the project.")

(defvar projectur-ignored-files
  '("*.elc" "*.rbc" "*.py[co]" "*.a" "*.o" "*.so" "*.bin" "*.class"
    "*.s[ac]ssc" "*.sqlite3" "TAGS" ".gitkeep" "*~")
  "List of wildcards, matching names of files, which will not be
considered part of the project.")

(defvar projectur-history nil "List of visited projects.")

(defvar projectur-tags-command "exuberant-ctags -e --recurse ."
  "Shell command for generating TAGS file for project.
Executed in context of projects root directory.")

(defun projectur-history-cleanup ()
  (setq projectur-history
        (loop
           for project in projectur-history
           for root = (projectur-project-root project)
           if (and
               (projectur-project-valid-p project)
               (not (member root seen-roots)))
           collect project into projects and collect root into seen-roots
           finally return projects)))

(defun projectur-history-add (project)
  "Adds PROJECT to `projectur-history'."
  (add-to-list 'projectur-history project)
  (projectur-history-cleanup))


(defun projectur-project-valid-p (project)
  "Returns non-nil if PROJECT is valid, nil otherwise."
  (let ((root (car project))
        (test (plist-get (cdr project) :test)))
    (and
     (stringp root)
     (file-directory-p root)
     (if test
         (and (functionp test)
              (funcall test root))
         t))))

(defun projectur-current-project ()
  "Return project for the current buffer, or nil if current
buffer does not belong to any project"
  (let ((project (projectur-project-get)))
    (projectur-history-add project)
    project))

(defun projectur-project-get ()
  "Return current project or nil if current buffer does not belong to any."
  (loop
     with project
     with dir = default-directory
     until (string= dir "/")
     thereis project
     do
       (setq project (projectur-project-with-root dir)
             dir (expand-file-name ".." dir))))

(defun projectur-project-with-root (root)
  "Return project with root in ROOT, nil if ROOT is not a root of any project."
  (loop
     for project-type in projectur-project-types
     for test-function = (plist-get (cdr project-type) :test)
     if (funcall test-function root)
     return (cons (file-name-as-directory root)
                  (cdr project-type))))

(defun projectur-select-project-from-history ()
  "Select single project from `projectur-history'."
  (projectur-complete
   "Select project: " projectur-history
   (lambda (project)
     (let* ((root (abbreviate-file-name
                   (projectur-project-root project)))
            (name (projectur-project-name project)))
       (format "%-25s (%s)" name root)))))

(defun projectur-project-root (project)
  "Return root directory of PROJECT."
  (car project))

(defun projectur-project-tags-command (project)
  "Return TAGS generation comman for PROJECT."
  (or
   (plist-get (cdr project) :tags-command)
   projectur-tags-command))

(defun projectur-project-name (project)
  "Return name of PROJECT."
  (file-name-nondirectory
   (directory-file-name
    (projectur-project-root project))))

(defun projectur-project-ignored-dirs (project)
  "Return list of ignored directories for PROJECT."
  (append projectur-ignored-dirs
          (plist-get (cdr project) :ignored-dirs)))

(defun projectur-project-ignored-files (project)
  "Return list of wildcards of ignored files for PROJECT."
  (append projectur-ignored-files
          (plist-get (cdr project) :ignored-files)))

(defun projectur-find-cmd (project)
  "Find file in project."
  (let ((ignored-dirs (projectur-project-ignored-dirs project))
        (ignored-files (projectur-project-ignored-files project)))
    (projectur-with-project project
      (find-cmd
       `(prune (name ,@ignored-dirs))
       `(not (iname ,@ignored-files))
       '(type "f")
       '(print0)))))

(defun projectur-project-files (project)
  "List of absolute names for files, belonging to PROJECT."
  (let ((command (projectur-find-cmd project)))
    (delete ""
            (split-string
             (shell-command-to-string command)
             "\0"))))

(defun projectur-buffers (project)
  "Returns list of buffers, visiting files, belonging to current project."
  (loop
     for buf in (buffer-list)
     if (projectur-buffer-in-project-p buf project)
     collect buf))

(defun projectur-buffer-in-project-p (buffer-or-name project)
  "Returns non-nil if BUFFER-OR-NAME is visiting a file, belonging to current project"
  (let ((buf (get-buffer buffer-or-name))
        (root (projectur-project-root project)))
    (with-current-buffer buf
      (and
       buffer-file-name
       (string-prefix-p root buffer-file-name)))))

(defmacro projectur-with-project (project &rest body)
  "Execute BODY with `default-directory' bound to PROJECT root directory."
  (declare (indent 1))
  `(progn
     (unless (projectur-project-valid-p ,project)
       (error (format "Invalid project: %s" ,project)))
     (let ((default-directory (projectur-project-root ,project)))
       ,@body)))

;;;###autoload
(defmacro projectur-define-command (command-name docstring &rest body)
  "Define command COMMAND_NAME to be executed in"
  (declare (indent 1))
  `(defun ,command-name (&optional choose-project)
     ,(concat
       docstring
       "\nIf called with prefix argument or current buffer does"
       "\nnot belong to any project, ask to choose project from list"
       "\nand use it as context for executing BODY."
       "\n"
       "\nin BODY you can use variable `project' which refers to the"
       "\nproject in context of which command is being executed.")
     (interactive "P")
     (let* ((current-project (projectur-current-project))
            (project (if (and (not choose-project)
                              current-project)
                         current-project
                         (projectur-select-project-from-history))))
       (projectur-with-project project
         ,@body))))

;;;###autoload
(font-lock-add-keywords
 'emacs-lisp-mode
 '(("(\\(projectur-define-command\\) +\\([^ ]+\\)"
    (1 'font-lock-keyword-face)
    (2 'font-lock-function-name-face))))

(projectur-define-command projectur-goto-root
  "Open root directory of current project."
  (find-file default-directory))

(projectur-define-command projectur-find-file
  "Open file from current project."
  (let ((files (projectur-project-files project)))
    (find-file
     (projectur-complete
      "Find file in project: " files
      (lambda (file)
        (file-relative-name file
                            (projectur-project-root project)))))))

(projectur-define-command projectur-rgrep
  "Run `rgrep' command in context of the current project root directory."
  (call-interactively 'rgrep))

(projectur-define-command projectur-execute-shell-command
  "Execute shell command in context of the current project root directory."
  (call-interactively 'shell-command))

(projectur-define-command projectur-ack
  "Run `ack' command (if available) in context of the current project root directory."
  (if (fboundp 'ack)
      (call-interactively 'ack)
      (error "You need `ack' command installed in order to use this functionality")))

(projectur-define-command projectur-delete-from-history
  "Delete current project from `projectur-history'"
  (setq projectur-history
        (delete project projectur-history))
  (message "Project \"%s\" deleted from history."
           (abbreviate-file-name (projectur-project-root project))))

(projectur-define-command projectur-version-control
  "Open appropriate version control interface for current project."
  (cond
    ((and
      (projectur-git-repo-p default-directory)
      (fboundp 'magit-status))
     (magit-status default-directory))
    ((and
      (projectur-mercurial-repo-p default-directory)
      (fboundp 'ahg-status))
     (ahg-status default-directory))
    (t
     (vc-dir default-directory nil))))

(projectur-define-command projectur-generate-tags
  "Generate TAGS file for current project."
  (let ((command (projectur-project-tags-command project)))
    (shell-command
     (read-string "Generate TAGS like this: "
                  command nil command))
    (setq tags-file-name (expand-file-name "TAGS"))))

(projectur-define-command projectur-save
  "Save all opened buffers that belong to current project."
  (mapc
   (lambda (buf)
     (with-current-buffer buf
       (save-buffer)))
   (projectur-buffers project)))

(defun* projectur-complete (prompt choices &optional (display-fn 'identity))
  "Select one of CHOICES, with PROMPT, use DISPLAY-FN for display if provided,
`identity' otherwise."
  (let* ((results-map
          (mapcar (lambda (choice)
                    (cons (funcall display-fn choice) choice))
                  choices))
         (display-choices
          (mapcar 'car results-map))
         (chosen
          (ido-completing-read prompt display-choices)))
    (cdr (assoc chosen results-map))))

(defun projectur-show-current-file ()
  "If current buffer is visitin a file, show path of it relative
to its project root or absolute path if it does not belong to any
project."
  (interactive)
  (unless buffer-file-name
    (error "Current buffer does not belong to any project"))
  (let ((project (projectur-current-project)))
    (message
     "%s"
     (if project
         (file-relative-name buffer-file-name
                             (projectur-project-root project))
         (abbreviate-file-name buffer-file-name)))))

(defalias 'projectur-hg-repo-p 'projectur-mercurial-repo-p)
(defalias 'projectur-svn-repo-p 'projectur-subversion-repo-p)

(defun projectur-git-repo-p (dir)
  "Returns non-nil if DIR is a root of git repository, nil otherwise."
  (file-directory-p
   (expand-file-name ".git" dir)))

(defun projectur-mercurial-repo-p (dir)
  "Returns non-nil if DIR is a root of mercurial repository, nil otherwise."
  (file-directory-p
   (expand-file-name ".hg" dir)))

(defun projectur-subversion-repo-p (dir)
  "Returns non-nil if DIR is a root of subversion repository, nil otherwise."
  (and
   (file-directory-p (expand-file-name ".svn" dir))
   (not
    (file-directory-p (expand-file-name "../.svn" dir)))))

(defun projectur-cvs-repo-p (dir)
  "Returns non-nil if DIR is a root of CVS repository, nil otherwise."
  (and
   (file-directory-p (expand-file-name "CVS" dir))
   (not
    (file-directory-p (expand-file-name "../CVS" dir)))))

(defun projectur-darcs-repo-p (dir)
  "Returns non-nil if DIR is a root of Darcs repository, nil otherwise."
  (file-directory-p
   (expand-file-name "_darcs" dir)))

(defun projectur-ruby-gem-p (dir)
  "Returns non-nil if DIR is a root of ruby gem source tree, nil otherwise."
  (file-expand-wildcards
   (expand-file-name "*.gemspec" dir)))

(defun projectur-rails-app-p (dir)
  "Returns non-nil if DIR is a root of ruby-on-rails application, nil otherwise."
  (file-regular-p
   (expand-file-name "script/rails" dir)))

(defun projectur-rake-project-p (dir)
  "Returns non-nil if DIR is a root of project using rake, nil otherwise."
  (loop
     for rakefile in '("rakefile" "Rakefile" "rakefile.rb" "Rakefile.rb")
     thereis (file-regular-p (expand-file-name rakefile dir))))

(defun projectur-bundler-project-p (dir)
  "Returns non-nil if DIR is a root of project using bundler, nil otherwise."
  (file-regular-p
   (expand-file-name "Gemfile" dir)))

(defun projectur-version-controlled-repo-p (dir)
  "Returns non-nil if DIR is a root of version-controlled project, nil otherwise.
Supported version control systems: git, mercurial, subversion, cvs, darcs."
  (or
   (projectur-git-repo-p dir)
   (projectur-mercurial-repo-p dir)
   (projectur-subversion-repo-p dir)
   (projectur-cvs-repo-p dir)
   (projectur-darcs-repo-p dir)))

(defun projectur-ruby-project-under-version-control-p (dir)
  "Returns non-nil if DIR is a root of version-controlled ruby project."
  (and
   (projectur-version-controlled-repo-p dir)
   (or
    (projectur-rails-app-p dir)
    (projectur-ruby-gem-p dir)
    (projectur-bundler-project-p dir)
    (file-regular-p (expand-file-name "spec/spec_helper.rb" dir))
    (file-regular-p (expand-file-name "test/test_helper.rb" dir))
    (file-regular-p (expand-file-name "features/support/env.rb" dir))
    (file-regular-p (expand-file-name ".rspec" dir))
    (file-regular-p (expand-file-name ".rvmrc" dir))
    (file-regular-p (expand-file-name ".rbenv-version" dir)))))

(provide 'projectur)

;;; projectur.el ends here
