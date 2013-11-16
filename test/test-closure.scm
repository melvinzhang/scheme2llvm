; Returning lambda with state.
(begin

(define (adder x) (lambda (y) (+ x y)))
(define a (adder 3)) 
(define b (adder 4))
(display (+ (a 1) (b 2)))

)
;->10                  
