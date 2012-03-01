;;; -*- Mode: LISP; Syntax: COMMON-LISP; Package: test-grid; Base: 10; indent-tabs-mode: nil; coding: utf-8; show-trailing-whitespace: t -*-

(defpackage #:test-grid (:use :cl))

(in-package #:test-grid)

(defgeneric libtest (library-name)
  (:documentation "Define a method for this function
with LIBRARY-NAME eql-specialized for for every library added
to the test grid.

The method should run test suite and return the resulting
status. Status is one of these values:
  :OK - all tests passed,
  :FAIL - some test failed,
  :NO-RESOURCE - test suite can not be run because some required
     resource is absent in the environment. For example, CFFI library
     test suite needs a small C library compiled to DLL. User must
     do it manually. In case the DLL is absent, the LIBTEST method
     for CFFI returns :NO-RESOURCE.
  Extended status in the form
     (:FAILED-TESTS <list of failed tests> :KNOWN-TO-FAIL <list of known failures>)
     The test names in these lists are represented as downcased strings.

If any SERIOUS-CONDITION is signalled, this is considered a failure.

For convenience, T may be returned instead of :OK and NIL instead of :FAIL."))

(defun normalize-status (status)
  "Normilzies test resul status - converts T to :OK and NIL to :FAIL."
  (case status
    ((t :ok) :ok)
    ((nil :fail) :fail)
    (otherwise status)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; My Require
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun require-impl (api)
  "Loads an implementation of the specified API (if
it is not loaded yet).

Some of test-grid components have separate package
and ASDF system for API and separate package+ASDF
system for the implementation. This allows test-grid
to be compilable and (partially) opereable even
when some components are broken on particular lisp.

For these known test-grid componetns REQUIRE-IMPL loads
the implementation. Otherwise the API parameter is
just passed to the QUICKLISP:QUICKLOAD."
  (setf api (string-downcase api))
  (let* ((known-impls '(("rt-api" . "rt-api-impl")))
         (impl-asdf-system (or (cdr (assoc api known-impls :test #'string=))
                               api)))
        (quicklisp:quickload impl-asdf-system)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; LIBTEST implementations for particular libraries
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defparameter *all-libs* '(:alexandria :babel :trivial-features :cffi
                           :cl-ppcre :usocket :flexi-streams :bordeaux-threads
                           :cl-base64 :trivial-backtrace :puri :anaphora
                           :parenscript :trivial-garbage :iterate :metabang-bind
                           :cl-json :cl-containers :metatilities-base :cl-cont
                           :moptilities :trivial-timeout :metatilities)
  "All the libraries currently supported by the test-grid.")


(defun run-rt-test-suite()
  (require-impl "rt-api")

  (let (non-compiled-failures all-failures)

    (rt-api:do-tests :compiled-p nil)
    (setf non-compiled-failures (rt-api:failed-tests))

    (rt-api:do-tests :compiled-p t)
    (setf all-failures (union non-compiled-failures
                              (rt-api:failed-tests)))

    (list :failed-tests (mapcar #'string-downcase all-failures)
          :known-to-fail (mapcar #'string-downcase (rt-api:known-to-fail)))))

(defmethod libtest ((library-name (eql :alexandria)))

; We keep the below hardcoded failure in case we want to test
; the ECL 11.1.1 release (until new release is out).
; It is commented out or uncommented depending on what
; ECL release we are going to test.

  ;; #+ecl
  ;; (progn
  ;;   (format t "ECL 11.1.1 has bug causing a stack overflow on alexandria tests. http://sourceforge.net/tracker/?func=detail&aid=3463131&group_id=30035&atid=398053~%")
  ;;   (return-from libtest :fail))

  ;; The test framework used: rt.
  (require-impl "rt-api")
  (rt-api:clean)
  (asdf:clear-system :alexandria-tests)
  (quicklisp:quickload :alexandria-tests)

  (run-rt-test-suite))

(defmethod libtest ((library-name (eql :babel)))

  ;; The test framework used: stefil.

  (quicklisp:quickload :babel-tests)

  (let* ((*debug-io* *standard-output*)
         (result (funcall (intern (string '#:run) '#:babel-tests)))
         (failures (funcall (intern (string '#:failure-descriptions-of) '#:hu.dwim.stefil)
                            result))
         (failed-p (> (length failures) 0)))

    (when failed-p
      (format t "~&~%-------------------------------------------------------------------------------------------------~%")
      (format t "The test result details (printed by cl-test-grid in addition to the standard Stefil output above)~%")
      (format t "~%(DESCRIBE RESULT):~%")
      (describe result)
      (format t "~&~%Individual failures:~%")
      (map 'nil
           (lambda (descr) (format t "~A~%" descr))
           failures))
    (not failed-p)))

(defmethod libtest ((library-name (eql :trivial-features)))

  ;; The test framework used: rt.
  (require-impl "rt-api")
  (rt-api:clean)
  (asdf:clear-system :trivial-features-tests)

  ;; Load cffi-grovel which is used in trivial-features-tests.asd,
  ;; but not in the asdf:defsystem macro (issue #2).
  (quicklisp:quickload :cffi-grovel)
  (quicklisp:quickload :trivial-features-tests)

  (run-rt-test-suite))

(defmethod libtest ((library-name (eql :cffi)))

  ;; The test framework used: rt.
  (require-impl "rt-api")
  (rt-api:clean)
  (asdf:clear-system :cffi-tests)

  ;; CFFI tests work with a small test C library.
  ;; The user is expected to compile the library manually.
  ;; If the library is not available, CFFI tests
  ;; signal cffi:load-foreign-library-error.
  (handler-bind ((error #'(lambda (condition)
                            ;; Check if the error is a
                            ;; cffi:load-foreign-library-error.
                            ;; Take into account that it might
                            ;; be some other error which prevents
                            ;; even CFFI system to load,
                            ;; and therefore CFFI package may be
                            ;; abset. That's why use use ignore-errors
                            ;; when looking for a symbol in the CFFI
                            ;; packge.
                            (when (eq (type-of condition)
                                      (ignore-errors (find-symbol (symbol-name '#:load-foreign-library-error)
                                                                  '#:cffi)))
                              ;; todo: add the full path to the 'test' directory,
                              ;; where user can find the scripts to compile
                              ;; the test C library, to the error message.
                              (format t
                                      "~& An error occurred during (quicklisp:quickload :cffi-tests):~%~A~&This means the small C library used by CFFI tests is not available (probably you haven't compiled it). The compilation script for the library may be found in the 'test' directory in the CFFI distribution.~%"
                                      condition)
                              (return-from libtest :no-resource))
                            ;; resignal the condition
                            (error condition))))
    (quicklisp:quickload :cffi-tests))
  (run-rt-test-suite))

(defmethod libtest ((library-name (eql :cl-ppcre)))

  #+abcl
  (progn
    (format t "~&Due to ABCL bug #188 (http://trac.common-lisp.net/armedbear/ticket/188)~%")
    (format t "cl-ppcre tests fail, repeating this error huge number of times, in result~%")
    (format t "hanging for a long time and producing a huge log.")
    (return-from libtest :fail))

  ;; The test framework used: custom.

  ;; Workaround the quicklisp issue #225 -
  ;; https://github.com/quicklisp/quicklisp-projects/issues/225 -
  ;; first load cl-ppcre-unicode, because otherwise
  ;; current quicklisp can not find cl-ppcre-unicode-test
  (quicklisp:quickload :cl-ppcre-unicode)
  (quicklisp:quickload :cl-ppcre-unicode-test)

  ;; copy/paste from cl-ppcre-unicode.asd
  (funcall (intern (symbol-name :run-all-tests) (find-package :cl-ppcre-test))
           :more-tests (intern (symbol-name :unicode-test) (find-package :cl-ppcre-test))))

(defmethod libtest ((library-name (eql :usocket)))

  #+abcl
  (progn
    (format t "~&On ABCL abcl-1.0.0 the usocket test suite hangs (after producing significant~%")
    (format t "number of errors/failures in the log). The last log message before it hangs is:~%")
    (format t "USOCKET-TEST::WAIT-FOR-INPUT.3")
    (return-from libtest :fail))

  ;; The test framework used: rt.
  (require-impl "rt-api")
  (rt-api:clean)
  (asdf:clear-system :usocket-test)

;  (asdf:operate 'asdf:load-op :usocket-test :force t)

  (quicklisp:quickload :usocket-test)

  ;; TODO: usocket test suite might need manual configuration,
  ;;       see their README. Distinguish the case
  ;;       when the manual configuration hasn't been
  ;;       performed and return :no-resource status.
  ;;
  ;; (setf usocket-test::*common-lisp-net*
  ;;       (or usocket-test::*common-lisp-net*
  ;;           "74.115.254.14"))

  (run-rt-test-suite))


(defmethod libtest ((library-name (eql :flexi-streams)))

  ;; The test framework used: custom.

  (quicklisp:quickload :flexi-streams-test)

  ;; copy/paste from flexi-streams.asd
  (funcall (intern (symbol-name :run-all-tests)
                   (find-package :flexi-streams-test))))

(defun run-fiveam-suite (fiveam-test-spec)
  "Runs the specified test suite created with the FiveAM
test framework. Returns T if all the tests succeeded and
NIL otherwise. The FIVEAM-TEST-SPEC specifies the tests
suite according to the FiveAM convention."
  (let ((run (intern (string '#:run) :fiveam))
        (explain (intern (string '#:explain) :fiveam))
        (detailed-text-explainer (intern (string '#:detailed-text-explainer) :fiveam))
        (test-failure-type (intern (string '#:test-failure) :fiveam)))

    (let ((results (funcall run fiveam-test-spec)))
      (funcall explain (make-instance detailed-text-explainer) results *standard-output*)
      (zerop (count-if (lambda (res)
                         (typep res test-failure-type))
                       results)))))

(defmethod libtest ((library-name (eql :bordeaux-threads)))

  #+cmucl
  (progn
    (format t "~&On CMUCL bordeaux-threads test suite traps into some active~%")
    (format t "deadlock, produces 8 MB of '.' symbols in log, constantly runs GC~%")
    (format t "and finally dies when heap is exhausted.~%")
    (return-from libtest :fail))

  ;; The test framework used: fiveam.

  (quicklisp:quickload :bordeaux-threads-test)

  (run-fiveam-suite :bordeaux-threads))

(defmethod libtest ((library-name (eql :cl-base64)))

  ;; The test framework used: ptester.

  ;; Load cl-base64 first, because cl-base64-tests
  ;; is defined in cl-base64.asd which confuses
  ;; quicklisp (some versions of, see issue #1)
  (quicklisp:quickload :cl-base64)

  (quicklisp:quickload :cl-base64-tests)

  (funcall (intern (symbol-name '#:do-tests)
                   (find-package '#:cl-base64-tests))))

(defun lift-tests-ok-p (lift-tests-result)
  "Helper function to work with Lift test framework.
Examines the tests result object and retuns T is all
the tests are successull and NIL otherwise."
  (let ((errors (intern (symbol-name '#:errors) :lift))
        (expected-errors (intern (symbol-name '#:expected-errors) :lift))
        (failures (intern (symbol-name '#:failures) :lift))
        (expected-failures (intern (symbol-name '#:expected-failures) :lift)))
    (zerop
     (+ (length (set-difference (funcall errors lift-tests-result)
                                (funcall expected-errors lift-tests-result)))
        (length (set-difference (funcall failures lift-tests-result)
                                (funcall expected-failures lift-tests-result)))))))

(defun run-lift-tests (suite-name)
  "Helper function to work with the Lift test framework.
Runs the specified Lift test suite and returns T
if all the tests succeeded and NIL othersize."
  (let ((run (intern (symbol-name '#:run-tests) :lift))
        (lift-debug-output (intern (string :*lift-debug-output*) :lift)))
    ;; bind lift:*debug-output* to *standard-output*,
    ;; wich is then redirected to file by run-libtests.
    (progv (list lift-debug-output) (list *standard-output*)
      (let ((result (funcall run :suite suite-name)))
        (describe result *standard-output*)
        (lift-tests-ok-p result)))))

(defmethod libtest ((library-name (eql :trivial-backtrace)))

  ;; The test framework used: lift.

  (quicklisp:quickload :trivial-backtrace-test)

  (run-lift-tests :trivial-backtrace-test))

(defmethod libtest ((library-name (eql :puri)))

  ;; The test framework used: ptester.

  ;; Load puri first, because puri-tests
  ;; is defined in puri.asd which confuses
  ;; quicklisp (some versions of, see issue #1)
  (quicklisp:quickload :puri)

  (quicklisp:quickload :puri-tests)

  ;; copy/paste from puri.asd
  (funcall (intern (symbol-name '#:do-tests)
                   (find-package :puri-tests))))

(defmethod libtest ((library-name (eql :anaphora)))

  ;; The test framework used: rt.
  (require-impl "rt-api")
  (rt-api:clean)
  (asdf:clear-system :anaphora-test)
  ;; anaphora-test is defined in anaphora.asd,
  ;; therefore to reload :anaphora-test
  ;; we need to clean the :anaphora system too
  (asdf:clear-system :anaphora)

  ;; Load anaphora first, because anaphora-tests
  ;; is defined in anaphora.asd which confuses
  ;; quicklisp (some versions of, see issue #1)
  (quicklisp:quickload :anaphora)
  (quicklisp:quickload :anaphora-test)

  (run-rt-test-suite))

(defmethod libtest ((library-name (eql :parenscript)))
  ;; The test framework used: eos (similar to FiveAM).

  (quicklisp:quickload :parenscript.test)

  ;; asdf:test-op is not provided for parenscript,
  ;; only a separate package ps-test with public
  ;; function run-tests.

  ;; The test suites to run determined by looking
  ;; into the function run-tests in the file test.lisp.
  (let* ((run (intern (string '#:run) :eos))
         (test-failure-type (intern (string '#:test-failure) :eos))
         (results (append (funcall run (intern (string '#:output-tests) :ps-test))
                          (funcall run (intern (string '#:package-system-tests) :ps-test)))))
    (zerop (count-if (lambda (res)
                       (typep res test-failure-type))
                     results))))

(defmethod libtest ((library-name (eql :trivial-garbage)))

  ;; The test framework used: rt.
  (require-impl "rt-api")
  (rt-api:clean)
  (asdf:clear-system :trivial-garbage)  ; yes, trivial-garbage but not trivial-garbage-tests,
                                        ; because the trivial-garbage-tests system is defined
                                        ; in the same trivial-garbage.asd and neither
                                        ; asdf nor quicklisp can't find trivial-garbage-tests.

  (quicklisp:quickload :trivial-garbage); trivial-garbage but not trivial-garbage-tests,
                                        ; for the same reasons as explained above.
  (asdf:operate 'asdf:load-op :trivial-garbage-tests)

  (run-rt-test-suite))

(defmethod libtest ((library-name (eql :iterate)))

  ;; The test framework used: rt.
  (require-impl "rt-api")
  (rt-api:clean)
  (asdf:clear-system :iterate-tests)
  (asdf:clear-system :iterate)

  ;; Load iterate first, because iterate-tests
  ;; is defined in iterate.asd which confuses
  ;; quicklisp (some versions of, see issue #1)
  (quicklisp:quickload :iterate)
  (quicklisp:quickload :iterate-tests)

  (run-rt-test-suite))

(defmethod libtest ((library-name (eql :metabang-bind)))

  ;; The test framework used: lift.

  ;; metabang-bind-test includes binding syntax
  ;; for regular-expression and corresponding
  ;; tests; but this functionality is only
  ;; loaded if cl-ppcre is loaded first.
  ;; (this conditional loading is achieaved
  ;; with asdf-system-connections).
  (quicklisp:quickload :cl-ppcre)
  (quicklisp:quickload :metabang-bind-test)

  (run-lift-tests :metabang-bind-test))

(defmethod libtest ((library-name (eql :cl-json)))
  ;; The test framework used: fiveam.
  (let ((*trace-output* *standard-output*))

    ;; Load cl-json first, because cl-json.tests
    ;; is defined in cl-json.asd which confuses
    ;; quicklisp (some versions of, see issue #1)
    (quicklisp:quickload :cl-json)

    (quicklisp:quickload :cl-json.test)
    (run-fiveam-suite (intern (symbol-name '#:json) :json-test))))

(defmethod libtest ((library-name (eql :cl-containers)))
  ;; The test framework used: lift.
  (quicklisp:quickload :cl-containers-test)
  (run-lift-tests :cl-containers-test))

(defmethod libtest ((library-name (eql :metatilities-base)))
  ;; The test framework used: lift.
  (quicklisp:quickload :metatilities-base-test)
  (run-lift-tests :metatilities-base-test))

(defmethod libtest ((library-name (eql :cl-cont)))
  ;; The test framework used: rt.
  (require-impl "rt-api")
  (rt-api:clean)
  (asdf:clear-system :cl-cont-test)
  (quicklisp:quickload :cl-cont-test)
  (run-rt-test-suite))

(defmethod libtest ((library-name (eql :moptilities)))
  ;; The test framework used: lift.
  (quicklisp:quickload :moptilities-test)
  (run-lift-tests :moptilities-test))

(defmethod libtest ((library-name (eql :trivial-timeout)))
  ;; The test framework used: lift.
  (quicklisp:quickload :trivial-timeout-test)
  (run-lift-tests :trivial-timeout-test))

(defmethod libtest ((library-name (eql :metatilities)))
  ;; The test framework used: lift.
  (quicklisp:quickload :metatilities-test)
  (run-lift-tests :metatilities-test))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Utils
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun set= (set-a set-b &key (test #'eql) key)
  (null (set-exclusive-or set-a set-b :test test :key key)))

(defun do-plist-impl (plist handler)
  (do* ((cur-pos plist (cddr cur-pos))
        (prop (first cur-pos) (first cur-pos))
        (val (second cur-pos) (second cur-pos)))
       ((null prop))
    (funcall handler prop val)))

(defmacro do-plist ((key val plist &optional result) &body body)
  `(block nil
     (do-plist-impl ,plist (lambda (,key ,val) ,@body))
     ,result))

(defun plist-comparator (&rest props-and-preds)
  (lambda (plist-a plist-b)
    (do-plist (prop pred props-and-preds)
      ;; iterate over all the property/predicate pairs
      ;; "compare" the values of the current property
      ;; in both plists
      (let ((val-a (getf plist-a prop))
            (val-b (getf plist-b prop)))
        (if (funcall pred val-a val-b)
            (return t))
        ;; Ok, val-a is not less than val-b (as defined by our predicate).
        ;; Lets check if they are equal. If the reverse comparation [val-b less val-a]
        ;; is also false, then they are equal, and we proceed to the next
        ;; property/predicate pair.
        (when (funcall pred val-b val-a)
          (return nil))))))

;; examples:
#|
 (let ((less (plist-comparator :a '< :b 'string<)))
   (and (funcall less '(:a 1 :b "x") '(:a 2 :b "y"))
        (funcall less '(:a 2 :b "x") '(:a 2 :b "y"))
        (not (funcall less '(:a 3 :b "x") '(:a 2 :b "y")))))

 (equalp
  (sort '((:a 1 :b "x")
          (:a 2 :b "y")
          (:a 2 :b "y")
          (:a 3 :b "z"))
        (plist-comparator :a '< :b 'string<))
  '((:A 1 :B "x") (:A 2 :B "y") (:A 2 :B "y") (:A 3 :B "z")))
|#

(defun getter (prop)
  #'(lambda (plist)
      (getf plist prop)))

(defun list< (predicates l1 l2)
  "Compares two lists L1 and L2 of equal lenght,
using for every pair of elements a corresponding predicate
from the PREDICATES list (of the same length). Returns
T if L1 is less than (according the PREDICATES) L2.
Othersise returns NIL."
  (if (null predicates)
      nil
      (let ((pred (car predicates))
            (elem1 (car l1))
            (elem2 (car l2)))
        (if (funcall pred elem1 elem2)
            t
            ;; Ok, elem1 is not less than elem2 (as defined by our predicate).
            ;; Lets check if they are equal. If the reverse comparation [elem2 less elem1]
            ;; is also false, then they are equal, and we proceed to the next
            ;; property/predicate pair.
            (if (funcall pred elem2 elem1)
                nil
                (list< (cdr predicates)
                       (cdr l1)
                       (cdr l2)))))))

#|
Examples:

 (and
  (list< '(< <) '(1 2) '(2 2))
  (not (list< '(< <) '(1 2) '(1 2)))
  (list< '(< <) '(1 2) '(1 3))
  (not (list< '(string< string<)
              '("quicklisp-fake-2011-00-02" "ccl-fake-1")
              '("quicklisp-fake-2011-00-01" "clisp-fake-1"))))
|#

(defun hash-table-keys (hash-table)
  (let (keys)
    (maphash #'(lambda (key val)
                 (declare (ignore val))
                 (push key keys))
             hash-table)
    keys))

;; copy/paste from
;; http://www.gigamonkeys.com/book/practical-an-mp3-browser.html
(defmacro with-safe-io-syntax (&body body)
  `(with-standard-io-syntax
     (let ((*read-eval* nil))
       ,@body)))

(defun safe-read (&rest args)
  (with-safe-io-syntax (apply #'read args)))

(defun safe-read-file (file)
  (with-open-file (in file
                      :direction :input
                      :element-type 'character ;'(unsigned-byte 8) + flexi-stream
                      )
    (safe-read in)))

(defun write-to-file (obj file)
  "Write to file the lisp object OBJ in a format acceptable to READ."
  (with-open-file (out file
                       :direction :output
                       :if-exists :supersede
                       :if-does-not-exist :create)
    (pprint obj out))
  obj)

;; based on
;; http://cl-user.net/asp/-1MB/sdataQ0mpnsnLt7msDQ3YNypX8yBX8yBXnMq=/sdataQu3F$sSHnB==
;; but fixed in respect to file-length returing file length in bytes
;; instead of characters (and violating the spec therefore) at least
;; on CLISP 2.49 and ABCL 1.0.0.
(defun file-string (path)
  "Sucks up an entire file from PATH into a freshly-allocated string,
      returning two values: the string and the number of bytes read."
  (with-open-file (s path)
    (let* ((len (file-length s))
           (data (make-string len))
           (char-len (read-sequence data s)))
      (if (> len char-len)
          (setf data (subseq data 0 char-len)))
      data)))

(defun file-byte-length (path)
  (with-open-file (s path
                     :direction :input
                     :element-type '(unsigned-byte 8))
    (file-length s)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Settings
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defparameter +settings-file-name+ "cl-test-grid-settings.lisp")

(defun get-settings-file()
  (merge-pathnames (user-homedir-pathname) +settings-file-name+))

(defun prompt-for-email ()
  (format *query-io* "~&~%")
  (format *query-io* "Please enter your email so that we know who is submitting the test results.~%")
  (format *query-io* "Also the email will be published in the online reports, and the library~%")
  (format *query-io* "authors can later contact you in case of questions about this test run, ~%")
  (format *query-io* "your environment, etc.~%~%")

  (format *query-io* "If you are strongly opposed to publishing you email, please type e.g. some nickname or just \"none\".~%~%")

  (format *query-io* "The value you enter will be saved and reused in the future. You can change~%")
  (format *query-io* "it in the file ~A in your home directory.~%~%" +settings-file-name+)

  (format *query-io* "email: ")

  (force-output *query-io*)
  (string-trim " " (read-line *query-io*)))

(defun get-user-email ()
  (let ((user-email nil))
    (handler-case
        (progn
          (setf user-email (getf (safe-read-file (get-settings-file))
                                 :user-email))
          (if (zerop (length user-email))
              (warn "Empty email is specified in the settings file ~a~%" (get-settings-file))))
      (file-error ()
        (progn
          (setf user-email (prompt-for-email))
          (write-to-file (list :user-email user-email)
                         (get-settings-file)))))
    user-email))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Test Runs
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun run-descr (run)
  "The description part of the test run."
  (getf run :descr))

(defun run-results (run)
  "The list of test suite statuses for every library in the specified test run."
  (getf run :results))

(defun (setf run-results) (new-run-results test-run)
  (setf (getf test-run :results) new-run-results))

(defun make-run (description lib-results)
  (list :descr description :results lib-results))

(defun fmt-time (universal-time &optional destination)
  "The preferred time format used in the cl-test-grid project."
  (multiple-value-bind (sec min hour date month year)
      (decode-universal-time universal-time 0)
    (funcall #'format
             destination
             "~2,'0D~2,'0D~2,'0D~2,'0D~2,'0D~2,'0D"
             year month date hour min sec)))

(defun pretty-fmt-time (universal-time &optional destination)
  "The human-readable time format, used in reports."
  (multiple-value-bind (sec min hour date month year)
      (decode-universal-time universal-time 0)
    (funcall #'format
             destination
             "~2,'0D-~2,'0D-~2,'0D ~2,'0D:~2,'0D:~2,'0D"
             year month date hour min sec)))

(defun make-run-descr ()
  "Generate a description for a test run which might be
performed in the current lisp system."
  (list :lisp (asdf::implementation-identifier)
        :lib-world (format nil "quicklisp ~A"
                           (ql-dist:version (ql-dist:dist "quicklisp")))
        :time (get-universal-time)
        :run-duration :unknown
        :contact (list :email (get-user-email))))

(defun name-run-directory (run-descr)
  "Generate name for the directory where test run
data (libraries test suites output and the run results) will be saved."
  (format nil
          "~A-~A"
          (fmt-time (getf run-descr :time))
          (getf run-descr :lisp)))

(defun test-output-base-dir ()
  (merge-pathnames "test-runs/"
                   test-grid-config:*src-base-dir*))

(defun run-directory (run-descr)
  (merge-pathnames (make-pathname
                    :directory (list :relative (name-run-directory run-descr))
                    :name      nil
                    :type      nil)
                   (test-output-base-dir)))

(defun lib-log-file (test-run-directory lib-name)
  (merge-pathnames (string-downcase lib-name)
                   test-run-directory))

(defun print-log-header (libname run-descr stream)
  (let ((*print-case* :downcase) (*print-pretty* nil))
    (format stream "============================================================~%")
    (format stream "  cl-test-grid test run~%")
    (format stream "------------------------------------------------------------~%")
    (format stream "  library:           ~A~%" libname)
    (format stream "  lib-world:         ~A~%" (getf run-descr :lib-world))
    (format stream "  lisp:              ~A~%" (getf run-descr :lisp))
    (format stream "  *features*:        ~A~%" (sort (copy-list *features*) #'string<))
    (format stream "  contributor email: ~A~%" (getf (getf run-descr :contact) :email))
    (format stream "  timestamp:         ~A~%" (pretty-fmt-time (get-universal-time)))
    (format stream "============================================================~%~%")))

(defun print-log-footer (libname status stream)
  (let ((*print-case* :downcase))
    (fresh-line stream)
    (terpri stream)
    (format stream "============================================================~%")
    (format stream "  cl-test-grid status for ~A: ~A~%"
            libname (print-test-status nil status))
    (format stream "============================================================~%")))

(defun run-libtest (lib run-descr log-directory)
  (let (status
        (log-file (lib-log-file log-directory lib))
        (start-time (get-internal-real-time)))
    (with-open-file (log-stream log-file
                                :direction :output
                                :if-exists :overwrite
                                :if-does-not-exist :create)
      (let* ((orig-std-out *standard-output*)
             (*standard-output* log-stream)
             (*error-output* log-stream))

        (format orig-std-out
                "Running tests for ~A. *STANDARD-OUTPUT* and *ERROR-OUTPUT* are redirected.~%"
                lib)
        (finish-output orig-std-out)

        (print-log-header lib run-descr *standard-output*)

        (setf status (handler-case
                         (normalize-status (libtest lib))
                       (serious-condition (condition) (progn
                                                        (format t
                                                                "~&Unhandled SERIOUS-CONDITION is signaled: ~A~%"
                                                                condition)
                                                        :fail))))
        (print-log-footer lib status *standard-output*)))

    (list :libname lib
          :status status
          :log-byte-length (file-byte-length log-file)
          :test-duration (/ (- (get-internal-real-time) start-time)
                            internal-time-units-per-second))))

(defun run-info-file (test-run-directory)
  (merge-pathnames "test-run-info.lisp"
                   test-run-directory))

(defun save-run-info (test-run directory)
  (let ((run-file (run-info-file directory)))
    (with-open-file (out run-file
                         :direction :output
                         :element-type 'character ;'(unsigned-byte 8) + flexi-stream
                         :if-exists :supersede
                         :if-does-not-exist :create)
      (print-test-run out test-run))))

(defun gae-blobstore-dir ()
  (merge-pathnames "gae-blobstore/lisp-client/" test-grid-config:*src-base-dir*))

(defparameter *gae-blobstore-base-url* "http://cl-test-grid.appspot.com")

(defun get-blobstore ()
  (pushnew (truename (gae-blobstore-dir)) asdf:*central-registry* :test #'equal)
  (ql:quickload '#:test-grid-gae-blobstore)
  (funcall (intern (string '#:make-blob-store) '#:test-grid-gae-blobstore)
           :base-url *gae-blobstore-base-url*))

(defun submit-logs (blobstore test-run-dir)
  (let* ((run-info (safe-read-file (run-info-file test-run-dir)))
         ;; prepare parameters for the SUBMIT-FILES blobstore function
         (submit-params (mapcar #'(lambda (lib-result)
                                    (let ((libname (getf lib-result :libname)))
                                      (cons libname
                                            (lib-log-file test-run-dir libname))))
                                (run-results run-info))))
    ;; submit files to the blobstore and receive
    ;; their blobkeys in response
    (let ((libname-to-blobkey-alist
           (test-grid-blobstore:submit-files blobstore
                                             submit-params)))
      ;; Now store the blobkeys for every library in the run-info.
      ;; Note, we destructively modify parts of the previously
      ;; read run-info.
      (flet ((get-blob-key (lib)
               (or (cdr (assoc lib libname-to-blobkey-alist))
                   (error "blobstore didn't returned blob key for the log of the ~A libary" lib))))
        (setf (run-results run-info)
              (mapcar #'(lambda (lib-result)
                          (setf (getf lib-result :log-blob-key)
                                (get-blob-key (getf lib-result :libname)))
                          lib-result)
                      (run-results run-info))))
      ;; finally, save the updated run-info with blobkeys
      ;; to the file. Returns the run-info.
      (save-run-info run-info test-run-dir))))

(defun submit-results (test-run-dir)
  (let* ((blobstore (get-blobstore))
         (run-info (submit-logs blobstore test-run-dir)))
    (format t "The log files are submitted. Submitting the test run info...~%")
    (test-grid-blobstore:submit-run-info blobstore run-info)
    (format t "Done. The test results are submitted. They will be reviewed by admin soon and added to the central database.~%")
    run-info))

(defun run-libtests (&optional (libs *all-libs*))
  (let* ((run-descr (make-run-descr))
         (run-dir (run-directory run-descr))
         (lib-results))
    (ensure-directories-exist run-dir)
    (dolist (lib libs)
      (let ((lib-result (run-libtest lib run-descr run-dir)))
        (push lib-result lib-results)))
    (setf (getf run-descr :run-duration)
          (- (get-universal-time)
             (getf run-descr :time)))
    (let ((run (make-run run-descr lib-results)))
      (save-run-info run run-dir)
      (format t "The test results were saved to this directory: ~%~A.~%"
              (truename run-dir))
      run-dir)))

(defun submit-test-run (test-run-dir)
  (format t "~%Submitting the test results to the server...~%")
  (handler-case (submit-results test-run-dir)
    (error (e) (format t "Error occured while uploading the test results to the server: ~A: ~A.
Please submit manually the full content of the results directory
   ~A
to the cl-test-grid issue tracker:
   https://github.com/cl-test-grid/cl-test-grid/issues~%"
                       (type-of e)
                       e
                       (truename test-run-dir))))
  (format t "~%Thank you for the participation!~%"))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Database
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defparameter *db* '(:version 0 :runs ()))

(defvar *standard-db-file*
  (merge-pathnames "db.lisp"
                   test-grid-config:*src-base-dir*))

(defun add-run (run-info &optional (db *db*))
  (push run-info (getf db :runs)))

(defun print-list-elements (destination list separator elem-printer)
  (let ((maybe-separator ""))
    (dolist (elem list)
      (format destination maybe-separator)
      (funcall elem-printer elem)
      (setf maybe-separator separator))))

(defun print-list (destination list separator elem-printer)
  (format destination "(")
  (print-list-elements destination list separator elem-printer)
  (format destination ")"))

(defun print-test-status (destination status)
  (etypecase status
    (symbol (format destination "~s" status))
    (list (progn
            (let ((dest (or destination (make-string-output-stream))))
              (flet ((test-name-printer (test-name)
                       (format dest "~s" test-name)))
                (format dest "(:failed-tests ")
                (print-list dest (sort (copy-list (getf status :failed-tests))
                                       #'string<)
                            " " #'test-name-printer)
                (format dest " :known-to-fail ")
                (print-list dest (sort (copy-list (getf status :known-to-fail))
                                              #'string<)
                            " " #'test-name-printer)
                (format dest ")"))
              (if (null destination)
                  (get-output-stream-string dest)
                  nil))))))

(defun print-test-run (out test-run &optional (indent 0))
  (let ((descr (getf test-run :descr)))
    (format out
            "(:descr (:lisp ~s :lib-world ~s :time ~s :run-duration ~s :contact (:email ~s))~%"
            (getf descr :lisp)
            (getf descr :lib-world)
            (getf descr :time)
            (getf descr :run-duration)
            (getf (getf descr :contact) :email)))
  (format out "~v,0t:results (" (1+ indent))
  (print-list-elements out
                       (sort (copy-list (getf test-run :results))
                             #'string<
                             :key #'(lambda (lib-result)
                                      (getf lib-result :libname)))
                       (format nil "~~%~~~Dt" (+ indent 11))
                       #'(lambda (lib-result)
                           (format out
                                   "(:libname ~s :status ~a :test-duration ~s :log-byte-length ~s :log-blob-key ~s)"
                                   (getf lib-result :libname)
                                   (print-test-status nil (getf lib-result :status))
                                   (getf lib-result :test-duration)
                                   (getf lib-result :log-byte-length)
                                   (getf lib-result :log-blob-key))))
  (format out "))"))

(defun save-db (&optional (db *db*) (stream-or-path *standard-db-file*))
  (with-open-file (out stream-or-path
                       :direction :output
                       :element-type 'character ;'(unsigned-byte 8) + flexi-stream
                       :if-exists :supersede
                       :if-does-not-exist :create)
    (format out "(:version ~a~%" (getf db :version))
    (format out " :runs (")
    (print-list-elements out
                         (getf db :runs)
                         "~%~8t"
                         #'(lambda (test-run)
                             (print-test-run out test-run 8)))
    (format out "))")))

(defun read-db (&optional (stream-or-path *standard-db-file*))
  (with-open-file (in stream-or-path
                      :direction :input
                      :element-type 'character ;'(unsigned-byte 8) + flexi-stream
                      )
    (safe-read in)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Reports
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Templating
;; (will be replaced by cl-closure-templates or html-template
;; after the reports are moved to a separate ASDF system).

(defun replace-str (template placeholder value)
  "Differs from CL:REPLACE in that placeholder and value may be of different length."
  (let* ((pos (or (search placeholder template)
                  (error "Can't find the placeholder ~A in the template." placeholder))))
    (concatenate 'string
                 (subseq template 0 pos)
                 value
                 (subseq template (+ pos (length placeholder))))))

(defun fmt-template (file substitutions-alist)
  (let ((template (file-string file)))
    (dolist (subst substitutions-alist)
      (setf template (replace-str template (car subst) (cdr subst))))
    template))

;; -------- end of templating -------------

(defun generate-fake-run-results ()
  "Generate fake test run result enought to test our reports."
  (flet ((random-status ()
           (let ((r (random 1.0)))
             (cond ((< r 0.43)
                    :ok)
                   ((< r 0.86)
                    :fail)
                   (t :no-resource)))))
    (let ((runs '()))
      (dolist (lisp '("sbcl-fake-1" "sbcl-fake-2" "clisp-fake-1" "ccl-fake-1" "abcl-fake-2"))
        (dolist (lib-world '("quicklisp-fake-2011-00-01" "quicklisp-fake-2011-00-02" "quicklisp-fake-2011-00-03"))
          (let ((run-descr (list :lisp lisp
                                 :lib-world lib-world
                                 :time (get-universal-time)
                                 :run-duration (+ 100 (random 90))
                                 :contact (list :email
                                                (nth (random 3) '("avodonosov@yandex.ru"
                                                                  "other-user@gmail.com"
                                                                  "foo@gmail.com")))))
                (lib-results '()))
            (dolist (lib *all-libs*)
              (push (list :libname lib :status (random-status) :log-char-length 50)
                    lib-results))
            (push (make-run run-descr lib-results) runs))))
      runs)))

(defvar *test-runs-report-template*
  (merge-pathnames "test-runs-report-template.html"
                   test-grid-config:*src-base-dir*))

(defun vertical-html (libname)
  (let ((maybeBr "")
        (libname (string libname)))
    (with-output-to-string (out)
      (loop for char across libname
         do (princ maybeBr out)
           (princ (if (char= char #\-) #\| char) out)
           (setf maybeBr "<br/>")))))

;; example:
#|
 (string= (vertical-html "cl-abc")
          "c<br/>l<br/>|<br/>a<br/>b<br/>c")
|#

;; todo: this should be a blobstore method, but
;; until we move the reporting to a separate
;; asdf system, we don't want the dependency
;; on blobstore here.
(defun blob-uri (blob-key)
  (format nil "~A/blob?key=~A"
          *gae-blobstore-base-url* blob-key))

(defun lib-log-local-uri (test-run lib-result)
  (format nil "file://~A~A"
          (run-directory (run-descr test-run))
          (string-downcase (getf lib-result :libname))))

(defun lib-log-uri (lib-result)
  (let ((blob-key (getf lib-result :log-blob-key)))
    (if blob-key
        (blob-uri blob-key)
        "javascript:alert('The blobstore key is not specified, seems like the library log was not submitted to the online storage')")))

(defun aggregated-status (normalized-status)
  "Returns the test resutl as one symbol, even
if it was an \"extended status\". Possible return
values: :OK, :UNEXPECTED-OK, :FAIL, :NO-RESOURSE, :KNOWN-FAIL."
  (etypecase normalized-status
    (symbol normalized-status)
    (list (destructuring-bind (&key failed-tests known-to-fail) normalized-status
            (cond ((null failed-tests)
                   (if (null known-to-fail)
                       :ok
                       :unexpected-ok))
                  ((set= failed-tests known-to-fail :test #'string=)
                   :known-fail)
                  (t :fail))))))

(defun single-letter-status (aggregated-status)
  (case aggregated-status
    (:ok "O")
    (:unexpected-ok "U")
    (:fail "F")
    (:known-fail "K")
    (:no-resource "R")
    (otherwise aggregated-status)))

(defun status-css-class (aggregated-status)
  (case aggregated-status
    (:ok "ok-status")
    ((:known-fail :fail :unexpected-ok) "fail-status")
    (:no-resource "no-resource-status")
    (otherwise "")))

(defun render-single-letter-status (test-run lib-test-result)
  (declare (ignore test-run))
  (if (null lib-test-result)
      "&nbsp;"
      (let ((status (aggregated-status (getf lib-test-result :status))))
        (format nil "<a class=\"test-status ~A\" href=\"~A\">~A</a>"
                (status-css-class status)
                (lib-log-uri lib-test-result)
                (single-letter-status status)))))

(defun test-runs-table-html (&optional
                             (db *db*)
                             (status-renderer 'render-single-letter-status))
  (with-output-to-string (out)
    (write-line "<table cellspacing=\"1\" class=\"tablesorter\">" out)

    (princ "<thead><tr style=\"vertical-align: bottom;\"><th>Start Time</th><th>Lib World</th><th>Lisp</th><th>Runner</th>" out)
    (dolist (lib *all-libs*)
      (format out "<th>~A</th>" (vertical-html lib)))
    (write-line "</tr></thead>" out)

    (write-line "<tbody>" out)
    (dolist (run (getf db :runs))
      (let ((run-descr (run-descr run))
            (lib-statuses (run-results run)))
        (format out "<tr><td>~A</td><td>~A</td><td>~A</td><td>~A</td>"
                (pretty-fmt-time (getf run-descr :time))
                (getf run-descr :lib-world)
                (getf run-descr :lisp)
                (getf (getf run-descr :contact) :email))
        (dolist (lib *all-libs*)
          (format out "<td>~A</td>"
                  (funcall status-renderer run (find lib lib-statuses
                                                     :key (getter :libname)))))
        (write-line "</tr>" out)))
    (write-line "</tbody>" out)
    (write-line "</table>" out)))

(defun test-runs-report (&optional (db *db*))
  (fmt-template *test-runs-report-template*
                `(("{THE-TABLE}" . ,(test-runs-table-html db))
                  ("{TIME}" . ,(pretty-fmt-time (get-universal-time))))))

(defun export-to-csv (out &optional (db *db*))
  (format out "Lib World,Lisp,Runner,LibName,Status,TestDuration~%")
  (dolist (run (getf db :runs))
    (let ((run-descr (run-descr run)))
      (dolist (lib-result (run-results run))
        (format out "~a,~a,~a,~a,~a,~a~%"
                (getf run-descr :lib-world)
                (getf run-descr :lisp)
                (getf (getf run-descr :contact) :email)
                (string-downcase (getf lib-result :libname))
                (aggregated-status (getf lib-result :status))
                (float (getf lib-result :test-duration)))))))

;; ========= Pivot Reports ==================

;; Conceptualy, test results are objects with various fields:
;; :libname, :lib-world, :lisp, :log-byte-size, :test-duration,
;; :log-byte-length, etc.
;;
;; To build pivot reports, we need to access the
;; results for the report table cells. Every table
;; cell is lying on the crossing of the table rows
;; and columns.
;;
;; In other words, we need to access test results for every
;; combination of values for the fields we put into rows
;; and columsn headers.
;;
;; Currently we want only 3 properties in the row or column
;; headers: :lib-world, :lisp, :libname.
;;
;; Let's build the index - a hash table where keys are
;; 3 element lists representing a particular combination
;; of lib-world, libname and lisp; and the hash table value is
;; a list of test results for that combination:
;;
;; ("sbcl-win-1" "quicklisp 1" "alexandria")     -> (<test results>)
;; ("sbcl-win-1" "quicklisp 1" "babel")          -> (<test results>)
;; ("sbcl-linux-1" "quicklisp 1" "alexandria")   -> (<test results>)
;; ("sbcl-linux-1" "quicklisp 2" "alexandria")   -> (<test results>)
;; ("clisp-win-1" "quicklisp 2" "flexi-streams") -> (<test results>)
;; ...
;;
(defun do-results-impl (db handler)
  "Handler is a function of two arguments: TEST-RUN and LIB-RESULT"
    (dolist (test-run (getf db :runs))
      (dolist (lib-result (run-results test-run))
        (funcall handler test-run lib-result))))

(defmacro do-results ((test-run-var lib-result-var db) &body body)
  `(do-results-impl ,db
     #'(lambda (,test-run-var ,lib-result-var)
         ,@body)))

(defun build-joined-index (db)
  (let ((all-results (make-hash-table :test 'equal)))
    (do-results (run lib-result db)
      (let* ((run-descr (run-descr run))
             (lisp (getf run-descr :lisp))
             (lib-world (getf run-descr :lib-world))
             (libname (getf lib-result :libname)))
        (push lib-result
              (gethash (list lisp lib-world libname) all-results))))
    all-results))

;; The pivot reports code below does not know exact form
;; of the index key - in what order lib-world, lisp and libname
;; values are specified in the key. Moreover, the pivot reports code
;; does not know we choses only these 3 properties for the pivot table
;; headers - it receives the property names for row and column headers
;; as parameters. All that the pivot code below knows, is that the
;; index is a hash table where keys store field values somehow,
;; and that the hash tabble values are lists of results.
;;
;; To abstract away the index format we provide the following functions:

(defun make-index-key ()
  (make-sequence 'list 3))

(defun make-fields-values-setter (fields)
  "Returns a function accepting index key
as the first parameter, field values as the rest parameters,
and destructively modifies the index key by setting the field
values in it. Names of fields to modify in the index key,
and their order is specified by FIELDS."
  (let ((index-key-setters (list :lisp #'(lambda (index-key lisp)
                                           (setf (first index-key) lisp))
                                 :lib-world #'(lambda (index-key lib-world)
                                                (setf (second index-key) lib-world))
                                 :libname #'(lambda (index-key libname)
                                              (setf (third index-key) libname)))))
    (flet ((field-setter (field)
             (or (getf index-key-setters field)
                 (error "field ~A is unknown" field))))
      (let ((setters (mapcar #'field-setter fields)))
        #'(lambda (index-key field-vals)
            (mapc #'(lambda (setter field-val)
                      (funcall setter index-key field-val))
                  setters
                  field-vals)
            index-key)))))

(defun make-fields-values-getter (fields)
  "Returns a function accepting and index key as a parameter,
and returning a list of field values from that index key.
The field names to retrieve, and their order in the
returned list is specified by FIELDS."
  (let ((index-key-getters (list :lisp #'first
                                 :lib-world #'second
                                 :libname #'third)))
    (flet ((field-getter (field)
             (or (getf index-key-getters field)
                 (error "field ~A is unknown" field))))
      (let ((getters (mapcar #'field-getter fields)))
        #'(lambda (index-key)
            (mapcar #'(lambda (getter)
                        (funcall getter index-key))
                    getters))))))

;; Lets introduce a notion of row and columns addresses.
;; An address is a list with values for the fields
;; we put into the row or column header.
;;
;; For example, if we want a privot report with lisp
;; implementations as columns, and lisp-world and
;; library name as rows, then we may have column
;; addresses like
;;   ("sbcl-win-1.0.55")
;;   ("clisp-win-2.49")
;;   ("abcl-1.1")
;; and row addresses like
;;   ("quickisp 2012-02-03" "alexandria")
;;   ("quickisp 2012-02-03" "babel")
;;   ("quickisp 2012-03-03" "cl-json")
;;
;; Order of values in the address depends on the order
;; of grouping we chosen for pivot reports. In the above
;; row addresses lib-worlds are larger groups, and for
;; every lib-world we enumerate library names. In another
;; pivot report we may want other way around: to first group
;; data by libnames, and then subdivede these groups by
;; lib-worlds. In this case row addresses would be
;;   ("alexandria" "quickisp 2011-12-07" )
;;   ("alexandria" "quickisp 2012-01-03" )
;;   ("alexandria" "quickisp 2012-02-03" )
;;   ("babel" "quickisp 2011-12-07" )
;;   ("babel" "quickisp 2012-02-03" )
;;

(defun distinct-addresses (joined-index address-fields)
  (let ((distinct (make-hash-table :test #'equal))
        (fields-getter (make-fields-values-getter address-fields)))
    (maphash #'(lambda (index-key unused-index-value)
                 (declare (ignore unused-index-value))
                 (setf (gethash (funcall fields-getter index-key)
                                distinct)
                       t))
             joined-index)
    (hash-table-keys distinct)))

;; Take into account the specifics of HTML tables - the
;; headers which group several rows or columns, will
;; have a single table cell with rowspan or colspan atribute
;; set to group size.
;;
;; Example HTML for a pivot report with row headers
;; containing lib-world and libname (in that order),
;; and column headers containing lisp implementation name.
;; Pay attantion to the rowspan attribute:

#|

<tr> <th>                                </th> <th>          </th> <th>sbcl-win-1.0.55</th> <th>clisp-linux-2.49</th> </tr>
<tr> <th rowspan="3">quicklisp 2012-01-03</th> <th>alexandria</th> <td>    data...    </td> <td>    data...     </td> </tr>
<tr>                                           <th>babel     </th> <td>    data...    </td> <td>    data...     </td> </tr>
<tr>                                           <th>cl-json   </th> <td>    data...    </td> <td>    data...     </td> </tr>
<tr> <th rowspan="2">quicklisp 2012-02-07</th> <th>alexandria</th> <td>    data...    </td> <td>    data...     </td> </tr>
<tr>                                           <th>cl-json   </th> <td>    data...    </td> <td>    data...     </td> </tr>

|#

;; If we put more thatn one field into the columns, we will
;; have similar situation with colspans. When printing table
;; row by row, cell by cell, we need to know what will be rowspan
;; or colspan for particular <th> cell, and whether we already
;; printed a <th> element for the current group. Lets calculate it.
;;
;; Subaddress is a prefix of row or column address.
;; It represents a some level of pivot groupping.
(defun subaddrs (row-address)
  (nreverse (maplist #'reverse (reverse row-address))))

(assert (equal '((1) (1 2) (1 2 3))
               (subaddrs '(1 2 3))))

;; For every subaddress (group) we calculate a
;; it's span (number of rows/columns in the group),
;; and store a flag, whether we already printed
;; the <th>.
(defstruct (header-print-helper :conc-name)
  (span 0 :type fixnum)
  (printed nil))

;; Here is the main calculation. Returns
;; a hash table mapping subaddresses to header-print-helper objects.
;; For the above example of pivot HTML table, the hashtable
;; for rows would be:
;;
;;  ("quicklisp 2012-01-03")              -> #S(span 3 printed nil)
;;  ("quicklisp 2012-01-03" "alexandria") -> #S(span 1 printed nil)
;;  ("quicklisp 2012-01-03" "cl-json")    -> #S(span 1 printed nil)
;;  ("quicklisp 2012-01-03" "cl-json")    -> #S(span 1 printed nil)
;;  ("quicklisp 2012-02-07")              -> #S(span 2 printed nil)
;;  ("quicklisp 2012-02-07" "alexandria") -> #S(span 1 printed nil)
;;  ("quicklisp 2012-02-07" "cl-json")    -> #S(span 1 printed nil)

(defun calc-spans (row-or-col-addrs)
  (let ((helpers (make-hash-table :test #'equal)))
    (dolist (row-or-col-addr row-or-col-addrs)
      (dolist (subaddr (subaddrs row-or-col-addr))
        (let ((helper (or (gethash subaddr helpers)
                          (setf (gethash subaddr helpers)
                                (make-header-print-helper)))))
          (incf (span helper)))))
    helpers))

;; This is how we print data in table data cells.
(defun format-lib-results (out lib-results)
  (dolist (lib-result lib-results)
    (let ((status (aggregated-status (getf lib-result :status))))
      (format out "<a href=\"~a\" class=\"test-status ~a\">~a</a> "
              (lib-log-uri lib-result)
              (status-css-class status)
              (string-downcase status)))))

(defun print-row-header (row-addr row-spans out)
  (dolist (subaddr (subaddrs row-addr))
    (let* ((helper (gethash subaddr row-spans))
           (rowspan (span helper))
           (maybe-css-class (if (> rowspan 1) "class=\"no-hover\"" "")))
      (when (not (printed helper))
        (format out "<th rowspan=\"~A\" ~A>~A</th>"
                rowspan maybe-css-class
                (string-downcase (car (last subaddr))))
        (setf (printed helper) t)))))

;; Two alternative ways of column headers.
;;
;; This is used when we have enought horizontal space,
;; just a usual <th> element.
(defun print-usual-col-header (colspan text out)
  (format out "<th colspan=\"~A\">~A</th>" colspan text))

;; When we need to save horizontal space, we print
;; column headers rotages, so the headers do not
;; requier more than 1ex from columns width
;; (the data cell may make the column wider,
;; than 1ex of course, but the headers never
;; increase the column width more than needed
;; for the data cells).
(defun print-rotated-col-header (colspan text out)
  ;; Calculate the height so that rotated text fits
  ;; into it: multiply the length of the text to
  ;; sine of the rotation (35 deegrees)
  ;; and add 3 ex for sure.
  (let ((css-height (+ (ceiling (* (sin (/ (* pi 35.0) 180.0))
                                   (length text)))
                       3)))
    (format out "<th colspan=\"~A\" class=\"rotated-header\" style=\"height: ~Aex\"><div>~A</div></th>"
            colspan css-height text)))

(defun print-col-headers (row-field-count col-field-count cols out)
  (let ((col-count (length cols))
        (col-spans (calc-spans cols))
        (header-row-count col-field-count))
    (dotimes (i (+ row-field-count col-count))
      (princ "<colgroup/>" out))
    (dotimes (header-row-num header-row-count)
      (princ "<tr class=\"header-row\">" out)
      (dotimes (row-header row-field-count)
        (princ "<th>&nbsp;</th>" out))
      (dolist (col-addr cols)
        (let* ((cell-addr (subseq col-addr 0 (1+ header-row-num)))
               (helper (gethash cell-addr col-spans)))
          (when (not (printed helper))
            (let ((colspan (span helper))
                  (text (string-downcase (car (last cell-addr)))))
              ;; Heuristic to determine if we need to rotate
              ;; the column headers:
              ;; more than 7 columns, and it is the last
              ;; row of column header (BTW, this is the place where
              ;; the code might need to be adjusted if
              ;; we start using it for pivot reports with more than
              ;; the 3 fields - :lib-world, :libname, :lisp -
              ;; in the headers; actually, it's not perfect even
              ;; now).
              (if (and (> col-count 7)
                       (= header-row-num (1- header-row-count)))
                  (print-rotated-col-header colspan text out)
                  (print-usual-col-header colspan text out)))
            (setf (printed helper) t))))
      (format out "</tr>~%"))))

(defun pivot-table-html (out
                         joined-index
                         row-fields row-fields-sort-predicates
                         col-fields col-fields-sort-predicates)

  (assert (= (length row-fields) (length row-fields-sort-predicates)))
  (assert (= (length col-fields) (length col-fields-sort-predicates)))

  (princ "<table border=\"1\" class=test-table>" out)

  (let* ((row-comparator #'(lambda (rowa rowb)
                             (list< row-fields-sort-predicates
                                    rowa rowb)))
         (col-comparator #'(lambda (cola colb)
                             (list< col-fields-sort-predicates
                                    cola colb)))
         (rows (sort (distinct-addresses joined-index row-fields)
                     row-comparator))
         (row-spans (calc-spans rows))
         (cols (sort (distinct-addresses joined-index col-fields)
                     col-comparator))
         ;; this index key will be destructively modified
         ;; when we need to access the data, to avoid
         ;; consing of creation of new indexe every time
         ;; (is it a prelimenary optimization?)
         (index-key (make-index-key))
         (rows-fields-setter (make-fields-values-setter row-fields))
         (cols-fields-setter (make-fields-values-setter col-fields)))

    (print-col-headers (length row-fields) (length col-fields) cols out)
    (flet ((test-results-by-row-col (row-addr col-addr)
             (funcall rows-fields-setter index-key row-addr)
             (funcall cols-fields-setter index-key col-addr)
             (gethash index-key joined-index)))
      (dolist (row rows)
        (princ "<tr>" out)
        (print-row-header row row-spans out)
        (dolist (col cols)
          (let ((lib-results (test-results-by-row-col row col)))
            (princ "<td>" out)
            (format-lib-results out lib-results)
            (princ "</td>" out)))
        (format out "</tr>~%"))))
  (princ "</table>" out))

(defvar *pivot-report-template*
  (merge-pathnames "pivot-report-template.html"
                   test-grid-config:*src-base-dir*))

(defun pivot-report-html (out
                          joined-index
                          row-fields row-fields-sort-predicates
                          col-fields col-fields-sort-predicates)

  (let ((table (with-output-to-string (str)
                 (pivot-table-html str
                                   joined-index
                                   row-fields row-fields-sort-predicates
                                   col-fields col-fields-sort-predicates))))

    (write-sequence (fmt-template *pivot-report-template*
                                  `(("{THE-TABLE}" . ,table)
                                    ("{TIME}" . ,(pretty-fmt-time (get-universal-time)))))
                    out)))

(defun print-pivot-reports (db)
  (let ((joined-index (build-joined-index db))
        (reports-dir (reports-dir)))
    (flet ((print-report (filename
                          row-fields row-fields-sort-predicates
                          col-fields col-fields-sort-predicates)
             (with-open-file (out (merge-pathnames filename reports-dir)
                                  :direction :output
                                  :element-type 'character ;'(unsigned-byte 8) + flexi-stream
                                  :if-exists :supersede
                                  :if-does-not-exist :create)
               (pivot-report-html out
                                  joined-index
                                  row-fields row-fields-sort-predicates
                                  col-fields col-fields-sort-predicates))))

      (print-report "pivot_ql_lisp-lib.html"
                    '(:lib-world) (list #'string>)
                    '(:lisp :libname) (list #'string< #'string<))
      (print-report "pivot_ql_lib-lisp.html"
                    '(:lib-world) (list #'string>)
                    '(:libname :lisp) (list #'string< #'string<))

      (print-report "pivot_lisp_lib-ql.html"
                    '(:lisp) (list #'string<)
                    '(:libname :lib-world) (list #'string< #'string>))
      (print-report "pivot_lisp_ql-lib.html"
                    '(:lisp) (list #'string<)
                    '(:lib-world :libname) (list #'string> #'string<))

      (print-report "pivot_lib_lisp-ql.html"
                    '(:libname) (list #'string<)
                    '(:lisp :lib-world) (list #'string< #'string>))
      (print-report "pivot_lib_ql-lisp.html"
                    '(:libname) (list #'string<)
                    '(:lib-world :lisp) (list #'string> #'string<))

      (print-report "pivot_ql-lisp_lib.html"
                    '(:lib-world :lisp) (list #'string> #'string<)
                    '(:libname) (list #'string<))
      (print-report "pivot_ql-lib_lisp.html"
                    '(:lib-world :libname) (list #'string> #'string<)
                    '(:lisp) (list #'string<))

      (print-report "pivot_lisp-lib_ql.html"
                    '(:lisp :libname) (list #'string< #'string<)
                    '(:lib-world) (list #'string>))
      (print-report "pivot_lisp-ql_lib.html"
                    '(:lisp :lib-world) (list #'string< #'string>)
                    '(:libname) (list #'string<))

      (print-report "pivot_lib-lisp_ql.html"
                    '(:libname :lisp) (list #'string< #'string<)
                    '(:lib-world) (list #'string>))
      (print-report "pivot_lib-ql_lisp.html"
                    '(:libname :lib-world) (list #'string< #'string>)
                    '(:lisp) (list #'string<)))))

(defun generate-reports (&optional (db *db*))

  (with-open-file (out (merge-pathnames "test-runs-report.html"
                                        (reports-dir))
                       :direction :output
                       :if-exists :supersede
                       :if-does-not-exist :create)
    (write-sequence (test-runs-report db) out))

  (with-open-file (out (merge-pathnames "export.csv"
                                        (reports-dir))
                       :direction :output
                       :if-exists :supersede
                       :if-does-not-exist :create)
    (export-to-csv out))

  (print-pivot-reports db))

(defun reports-dir ()
  (merge-pathnames "reports-generated/"
                   test-grid-config:*src-base-dir*))

;; ========= Regressions between quicklisp distro versions ==================

;;; Alternative representation of a library test status.
;;;
;;; Fail-list is an always sorted list of failures.
;;;
;;; Failures [elements of this list] are strings - failed test
;;; names; or conses in the form (:unexpected-ok . "test-name")
;;; - names of the tests which passed successfully despite
;;; they are known to fail.
;;;
;;; The sort order is so that unexpected OKs are always
;;; at the end.
;;;
;;; Example:
;;; ("test-a2" "test-b" (:unexpected-ok "test-a1"))
;;;
;;; Fail-list may also somtimes be a single keyword: :OK, :FAIL or :NO-RESOURCE
;;;
;;; Note that fail-list does distinguish knoww failures from unknwown failures;
;;; all of them are represented just by stings naming failed tests.

;; Sort order for failures
(defun fail-less (fail-a fail-b)
  (if (stringp fail-a)
      (if (stringp fail-b)
          (string< fail-a fail-b)  ; "test-a" "test-b"
          t)                       ; "test-a" (:unexpected-ok . "test-b")
      (if (stringp fail-b)
          nil                      ; (:unexpected-ok . "test-a") "test-b"
          (string< (cdr fail-a)    ; (:unexpected-ok . "test-a") (:unexpected-ok . "test-b")
                   (cdr fail-b)))))

;; Helper function for fail-list creation:
(defun sort-fail-list (fail-list)
  "Destructively sort the FAIL-LIST"
  (sort fail-list #'fail-less))

(assert (equal '("a" "a2" "a3" "b" "b2" "b3" (:unexpected-ok . "a2.2") (:unexpected-ok . "b2.2"))
               (sort-fail-list '("a" (:unexpected-ok . "a2.2") "b3" "b" "a2" "a3" (:unexpected-ok . "b2.2") "b2"))))

;; Convert the test status from the db.lisp form:
;;    (:failed-tests ("test-a" "test-b") :known-to-fail ("test-c"))
;; to the fail-list form:
;;    ("test-a" "test-b" (:unexpected-ok . "test-c"))
(defun fail-list (lib-status)
  (cond ((eq :ok lib-status)
         '())
        ((eq :fail lib-status)
         :fail)
        ((eq :no-resource lib-status)
         :no-resource)
        ((listp lib-status)
         (let* ((failures (getf lib-status :failed-tests))
                (unexpected-oks (set-difference (getf lib-status :known-to-fail)
                                                failures
                                                :test #'string=)))

           (sort-fail-list (append failures
                                   (mapcar #'(lambda (unexpected-ok-test) (cons :unexpected-ok unexpected-ok-test))
                                           unexpected-oks)))))))
(assert
 (and (equal '() (fail-list :ok))
      (eq :fail (fail-list :fail))
      (eq :no-resource (fail-list :no-resource))
      (equal '("a" "b") (fail-list '(:failed-tests ("a" "b"))))
      (equal '("a" "b") (fail-list '(:failed-tests ("b" "a"))))
      (equal '("a" "b" (:unexpected-ok . "c"))
             (fail-list '(:failed-tests ("a" "b") :known-to-fail ("b" "c"))))))

(defun failures-different-p (fail-list-a fail-list-b)
  (cond ((or (eq :no-resource fail-list-a)
             (eq :no-resource fail-list-b))
         nil)
        ((and (eq :fail fail-list-a)
              (not (null fail-list-b)))
         nil)
        ((and (eq :fail fail-list-b)
              (not (null fail-list-a)))
         nil)
        (t (not (equal fail-list-a fail-list-b)))))

(assert
 (and (not (failures-different-p :fail :fail))
      (not (failures-different-p '() '()))
      (not (failures-different-p :no-resource :no-resource))
      (not (failures-different-p :fail :no-resource))
      (not (failures-different-p :ok :no-resource))
      (not (failures-different-p :fail '("a" "b")))
      (not (failures-different-p '("a" "b") :fail))
      (not (failures-different-p '("a" (:unexpected-ok . "b"))
                                 '("a" (:unexpected-ok . "b"))))
      (failures-different-p '("a") '("b"))
      (failures-different-p '("a") '("a" "b"))
      (failures-different-p '("a") '("a" (:unexpected-ok . "b")))
      (failures-different-p :fail '())))


(defun regressions (new-fail-list old-fail-list)
  "Returns fail list which denotes
what is worse with new-fail-list, comparing
to old-fail-list. Result is represented
by a fail list which may be a list of failures
or just a symbol :FAIL (but never :OK or :NO-RESOURCE).
Accepts any fail list as a parameter."
  (labels (;; helper functions to write
           ;; the COND below, see how
           ;; the RESULTS-ARE is used
           ;; in the COND below and
           ;; the helpers will be obvious
           (match (spec actual-value)
             (or (eq spec actual-value)
                 (and (listp actual-value)
                      (listp spec))))
           (results-are (new old)
             (and (match new new-fail-list)
                  (match old old-fail-list))))
    (cond ((or (eq :no-resource new-fail-list)
                (eq :no-resource old-fail-list))
           nil)

          ((results-are :fail :fail) nil)

          ((results-are :fail '(some)) (if (null old-fail-list) :fail nil))
          ((results-are '(some) :fail) nil)

          ((results-are '(some) '(some))
           (sort-fail-list (set-difference new-fail-list old-fail-list :test #'equal)))

          (t (error "Unexpected fail lists: ~S ~S" new-fail-list old-fail-list)))))

(assert
 (and (equal '("a" "b") (regressions '("a" "b") '("c")))
      (equal '("a" "b") (regressions '("a" "b") '()))
      (equal '() (regressions '("a" "b") '("a" "b")))

      (equal '() (regressions :fail :fail))

      (equal '() (regressions '("a" "b") :fail))
      (equal '() (regressions :fail '("a" "b")))
      (eq :fail (regressions :fail '()))))


;; Diff item represent two results
;; of the same library under the same lisp,
;; but in different quicklisp disto versions.
(defclass quicklisp-diff-item ()
  ((libname :initarg :libname :accessor libname)
   (lisp :initarg :lisp :accessor lisp)
   (new-status :initarg :new-status :accessor new-status)
   (old-status :initarg :old-status :accessor old-status)))

(defun compare-quicklisps (db-index quicklisp-new quicklisp-old)
  (let ((diff-items '())
        (new-quicklisp-keys (remove-if-not #'(lambda (key) (string= (second key) quicklisp-new))
                                           (hash-table-keys db-index))))
    (dolist (key new-quicklisp-keys)
      (let ((key-prev (copy-list key)))
        (setf (second key-prev) quicklisp-old)
        (let ((results (gethash key db-index))
              (results-prev (gethash key-prev db-index)))

          ;; order our results-diff report by library name
          (setf results (sort (copy-list results)
                              (lambda (lib-result-a lib-result-b)
                                (string< (getf lib-result-a :libname)
                                         (getf lib-result-b :libname)))))

          (dolist (lib-result results)
            (let* ((fail-list (fail-list (getf lib-result :status)))
                   (diff-lib-results-prev (remove-if-not #'(lambda (result-prev)
                                                             (failures-different-p fail-list
                                                                                   (fail-list (getf result-prev :status))))
                                                         results-prev)))
              (when (not (null diff-lib-results-prev))
                (dolist (diff-lib-result-prev diff-lib-results-prev)
                  (push (make-instance 'quicklisp-diff-item
                                       :libname (getf lib-result :libname)
                                       :lisp (first key)
                                       :new-status (getf lib-result :status)
                                       :old-status (getf diff-lib-result-prev :status))
                        diff-items))))))))
    diff-items))

(defun print-quicklisp-diff (ql-new ql-old diff-items)
  ;; separate result diffs into two categories:
  ;; diffs which have regressions, and diffs which do
  ;; not have regressions - only improvements
  (let ((have-regressions '())
        (improvements-only '()))
    (dolist (diff-item diff-items)
      (if (regressions (fail-list (new-status diff-item))
                       (fail-list (old-status diff-item)))
        (push diff-item have-regressions)
        (push diff-item improvements-only)))

    (flet ((print-diff-item (diff-item)
             (let ((*print-pretty* nil))
               (format t "~a, ~a:~%~a: ~a~%~a: ~a~%~%"
                       (string-downcase (libname diff-item))
                       (lisp diff-item)
                       ql-new
                       (new-status diff-item)
                       ql-old
                       (old-status diff-item)))))
      (format t "~%~%************* Have Regressions *************~%")
      (dolist (diff-item have-regressions)
        (print-diff-item diff-item))
      (format t "~%~%************* Improvements Only *************~%")
      (dolist (diff-item improvements-only)
        (print-diff-item diff-item)))))