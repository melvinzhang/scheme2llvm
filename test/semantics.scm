(begin

; helper funtions to run tests
(define passed 0)
(define failed 0)

(define (error ex1 ex2)
  (display ex1) (display " != ")
  (display ex2) (newline)
  (exit (raw-number 1)))

(define (assert ex1 ex2)
  (if (eq? ex1 ex2)
    (begin
      (display ".")
      (set! passed (+ passed 1)))
    (error ex1 ex2)))

(define (done)
  (newline)
  (display "Ran ")
  (display passed)
  (display " tests.")
  (newline)
  (display "All passed.")
  (newline)
  0)

; +,-.*,/,%,=,> are a binary functions created with llvm-define
; only works on numbers
(assert 5 (+ 1 4))
(assert 3 (- 4 1))

(assert 1 (= 5 5))
(assert 0 (= 2 4))

(assert 1 (> 4 2))
(assert 0 (> 2 4))

; and, or, not are binary functions created with llvm-define
; and returns the second argument if the first one is truthy, otherwise return nil
(assert 4 (and 1 4))
(assert "a" (and 1 "a"))
(assert '() (and 0 4))

; or returns the 1 if the first argument it is truthy, otherwise return the second argument
(assert "b" (or 0 "b"))
(assert 1 (or "a" 0))

; not returns nil if the argument is truthy, otherwise return 1
(assert 1 (not 0))
(assert 1 (not '()))
(assert '() (not 1))
(assert '() (not "a"))

(done)

)
