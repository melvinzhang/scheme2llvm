(begin
    (define (odd x)  (if (= x 1) 1 (if (even (- x 1)) 1 0)))
    (define (even x) (if (= x 2) 1 (if (odd  (- x 1)) 1 0)))
    (display (even 10))
)
