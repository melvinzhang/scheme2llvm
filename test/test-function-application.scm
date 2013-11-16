; Function application.
(begin

(define y 5) 
(define (fac x) (if (= x 0) 1 (* x (fac (- x 1)))))
(display (fac y))

)
;->120
