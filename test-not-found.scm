(begin
    (define (even x) (if (= x 2) 1 (if (odd  (- x 1)) 1 0)))
    (display (even 10))
)
