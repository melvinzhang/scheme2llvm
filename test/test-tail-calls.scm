(begin
  (define (calls n m)
    (cond 
      ((= n 0) (display m) m)
      (else (calls (- n 1) (+ m 1)))))

  (display (calls (read) 0))

  0
)
