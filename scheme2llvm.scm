;; A small self applicable scheme->llvm compiler.
;; ,  Tobias Nurmiranta
;;
;; -- To Use It --
;; Reads scheme-code from standard input.
;; cat code.ss|mzscheme --script compile.ss|llvm-as -f -o=test.bc;lli test.bc
;;
;; The compiler is painfully slow since it for testing purposes
;; compiles all help functions as well (see variable bootstrap). 
;; It extends standard scheme with a subset of available
;; llvm-instructions, and adds the new special-form llvm-define.
;;
;; - llvm-define -
;; llvm-define defines a llvm-function, which parameters are the
;; llvm-function's parameters, so it doesn't use an environment for
;; variable lookup. llvm-define's are used to implement basic
;; functionality of the language, and can only call other llvm-defined
;; functions. Numbers in llvm-defines are compiled to untyped raw
;; numbers.
;;
;; -- Example of Self Application --
;; bash-2.05b$ mzscheme --script compile.ss > hello.ll
;; (display "you can't h4xx0r a cake if you not kr4xx0r an egg")
;; bash-2.05b$ cat compile.ss|mzscheme --script compile.ss|llvm-as -o=ccomp.bc
;; bash-2.05b$ lli ccomp.bc > hello2.ll                                
;; (display "you can't h4xx0r a cake if you not kr4xx0r an egg")       
;; bash-2.05b$ llvm-as hello2.ll
;; bash-2.05b$ lli hello2.bc
;; you can't h4xx0r a cake if you not kr4xx0r an egg
;; bash-2.05b$ diff hello.ll hello2.ll
;; bash-2.05b$
;;
;; -- Implemented Types --
;; 30 bit immediate fixnums (also used as chars)
;; symbols
;; strings
;; vectors (which are also used as conscells)
;; functions (fixed and arbitrary number of arguments)
;;
;; All objects are represented with i64 as follows: 
;;   null is 1
;;   numbers use 62 bits and have b10 in two low order bits
;;   pointers store tag information in the first allocated i64
;;
;; -- The Implementation --

(begin
  
(define (error func str)
  (display func) (display " ") 
  (display str) (newline)
  (exit 1))

;; Abstract syntax

(define (tagged-list? exp tag) (if (pair? exp) (eq? (car exp) tag) (= 1 0)))
(define (self-evaluating? exp) (or (number? exp) (string? exp)))
(define (variable? exp) (symbol? exp))
(define (assignment? exp) (tagged-list? exp 'set!))
(define (definition? exp) (tagged-list? exp 'define))
(define (if? exp) (tagged-list? exp 'if))
(define (cond? exp) (tagged-list? exp 'cond))
(define (lambda? exp) (tagged-list? exp 'lambda))
(define (begin? exp) (tagged-list? exp 'begin))
(define (quote? exp) (tagged-list? exp 'quote))
(define (let? exp) (tagged-list? exp 'let))
(define (application? exp) (pair? exp))

(define (llvm-definition? exp) (tagged-list? exp 'llvm-define))
(define (llvm-instruction? exp) (assoc (operator exp) llvm-instructions))

(define (llvm-load? exp) (tagged-list? exp 'load))
(define (llvm-store? exp) (tagged-list? exp 'store))
(define (llvm-getelementptr? exp) (tagged-list? exp 'getelementptr))
(define (llvm-ptrtoint? exp) (tagged-list? exp 'ptrtoint))
(define (llvm-inttoptr? exp) (tagged-list? exp 'inttoptr))
(define (llvm-ret? exp) (tagged-list? exp 'ret))

(define (operator exp) (car exp))
(define (operands exp) (cdr exp))
(define (first-arg exp) (cadr exp))
(define (second-arg exp) (caddr exp))
(define (third-arg exp) (cadddr exp))

(define (begin-actions exp) (cdr exp))
(define (last-exp? seq) (null? (cdr seq)))

(define (text-of-quotation exp) (cadr exp))

(define (definition-variable exp)
  (if (symbol? (cadr exp)) (cadr exp) (caadr exp)))
(define (definition-value exp)
  (if (symbol? (cadr exp))
      (caddr exp) (cons 'lambda (cons (cdadr exp) (cddr exp)))))

(define (if-predicate exp) (cadr exp))
(define (if-consequent exp) (caddr exp))
(define (if-alternative exp)
  (if (not (null? (cdddr exp))) (cadddr exp) 0))

(define (make-if predicate consequent alternative)
  (list 'if predicate consequent alternative))

(define (lambda-parameters exp) 
  (define (fix-list lst)
    (cond ((not (pair? lst)) (cons lst '()))
          (else (cons (car lst) (fix-list (cdr lst))))))
  (if (list? (cadr exp)) (cadr exp)
      (fix-list (cadr exp))))
(define (lambda-arbitrary-args? exp) (not (list? (cadr exp))))
(define (lambda-body exp) (cddr exp))

;; Code transformation

(define (sequence->exp seq)
  (cond ((null? seq) seq)
        ((last-exp? seq) (car seq))
        (else (make-begin seq))))
(define (make-begin seq) (cons 'begin seq))

(define (cond-clauses exp) (cdr exp))
(define (cond-else-clause? clause) (eq? (cond-predicate clause) 'else))
(define (cond-predicate clause) (car clause))
(define (cond-actions clause) (cdr clause))
(define (cond->if exp) (expand-clauses (cond-clauses exp)))
(define (expand-clauses clauses)
  (if (null? clauses) 0
      (let ((first (car clauses))
            (rest (cdr clauses)))
        (if (cond-else-clause? first)
            (if (null? rest) (sequence->exp (cond-actions first))
                (error 'expand-clauses "else clause not last"))
            (make-if (cond-predicate first)
                     (sequence->exp (cond-actions first))
                     (expand-clauses rest))))))

(define (let-vars exp) (map (lambda (x) (car x)) (cadr exp)))
(define (let-vals exp) (map (lambda (x) (cadr x)) (cadr exp)))
(define (let-body exp) (cddr exp))    
(define (let->lambda exp)
  (cons (cons 'lambda (cons (let-vars exp) (let-body exp)))
        (let-vals exp)))

;; Code constructors

(define (compiled-code compile-res) (cdr compile-res))
(define (compiled-target compile-res) (car compile-res))

(define (append-code2 instrs)
    (cond ((null? instrs) instrs)
          ((null? (car instrs))
           (append-code2 (cdr instrs)))
          ((pair? (car instrs))
           (append (car instrs) (append-code2 (cdr instrs))))
          (else (cons (car instrs) (append-code2 (cdr instrs))))))
(define (append-code . instrs) (append-code2 instrs)) 
(define (make-code target . instrs) (cons target (append-code2 instrs)))

;; Generate variables, labels, string constants and functions.

(define c
  (lambda strs
    (define (str-app str1 rest)
      (if (null? rest) str1
          (string-append str1 (str-app (car rest) (cdr rest)))))
    (str-app (car strs) (cdr strs))))
                   
(define (init-generators)
  (set! var-counter 0)
  (set! label-counter 0)
  (set! function-counter 0)
  (set! llvm-function-list '())
  (set! llvm-primitive-functions 
        '(llvm-read-char print append-bytearray bytearray-ref exit malloc))
  (set! llvm-string-list '()))

(define var-counter 0)
(define (make-var)
  (set! var-counter (+ 1 var-counter))
  (c "%r" (number->string var-counter)))

(define (make-global-var)
  (set! var-counter (+ 1 var-counter))
  (c "@r" (number->string var-counter)))

(define label-counter 0)
(define (make-label)
  (set! label-counter (+ 1 label-counter))
  (c "label" (number->string label-counter)))

(define function-counter 0)
(define (make-raw-function-name)
  (set! function-counter (+ 1 function-counter))
  (c "function" (number->string function-counter)))
(define (make-function-name)
  (c "@" (make-raw-function-name)))

(define llvm-primitive-functions '())
(define (add-llvm-function-name f-name)
  (set! llvm-primitive-functions (cons f-name llvm-primitive-functions)))

(define llvm-function-list '())
(define (add-llvm-function f-name f-params f-body)
  (define (build-params params)
    (if (null? params) ""
        (c "i64 " (llvm-repr (car params))
           (if (null? (cdr params)) "" ", ")
           (build-params (cdr params)))))
  (set! llvm-function-list
    (append 
         llvm-function-list
         (list (append-code 
               (c "define fastcc i64 " (llvm-global-repr f-name) "(" (build-params f-params) ") nounwind {")
               (compiled-code f-body)
               (llvm-ret (compiled-target f-body))
               (c "}"))))))

(define (fix-string-format str) ;; some extra work since we have no char-type.
  (define (str-ref-int str pos) (char->integer (string-ref str pos)))
  (define (esc-char hex1 hex2 rest)
    (cons (integer->char 92) 
          (cons (integer->char hex1) (cons (integer->char hex2) rest))))
  (define (fix-str-format str pos end)
    (cond ((= pos end) '())
          ((eq? (str-ref-int str pos) 34) 
           (esc-char 50 50 (fix-str-format str (+ pos 1) end)))
          ((eq? (str-ref-int str pos) 92)
           (esc-char 53 67 (fix-str-format str (+ pos 1) end)))
          (else (cons (string-ref str pos) 
                      (fix-str-format str (+ pos 1) end)))))
  (list->string (fix-str-format str 0 (string-length str))))

(define llvm-string-list '())
(define (add-llvm-string target str)  
  (let ((str-type (c "[" (llvm-repr (+ (string-length str) 1)) " x i8]")))
    (set! llvm-string-list 
          (append llvm-string-list
                  (list
                   (c target " = internal constant " str-type 
                      " c\"" (fix-string-format str) "\\00\""))))
    (c str-type "*")))

;; Lexical addressing.

(define (extend-c-t-env params c-t-env) (cons params c-t-env))
(define (current-c-t-env c-t-env) (car c-t-env))
(define (outer-c-t-env c-t-env) (cdr c-t-env))

(define (find-var var c-t-env scope)
  (define (find-index var env index)
    (cond ((null? env) '())
      ((eq? (car env) var) index)
      (else (find-index var (cdr env) (+ 1 index)))))
  (if (null? c-t-env) '()
      (let ((index (find-index var (current-c-t-env c-t-env) 1)))
    (if (null? index)
        (find-var var (outer-c-t-env c-t-env) (+ 1 scope))
        (cons scope index)))))
 
;; LLVM primitives.

(define llvm-instructions
  '(;; binary operations.
    (add . "add") (sub . "sub") (mul . "mul") (div . "udiv") (rem . "urem")    
    ;; binary bit operations.
    (bit-and . "and") (bit-or . "or") (bit-xor . "xor") 
    (bit-shl . "shl") (bit-shr . "lshr")
    ;; boolean operations.
    (seteq . "icmp eq") (setne . "icmp ne") (setlt . "icmp ult") (setgt . "icmp ugt")
    (setle . "icmp ule") (setge . "icmp uge")
    ;; memory operations.
    (getelementptr . 0)
    (cast . 0) (load . 0) (store . 0) (ptrtoint . 0) (inttoptr . 0) 
    (ret . 0)))

(define llvm-boolean-instructions '(seteq setne setlt setgt setle setge))
(define llvm-shift-instructions '(bit-shl bit-shr))
(define (llvm-instr-name op) (cdr (assoc op llvm-instructions)))

(define (llvm-global-repr exp)
  (cond ((number? exp) (number->string exp))
        ((symbol? exp) (c "@\"scm-" (symbol->string exp) "\""))
        (else exp)))

(define (llvm-repr exp)
  (cond ((number? exp) (number->string exp))
        ((symbol? exp) (c "%\"" (symbol->string exp) "\""))
        (else exp)))

(define (llvm-instruction target op x y)
  (c target " = " (llvm-instr-name op) " i64 " 
     (llvm-repr x) ", " (llvm-repr y)))

(define (llvm-id target exp) ; Identity function
  (llvm-instruction target 'add 0 exp))

(define (llvm-call2 target function args)
  (define (build-arg-list arg-list fi)
    (if (null? arg-list) ""
        (c (if (= fi 1) "" ", ")
           (c "i64 " (llvm-repr (car arg-list)))
           (build-arg-list (cdr arg-list) 0))))
  (c target " = tail call fastcc i64 " (llvm-global-repr function) "(" (build-arg-list args 1) ")"))
(define (llvm-call target function . args)
  (llvm-call2 target function args))

(define (llvm-ret value) (c "ret i64 " (llvm-repr value)))

(define (llvm-ptrtoint target type1 x type2)
  (c target " = ptrtoint " type1 " " x " to " type2))

(define (llvm-inttoptr target type1 x type2)
  (c target " = inttoptr " type1 " " x " to " type2))

(define (llvm-phi target type vars) ; not used
  (define (build-phi-list phis)
    (c "[" (llvm-repr (car (car phis))) ", %" (cdr (car phis)) "]"
       (if (null? (cdr phis)) "" 
           (c ", " (build-phi-list (cdr phis))))))
  (c target " = phi " type " " (build-phi-list vars))) 

(define (llvm-label label) (c label ":"))
(define (llvm-br label) (c "br label %" label))
(define (llvm-bool-br pred c-label a-label)
  (let ((t1 (make-var))
        (t2 (make-var)))
    (append-code
     (llvm-call t1 'raw-number pred) ; false iff pred = 0 or '()
     (c t2 " = icmp ne i64 " t1 ", 0")
     (c "br i1 " t2 ", label %" c-label ", label %" a-label))))

(define (llvm-store target value) 
  (c "store i64 " value ", i64* " target))

(define (llvm-load target var) (c target " = load i64* " var))
(define (llvm-alloca-var target) (c target " = alloca i64"))

(define (llvm-shift-op target op value sh)
  (c target " = " (llvm-instr-name op) " i64 " (llvm-repr value) ", " sh))

(define (llvm-getelementptr target ptr index)
  (let ((t1 (make-var)))
    (append-code
      (llvm-inttoptr t1 "i64" ptr "i64*")
      (c target " = getelementptr i64* " t1 ", i64 " index))))

(define (llvm-vector-ref target vector index)
  (llvm-call target 'vector-ref (llvm-repr vector) (llvm-repr index)))
  
(define (llvm-vector-set! vector index value)
  (llvm-call (make-var) 'vector-set! (llvm-repr vector)
             (llvm-repr index) (llvm-repr value)))

(define (block-comment str exp)
  (display (c ";>>> " str))
  (newline)
  (display exp)
  (newline)
  (display ";<<<")
  (newline))

(define (comment str)
  (display (c "; " str))
  (newline))

;; Compiler
;; Return value: A cons-pair (target . code)
;;               target: Target register
;;               code:   The created code

(define (compile exp c-t-env)
  
  ;(block-comment "compile" exp)

  (cond ((self-evaluating? exp)  (compile-self-evaluating exp c-t-env))
        ((variable? exp)         (compile-variable exp c-t-env))
        ((quote? exp)            (compile-self-evaluating
                                  (text-of-quotation exp) c-t-env))
        ((or (assignment? exp) 
             (definition? exp))  (compile-assignment exp c-t-env))
        ((if? exp)               (compile-if exp c-t-env))
        ((cond? exp)             (compile-if (cond->if exp) c-t-env))
        ((lambda? exp)           (compile-lambda exp c-t-env))
        ((let? exp)              (compile (let->lambda exp) c-t-env))
        ((begin? exp)            (compile-sequence (begin-actions exp) c-t-env))
        ((llvm-instruction? exp) (compile-llvm-instruction exp c-t-env))
        ((llvm-definition? exp)  (compile-llvm-definition exp c-t-env))
        ((application? exp)      (compile-application exp c-t-env))
        (else                    (error 'compile "Unknown expression type"))))

(define (compile-self-evaluating exp c-t-env)
  (if (and (eq? c-t-env 'llvm-function) (number? exp))
      (make-code (llvm-repr exp) '()) ;; create raw integer
      (let ((target (make-var)))
    (make-code
         target
         (cond ((number? exp) (llvm-call target 'make-number (llvm-repr exp)))
               ((string? exp)
                (let ((str (make-global-var))
                      (t1 (make-var)))
                  (append-code
                   (llvm-ptrtoint t1 (add-llvm-string str exp) str "i64")
                   (llvm-call target 'make-string t1 (string-length exp)))))
               ((symbol? exp)
                (let ((str (make-global-var))
                      (t1 (make-var))
                      (str-repr (symbol->string exp)))
                  (append-code
                   (llvm-ptrtoint t1 (add-llvm-string str str-repr) str "i64")
                   (llvm-call target 'make-symbol t1 (string-length str-repr)))))
               ((null? exp) (llvm-call target 'make-null))
               ((pair? exp)
                (let ((c1 (compile-self-evaluating (car exp) c-t-env))
                      (c2 (compile-self-evaluating (cdr exp) c-t-env)))
                  (append-code
                   (compiled-code c1) (compiled-code c2)
                   (llvm-call target 'cons 
                              (compiled-target c1) (compiled-target c2)))))
               (else (error 'self-eval "not implemented")))))))

(define (compile-variable exp c-t-env)
  (if (eq? c-t-env 'llvm-function)
      (make-code (llvm-repr exp) '())
      (let ((target (make-var)) 
            (c-t-pos (find-var exp c-t-env 0)))
    (if (null? c-t-pos) (error exp "not found")
        (make-code target (llvm-call target 'lookup-variable 'env
                                         (car c-t-pos) (cdr c-t-pos)))))))

(define (compile-assignment exp c-t-env)
  (let ((target (make-var))
        (c-t-pos (find-var (definition-variable exp) c-t-env 0))
        (value (cond 
                 ((lambda? (definition-value exp)) 
                    (compile-named-lambda (definition-value exp) c-t-env (definition-variable exp)))
                 (else 
                    (compile (definition-value exp) c-t-env)))))
    (if (null? c-t-pos) (error 'compile-assignment "not found")
    (make-code
         target 
         (compiled-code value)
         (llvm-call target 'set-variable! 'env (car c-t-pos) (cdr c-t-pos) 
                    (compiled-target value))))))
  
(define (compile-if exp c-t-env)
  (let ((c-branch (make-label))
        (a-branch (make-label))
        (after-if (make-label))
        (p-code (compile (if-predicate exp) c-t-env))
        (c-code (compile (if-consequent exp) c-t-env))
        (a-code (compile (if-alternative exp) c-t-env))
        (t1 (make-var))
        (target (make-var)))
    (make-code target
           (llvm-alloca-var t1)
           (compiled-code p-code) 
           (llvm-bool-br (compiled-target p-code) c-branch a-branch)
           (llvm-label c-branch) 
           (compiled-code c-code)
           (llvm-store t1 (compiled-target c-code))
           (llvm-br after-if)
           (llvm-label a-branch) 
           (compiled-code a-code)
           (llvm-store t1 (compiled-target a-code))
           (llvm-br after-if)
           (llvm-label after-if)
           (llvm-load target t1))))

(define (compile-sequence seq c-t-env)
  (define (sequence-defines seq)
    (cond ((null? seq) '())
          ((definition? (car seq))
           (cons (definition-variable (car seq)) (sequence-defines (cdr seq))))
          ((llvm-definition? (car seq))
           (add-llvm-function-name (definition-variable (car seq)))
           (sequence-defines (cdr seq)))
          (else (sequence-defines (cdr seq)))))
  
  (define (append-sequences seq code-seq c-t-env2)
    (if (last-exp? seq)
        (let ((l-code (compile (car seq) c-t-env2)))
          (make-code (compiled-target l-code) code-seq (compiled-code l-code)))
        (append-sequences
         (cdr seq)
         (append-code code-seq (compiled-code (compile (car seq) c-t-env2)))
         c-t-env2)))
    
  (let ((seq-defines (sequence-defines seq)))
    (if (null? seq-defines) ;; no local definitions
        (append-sequences seq '() c-t-env)
        (let ((seq-code 
               (append-sequences seq '() (extend-c-t-env seq-defines c-t-env)))
              (f-name (make-function-name))
              (t1 (make-var)) 
              (t2 (make-var))
              (seq-env (make-var))
              (target (make-var)))
          (add-llvm-function f-name '(env) seq-code)
          (make-code 
           target
           (llvm-call t1 'make-env (length seq-defines) 'env)
           (llvm-call target f-name t1))))))

(define (compile-lambda-with-name exp c-t-env f-name)
  (let ((t1 (make-var))
        (target (make-var))
        (l-body 
         (compile-sequence (lambda-body exp)
                           (extend-c-t-env (lambda-parameters exp) c-t-env))))
    (add-llvm-function f-name '(env) l-body)
    (make-code 
     target 
     (llvm-ptrtoint t1 "i64 (i64)*" f-name "i64")
     (llvm-call target 'make-function t1 'env 
                (if (lambda-arbitrary-args? exp)
                    (length (lambda-parameters exp))
                    0)))))

(define (compile-lambda exp c-t-env)
  (compile-lambda-with-name exp c-t-env (make-function-name)))

(define (compile-named-lambda exp c-t-env def-name)
  (compile-lambda-with-name exp c-t-env (c "@\"" (make-raw-function-name) "-" (symbol->string def-name) "\"")))

(define (compile-llvm-definition exp c-t-env)
  (let ((f-name (definition-variable exp))
    (f-lambda (definition-value exp))
        (target (make-var)))
    (add-llvm-function 
     f-name
     (lambda-parameters f-lambda)
     (compile-sequence (lambda-body f-lambda) 'llvm-function))
    (make-code 0 '())))

(define (compile-llvm-instruction exp c-t-env)
  (let ((target (make-var)))
    (cond 
      ((llvm-load? exp)
       (let ((ptr (compile (first-arg exp) c-t-env)))
         (make-code target (compiled-code ptr)
            (llvm-load target (compiled-target ptr)))))
      ((llvm-store? exp)
       (let ((value (compile (first-arg exp) c-t-env))
         (ptr   (compile (second-arg exp) c-t-env)))
         (make-code (compiled-target ptr)
                        (compiled-code value) (compiled-code ptr)
            (llvm-store (compiled-target ptr)
                    (compiled-target value)))))
      ((llvm-getelementptr? exp)
       (let ((ptr (compile (first-arg exp) c-t-env))
         (index (compile (second-arg exp) c-t-env)))
         (make-code target (compiled-code ptr) (compiled-code index)
            (llvm-getelementptr target (compiled-target ptr)
                        (compiled-target index)))))
      ((llvm-ptrtoint? exp)
       (let ((value (compile (second-arg exp) c-t-env)))
         (make-code target (compiled-code value)
            (llvm-ptrtoint target (first-arg exp) 
                   (compiled-target value) (third-arg exp)))))
      ((llvm-inttoptr? exp)
       (let ((value (compile (second-arg exp) c-t-env)))
         (make-code target (compiled-code value)
            (llvm-inttoptr target (first-arg exp) 
                   (compiled-target value) (third-arg exp)))))
      ((llvm-ret? exp)
       (let ((value (compile (first-arg exp) c-t-env)))
         (make-code (compiled-target value) (compiled-code value)
            (llvm-ret (compiled-target value)))))
      ((member (operator exp) llvm-shift-instructions)
       (let ((value (compile (first-arg exp) c-t-env))
         (sh (compile (second-arg exp) c-t-env)))
         (make-code target (compiled-code value) (compiled-code sh)
            (llvm-shift-op target (operator exp)
                       (compiled-target value)
                       (compiled-target sh)))))
      ((member (operator exp) llvm-boolean-instructions)
       (let ((x (compile (first-arg exp) c-t-env))
         (y (compile (second-arg exp) c-t-env))
         (t1 (make-var))
         (t2 (make-var)))
         (make-code target (compiled-code x) (compiled-code y)
            (llvm-instruction t1 (operator exp) (compiled-target x) (compiled-target y))
            (c t2 " = zext i1 " t1 " to i64")
            (llvm-call target 'make-number t2))))
      (else ;; binary operation
       (let ((x (compile (first-arg exp) c-t-env))
         (y (compile (second-arg exp) c-t-env)))
         (make-code target (compiled-code x) (compiled-code y)
            (llvm-instruction 
             target (operator exp) 
             (compiled-target x) (compiled-target y))))))))

(define (compile-application exp c-t-env)
  (define (build-param-list param-list operand-codes index)
    (if (null? operand-codes) '()
        (append-code 
         (compiled-code (car operand-codes))
         (llvm-vector-set! 
          param-list index (compiled-target (car operand-codes)))
         (build-param-list param-list (cdr operand-codes) (+ 1 index)))))

  (if (member (operator exp) llvm-primitive-functions)
      (compile-llvm-application exp c-t-env)
      (let ((func (make-var))
            (f-env (make-var))
            (f-nparams (make-var))
            (call-env (make-var))
            (f-func (make-var))
            (target (make-var))
            (proc-code (compile (operator exp) c-t-env))
            (operand-codes (map (lambda (operand) (compile operand c-t-env))
                                (operands exp))))
        (make-code 
         target
         (compiled-code proc-code)
         (llvm-call f-env 'get-function-env (compiled-target proc-code))
         (llvm-call call-env 'make-env (length (operands exp)) f-env)
         (llvm-call f-func 'get-function-func (compiled-target proc-code))
         (llvm-inttoptr func "i64" f-func "i64 (i64)*")
         (build-param-list call-env operand-codes 1)
         (llvm-call f-nparams 'get-function-nparams (compiled-target proc-code))
         (llvm-call (make-var) 'fix-arbitrary-funcs f-nparams call-env)
         (llvm-call target func call-env)))))

(define (compile-llvm-application exp c-t-env)
  (let ((target (make-var))
        (operand-codes (map (lambda (operand) (compile operand c-t-env))
                            (operands exp))))
    (make-code target 
               (append-code2 (map compiled-code operand-codes))
               (llvm-call2 target (operator exp) 
                           (map compiled-target operand-codes)))))

(define bootstrap-llvm-code
"
declare i32 @printf(i8*, ...)
declare i32 @exit(i32)
declare i32 @getchar()
declare i8* @malloc(i64)
declare void @GC_init()
declare void @GC_disable()
declare i8* @GC_malloc(i64)
declare void @llvm.memcpy.p0i8.p0i8.i64(i8*, i8*, i64, i32, i1)

define fastcc i64 @\"scm-llvm-read-char\"() {
    %res.0 = call i32 @getchar( )
    %res.1 = sext i32 %res.0 to i64
    ret i64 %res.1
}

define fastcc i64 @\"scm-print\"(i64 %format, i64 %value) {
    %format2 = inttoptr i64 %format to i8*
    call i32 (i8*, ...)* @printf( i8* %format2, i64 %value )
    ret i64 0
}

define fastcc i64 @\"scm-malloc\"(i64 %num) {
    %r0 = mul i64 8, %num
    %r1 = call i8* @GC_malloc( i64 %r0 )
    %r2 = ptrtoint i8* %r1 to i64
    ret i64 %r2
}

define fastcc i64 @\"scm-append-bytearray\"(i64 %arr, i64 %ch, i64 %size) {
    %newsize = add i64 %size, 1
    %res = call i8* @GC_malloc( i64 %newsize )
    %ch2 = trunc i64 %ch to i8
    %end = getelementptr i8* %res, i64 %size
    store i8 %ch2, i8* %end
    %cpy = icmp eq i64 %size, 0
    br i1 %cpy, label %nocopy, label %copy

copy:
    %arr2 = inttoptr i64 %arr to i8*
    call void @llvm.memcpy.p0i8.p0i8.i64( i8* %res, i8* %arr2, i64 %size, i32 0, i1 0 )
    br label %nocopy

nocopy:
    %res3 = ptrtoint i8* %res to i64
    ret i64 %res3
}

define fastcc i64 @\"scm-bytearray-ref\"(i64 %arr, i64 %index) {
    %arr2 = inttoptr i64 %arr to i8*
    %ptr = getelementptr i8* %arr2, i64 %index
    %res = load i8* %ptr
    %res2 = sext i8 %res to i64
    ret i64 %res2
}

define fastcc i64 @\"scm-exit\"(i64 %ev) {
    %ev2 = trunc i64 %ev to i32
    call i32 @exit( i32 %ev2 )
    ret i64 0
}

define fastcc i64 @main(i32 %argc, i8** %argv) {
    call void @GC_init( )
    %r0 = call fastcc i64 @startup( i64 0 )
    %r1 = call fastcc i64 @\"scm-raw-number\"(i64 %r0)
    ret i64 %r1
}

;; Autogenerated code
")

(define bootstrap
  '(begin 
     (llvm-define (and x y) (if x y (make-null)))
     (llvm-define (or x y)  (if x (make-true) y))
     (llvm-define (not x) (if x (make-null) (make-true)))

     (llvm-define (ensure x message) 
                  (cond ((not x) (display message) (exit 42))))
     
     (llvm-define (make-number x) (bit-or (bit-shl x 2) 2))
     (llvm-define (make-char x) (ensure (setlt x 256) "make-char: not ASCII or reached EOF") (make-number x))
     (llvm-define (raw-number x) (bit-shr x 2))

     (llvm-define (get-tag x) 
                    (cond 
                       ((number? x) 0)
                       ((null? x) 1)
                       (else (load (getelementptr x 0)))))

     

     (llvm-define (make-function-pointer x) 
                  x)

     (llvm-define (number? x) (seteq (bit-and x 3) 2))
     (llvm-define (vector? x) (seteq (get-tag x) 1))
     (llvm-define (function? x) (seteq (get-tag x) 3))
     (llvm-define (string? x) (seteq (get-tag x) 2))
     (llvm-define (symbol? x) (seteq (get-tag x) 4))
     (llvm-define (null? x) (seteq x 1))
     (llvm-define (make-null) 1)
     (llvm-define (make-true) (make-number 1))
     (llvm-define (pair? x) (if (vector? x) (seteq (vector-size x) 2) (make-null)))
    
     (llvm-define (init-vector! vector size)
                  (store 1    (getelementptr vector 0))
                  (store size (getelementptr vector 1))
                  vector)

     (llvm-define (make-vector raw-size)
                  ;(display "; make-vector:")
                  ;(print (string-bytes " %d\n") raw-size)
                  (init-vector! (malloc (add raw-size 2)) raw-size))
     
     (llvm-define (vector-size vector)
                  (load (getelementptr vector 1)))
     
     (llvm-define (vector-ref vector raw-index)
                  ;(display "; vector-ref:")
                  ;(print (string-bytes " %d") raw-index)
                  ;(print (string-bytes " %d\n") (vector-size vector))
                  (ensure (vector? vector) "vector-ref: not a vector.")
                  (ensure (not (null? vector)) "vector-ref: null vector")
                  (ensure (setlt raw-index (vector-size vector)) "vector-ref: out of range.")
                  (load (getelementptr vector (add raw-index 2))))

     (llvm-define (vector-set! vector raw-index value)
                  ;(display "; vector-set!:")
                  ;(print (string-bytes " %d") raw-index)
                  ;(print (string-bytes " %d\n") (vector-size vector))
                  (ensure (vector? vector) "vector-set!: not a vector.")
                  (ensure (not (null? vector)) "vector-set!: null vector")
                  (ensure (setlt raw-index (vector-size vector)) "vector-set!: out of range.")
                  (store value (getelementptr vector (add raw-index 2)))
                  vector)
    
     (llvm-define (set-enclosing-env! env enclosing-env) (vector-set! env 0 enclosing-env))
     (llvm-define (get-enclosing-env env) (vector-ref env 0))
      ; +2?: env + arbitrary arg for function called with nparams - 1.
     (llvm-define (make-env raw-nparams env) 
                  (set-enclosing-env! (make-vector (add raw-nparams 2)) env))
     
     (llvm-define (init-function! function raw-func env nparams)
                  (store 3        (getelementptr function 0))
                  (store raw-func (getelementptr function 1))
                  (store env      (getelementptr function 2))
                  (store nparams  (getelementptr function 3))
                  function)

     (llvm-define (make-function raw-func env nparams)
                  (init-function! (malloc 4) raw-func env nparams))
                   
     (llvm-define (get-function-func function)
                  (ensure (function? function) "get-function-func: not a function.")
                  (load (getelementptr function 1)))
     (llvm-define (get-function-env function)
                  (ensure (function? function) "get-function-env: not a function.")
                  (load (getelementptr function 2)))
     (llvm-define (get-function-nparams function)
                  (ensure (function? function) "get-function-nparams: not a function.")
                  (load (getelementptr function 3)))
     
     (llvm-define (fix-arb-funcs n-params end call-env)
                  (cond ((setge n-params end) (make-null))
                        (else (cons (vector-ref call-env n-params)
                                    (fix-arb-funcs (add n-params 1) end call-env)))))
     (llvm-define (fix-arbitrary-funcs n-params call-env)
                  (if (seteq n-params 0) 1
                      (vector-set! 
                       call-env n-params 
                       (fix-arb-funcs n-params (sub (vector-size call-env) 1) call-env))))
                       
     (llvm-define (init-string str raw-str size)
                  (store 2         (getelementptr str 0))
                  (store raw-str   (getelementptr str 1))
                  (store size      (getelementptr str 2))
                  str)
     
     (llvm-define (make-string raw-str raw-size)
                  (init-string (malloc 3) raw-str (make-number raw-size)))
     
     (llvm-define (init-symbol str raw-str size)
                  (store 4         (getelementptr str 0))
                  (store raw-str   (getelementptr str 1))
                  (store size      (getelementptr str 2))
                  str)
     
     (llvm-define (make-symbol raw-str raw-size)
                  (init-symbol (malloc 3) raw-str (make-number raw-size)))
     
     (llvm-define (string-length str)
                  (load (getelementptr str 2)))
     (llvm-define (string-bytes str)
                  (load (getelementptr str 1)))
     
     (llvm-define (string->symbol str)
                  (ensure (string? str) "string->symbol: not a string")
                  (make-symbol (string-bytes str) (raw-number (string-length str))))
     (llvm-define (symbol->string str)
                  (ensure (symbol? str) "symbol->string: not a symbol")
                  (make-string (string-bytes str) (raw-number (string-length str))))
     
     (llvm-define (list->string-helper lst len str-bytes)
                  (cond ((null? lst)
                         (make-string (append-bytearray str-bytes 0 len) len))
                        (else (ensure (number? (car lst)) 
                                      "list->string: list element is not a number") 
                              (list->string-helper 
                               (cdr lst) (add len 1)
                               (append-bytearray str-bytes (raw-number (car lst)) len)))))
     (llvm-define (list->string lst)
                  (ensure (vector? lst) "list->string: not a list")
                  (list->string-helper lst 0 0))
     
     (llvm-define (string->list-helper bytearray pos end)
                  (cond ((seteq pos end) '())
                        (else (cons (make-number (bytearray-ref bytearray pos))
                                    (string->list-helper bytearray (add pos 1) end)))))
     (llvm-define (string->list str)
                  (ensure (string? str) "string->list: not a string")
                  (string->list-helper (string-bytes str) 0 (raw-number (string-length str))))
     
     (llvm-define (string-ref str pos)
                  (ensure (string? str) "string-ref: not a string")
                  (ensure (number? pos) "string-ref: pos not a number")
                  (ensure (setlt pos (string-length str)) "string-ref: out of range")
                  (make-number (bytearray-ref (string-bytes str) (raw-number pos))))
     (llvm-define (char->integer ch) ch)
     (llvm-define (integer->char ch) ch)
     
     
     (llvm-define (lookup-variable env scope index)
                  (if (seteq 0 scope)
                      (vector-ref env index)
                      (lookup-variable (vector-ref env 0)
                                       (sub scope 1)
                                       index)))
     
     (llvm-define (set-variable! env scope index value)
                  (if (seteq 0 scope)
                      (vector-set! env index value)
                      (set-variable! (vector-ref env 0)
                                     (sub scope 1)
                                     index value)))
                                    
     (llvm-define (cons x y) (vector-set! (vector-set! (make-vector 2) 0 x) 1 y))
     (llvm-define (car cell) (vector-ref cell 0))
     (llvm-define (cdr cell) (vector-ref cell 1))
     (llvm-define (cddr x) (cdr (cdr x)))
     (llvm-define (cdddr x) (cdr (cdr (cdr x))))
     (llvm-define (cadr x) (car (cdr x)))
     (llvm-define (cdadr x) (cdr (car (cdr x))))
     (llvm-define (caadr x) (car (car (cdr x))))
     (llvm-define (caddr x) (car (cdr (cdr x))))
     (llvm-define (cadddr x) (car (cdr (cdr (cdr x)))))
     
     (llvm-define (* x y)
                  (ensure (number? x) "*: first argument is not a number.")
                  (ensure (number? y) "*: second argument is not a number.")
                  (make-number (mul (raw-number x) (raw-number y))))

     (llvm-define (- x y)
                  (ensure (number? x) "-: first argument is not a number.")
                  (ensure (number? y) "-: second argument is not a number.")
                  (make-number (sub (raw-number x) (raw-number y))))
     
     (llvm-define (+ x y)
                  (ensure (number? x) "+: first argument is not a number.")
                  (ensure (number? y) "+: second argument is not a number.")
                  (make-number (add (raw-number x) (raw-number y))))

     (llvm-define (/ x y)
                  (ensure (number? x) "/: first argument is not a number.")
                  (ensure (number? y) "/: second argument is not a number.")
                  (make-number (div (raw-number x) (raw-number y))))
     
     (llvm-define (% x y)
                  (ensure (number? x) "%: first argument is not a number.")
                  (ensure (number? y) "%: second argument is not a number.")
                  (make-number (rem (raw-number x) (raw-number y))))

     (llvm-define (= x y)
                  (cond ((and (number? x) (number? y))
                         (seteq (raw-number x) (raw-number y)))
                        (else (ensure 0 "=: nonapplicable types."))))
     (llvm-define (> x y)
                  (cond ((and (number? x) (number? y))
                         (setgt (raw-number x) (raw-number y)))
                        (else (ensure 0 ">: nonapplicable types."))))
                                                                        
     (llvm-define (display x)
                  (cond ((number? x) (print (string-bytes "%d")
                                            (raw-number x)))
                        ((string? x) (print (string-bytes "%s")
                                            (string-bytes x)))
                        ((symbol? x) (print (string-bytes "'%s")
                                            (string-bytes x)))
                        ((null? x) (print (string-bytes "nil") 0))
                        ((pair? x) (print (string-bytes "(") 0)
                                   (display (car x))
                                   (print (string-bytes " . ") 0)
                                   (display (cdr x))
                                   (print (string-bytes ")") 0))
                        (else (ensure (make-null) "display: nonapplicable type.")))
                  x)
     (define (newline) (display (list->string (cons 10 '()))))
     
     (define (string/symbol-data-eq? x y pos len)
       (cond ((= pos len) 1)
             ((seteq (bytearray-ref (string-bytes x) (raw-number pos))
                     (bytearray-ref (string-bytes y) (raw-number pos)))
              (string/symbol-data-eq? x y (+ pos 1) len))
             (else '())))

     (define (eq? x y)
       (cond ((and (number? x) (number? y)) (= x y))
             ((and (string? x) (string? y))
              (if (= (string-length x) (string-length y))
                  (string/symbol-data-eq? x y 0 (string-length x)) '()))
             ((and (symbol? x) (symbol? y))
              (if (= (string-length x) (string-length y))
                  (string/symbol-data-eq? x y 0 (string-length x)) '()))
             (else (seteq x y))))
          
     (define (member el lst)
       (cond ((null? lst) '())
             ((eq? el (car lst)) 1)
             (else (member el (cdr lst)))))
     
     (define (length lst)
       (cond ((null? lst) 0)
             (else (+ 1 (length (cdr lst))))))
     
     (define (nth lst el)
       (cond ((null? lst) '())
             ((= el 0) (car lst))
             (else (nth (cdr lst) (- el 1)))))
     
     (define (map fn lst)
       (cond ((null? lst) '())
             (else (cons (fn (car lst)) (map fn (cdr lst))))))

     (define (append l1 l2)
       (cond ((null? l1) l2)
             (else (cons (car l1) (append (cdr l1) l2)))))
     
     (define (reverse lst)
       (if (null? lst) lst
           (append (reverse (cdr lst)) (list (car lst)))))
     
     (define (number->string n)
       (define (nmb-str n res)
         (if (> n 9) 
             (nmb-str (/ n 10) (cons (nth number-chars (% n 10)) res))
             (cons (nth number-chars n) res)))
       (list->string (nmb-str n '())))
     
     (define (list? x)
       (cond ((null? x) 1)
             ((pair? x) (list? (cdr x)))
             (else '())))
     (define list (lambda x x))
     
     (define (assoc x lst)
       (cond ((null? lst) '())
             ((eq? x (car (car lst))) (car lst))
             (else (assoc x (cdr lst)))))
     
     (define (string-append str1 str2)
       (list->string (append (string->list str1) (string->list str2))))
     
     (define read-char-peek '())
     (define (peek-char)
       (cond ((null? read-char-peek)
              (set! read-char-peek (make-char (llvm-read-char)))
              read-char-peek)
             (else read-char-peek)))
     (define (read-char)
       (define peek read-char-peek)
       (cond ((null? peek) (make-char (llvm-read-char)))
             (else (set! read-char-peek '())
                   peek)))
     
     (define number-chars (quote (48 49 50 51 52 53 54 55 56 57)))
     (define (char-whitespace? ch) (or (eq? ch 32) (or (eq? ch 10) (eq? ch 9))))
     (define (char-numeric? ch) (member ch number-chars))
     (define (char-left-paren? ch) (eq? ch 40))
     (define (char-right-paren? ch) (eq? ch 41))
     (define (char-comment? ch) (eq? ch 59))
     (define (char-string? ch) (eq? ch 34))
     (define (char-newline? ch) (eq? ch 10))
     (define (char-dot? ch) (eq? ch 46))
     (define (char-quote? ch) (eq? ch 39))
     (define (char-backquote? ch) (eq? ch 96))
     (define (char-comma? ch) (eq? ch 44))
     (define (char-backslash? ch) (eq? ch 92))
     (define (char-character? ch) (eq? ch 35))
     (define identifier-end '(40 41 32 10))
     
     (define (read)
       (define ch (read-char))
       (cond ((char-left-paren? ch) (read-list))
             ((char-whitespace? ch) (read))
             ((char-comment? ch) (read-comment) (read))
             ((char-quote? ch) (cons 'quote (cons (read) '())))
             ((char-string? ch) (read-string))
             ((char-character? ch) (read-char-quote))
             ((char-numeric? ch) (read-number ch))
             (else (read-identifier ch))))
     
     (define (read-char-quote)
       (read-char) (read-char))
     
     (define (read-comment)
       (if (not (char-newline? (read-char)))
           (read-comment)))
     
     (define (read-list)
       (define ch (read-char))
       (cond ((char-right-paren? ch) '())
             ((char-dot? ch) (car (read-list)))
             ((char-left-paren? ch) (cons (read-list)  (read-list)))
             ((char-whitespace? ch) (read-list))
             ((char-comment? ch) (read-comment) (read-list))
             ((char-quote? ch) (cons (cons 'quote (cons (read) '())) (read-list)))
             ((char-string? ch) (cons (read-string) (read-list)))
             ((char-character? ch) (read-char-quote))
             ((char-numeric? ch) (cons (read-number ch) (read-list)))
             (else (cons (read-identifier ch) (read-list)))))
     
     (define (char-list->number lst res)
       (define (nmemb x lst pos)
         (if (= x (car lst)) pos (nmemb x (cdr lst) (+ pos 1))))
       (if (null? lst) res
           (char-list->number 
            (cdr lst) (+ (* res 10)
                         (nmemb (car lst) number-chars 0)))))
        
     (define (read-number ch)
       (define (read-nmb)
         (define peek (peek-char))
         (if (char-numeric? peek) 
             (cons (read-char) (read-nmb)) '()))
       (char-list->number (cons ch (read-nmb)) 0))
     
     (define (read-identifier ch)
       (define (read-id)
         (if (member (peek-char) identifier-end) '()
             (cons (read-char) (read-id))))
       (string->symbol (list->string (cons ch (read-id)))))
    
     (define (interpret-escape ch)
        (cond ((eq? ch 110) 10) ;\n is newline
              ((eq? ch 116) 9)  ;\t is tab
              (else ch)))

     (define (read-string)
       (define (read-str)
         (define ch (read-char))
         (cond ((char-backslash? ch) (cons (interpret-escape (read-char)) (read-str)))           
               ((char-string? ch) '())
               (else (cons ch (read-str)))))
       (list->string (read-str)))
  ))

(define (compiler exp)
  (init-generators)
  (let ((printer (lambda (line) (display line) (newline)))
        (result (compile (append bootstrap exp) '())))
    (map printer llvm-string-list)
    (display bootstrap-llvm-code)
    (display "define fastcc i64 @startup(i64 %\"env\") {\n")
    (map printer (compiled-code result))
    (display (c "ret i64 " (compiled-target result) "\n}\n"))
    (display "; FUNCTIONS\n")
    (map (lambda (function) (map printer function) (newline))
         llvm-function-list))
  0)

(compiler (list (read)))


)
