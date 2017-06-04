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
(assert 4 (and 2 4))
(assert '() (and 0 0))

(done)

)
