;;;; -*- Mode: LISP; Syntax: COMMON-LISP; indent-tabs-mode: nil; coding: utf-8; show-trailing-whitespace: t -*-
;;;; Copyright (C) 2011 Anton Vodonosov (avodonosov@yandex.ru)
;;;; See LICENSE for details.

(in-package #:test-grid-reporting)

(defun list-failures (lib-results)
  (mapcan #'failures lib-results))

(defun failures (lib-result)
  (nconc (testsuite-failures lib-result)
         (load-failures lib-result)))

(defun testsuite-failures (lib-result)
  (let* ((test-status (status lib-result))
         (test-fail-specs (etypecase test-status
                            (keyword (when (and (not (eq :ok test-status))
                                                (not (eq :no-resource test-status)))
                                       (list (list :whole-test-suite test-status))))
                            (list (let* ((failures (getf test-status :failed-tests))
                                         (unexpected-oks (set-difference (getf test-status :known-to-fail)
                                                                         failures
                                                                         :test #'string=)))
                                    (nconc (mapcar (lambda (failed-test-case) (list :test-case failed-test-case :fail))
                                                   failures)
                                           (mapcar (lambda (unexpected-ok-test) (list :test-case unexpected-ok-test :unexpected-ok))
                                                   unexpected-oks)))))))
    (mapcar (lambda (fail-spec)
              (make-instance 'failure :lib-result lib-result :fail-spec fail-spec))
            test-fail-specs)))

(defun load-failures (lib-result)
  (mapcar (lambda (load-result)
            (let ((fail-spec (list :load (system-name load-result) (load-status load-result))))
              (make-instance 'failure :lib-result lib-result :fail-spec fail-spec :load-result load-result)))
          (remove-if (lambda (load-status)
                       (or (eq :ok load-status) (eq :no-resource load-status)))
                     (load-results lib-result)
                     :key #'load-status)))

(defclass failure ()
  ((lib-result :type joined-lib-result :initarg :lib-result :reader lib-result)
   (load-result :type (or nul list) :initarg :load-result :initform nil :reader load-result)
   (fail-spec :type list :initarg :fail-spec :reader fail-spec)))

(defmethod lisp ((item failure))
  (lisp (lib-result item)))
(defmethod lib-world ((item failure))
  (lib-world (lib-result item)))
(defmethod libname ((item failure))
  (libname (lib-result item)))
(defmethod log-blob-key ((item failure))
  (if (load-result item)
      (log-blob-key (load-result item))
      (log-blob-key (lib-result item))))
(defmethod log-byte-length ((item failure))
  (if (load-result item)
      (log-byte-length (load-result item))
      (log-byte-length (lib-result item))))
(defmethod contact-email ((item failure))
  (contact-email (lib-result item)))


