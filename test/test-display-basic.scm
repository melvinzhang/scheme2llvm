(begin

(display "Hello World")
(newline)

(display (quote (1 2 "foo" "bar" fum)))
(newline)

(display (quote (1 . (2 . 3))))
(newline)

(display (list->string (quote (97 98 98 99))))
(newline)

(display (number->string 123546))
(newline)

(display (string? (symbol->string (quote foo))))
(newline)

(display (member 5 (quote (1 2 3 4))))
(newline)

(display (read))
(newline)

)
