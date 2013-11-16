(begin

(define y 5)
(define (fac x)
  (cond ((= x 0) 1)
         (else (* x (fac (- x 1))))))

(display (fac y))

)
