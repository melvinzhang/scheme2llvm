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
;; All objects are represented with a 32 bit uint, with 2 bits reserved 
;; for a type tag.
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

(define (llvm-malloc? exp) (tagged-list? exp 'malloc))
(define (llvm-load? exp) (tagged-list? exp 'load))
(define (llvm-store? exp) (tagged-list? exp 'store))
(define (llvm-getelementptr? exp) (tagged-list? exp 'getelementptr))
(define (llvm-cast? exp) (tagged-list? exp 'cast))
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
        '(llvm-read-char print append-bytearray bytearray-ref exit))
  (set! llvm-string-list '()))

(define var-counter 0)
(define (make-var)
  (set! var-counter (+ 1 var-counter))
  (c "%r" (number->string var-counter)))

(define label-counter 0)
(define (make-label)
  (set! label-counter (+ 1 label-counter))
  (c "label" (number->string label-counter)))

(define function-counter 0)
(define (make-function-name)
  (set! function-counter (+ 1 function-counter))
  (c "%function" (number->string function-counter)))

(define llvm-primitive-functions '())
(define (add-llvm-function-name f-name)
  (set! llvm-primitive-functions (cons f-name llvm-primitive-functions)))

(define llvm-function-list '())
(define (add-llvm-function f-name f-params f-body)
  (define (build-params params)
    (if (null? params) ""
        (c "uint " (llvm-repr (car params))
           (if (null? (cdr params)) "" ", ")
           (build-params (cdr params)))))
  (set! llvm-function-list
	(append 
         llvm-function-list
         (list (append-code 
               (c "uint " (llvm-repr f-name) "(" (build-params f-params) ") {")
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
  (let ((str-type (c "[" (llvm-repr (+ (string-length str) 1)) " x sbyte]")))
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
    (add . "add") (sub . "sub") (mul . "mul") (div . "div") (rem . "rem")    
    ;; binary bit operations.
    (bit-and . "and") (bit-or . "or") (bit-xor . "xor") 
    (bit-shl . "shl") (bit-shr . "shr")
    ;; boolean operations.
    (seteq . "seteq") (setne . "setne") (setlt . "setlt") (setgt . "setgt")
    (setle . "setle") (setge . "setge")
    ;; memory operations.
    (malloc . 0) (getelementptr . 0)
    (cast . 0) (load . 0) (store . 0)
    (ret . 0)))

(define llvm-boolean-instructions '(seteq setne setlt setgt setle setge))
(define llvm-shift-instructions '(bit-shl bit-shr))
(define (llvm-instr-name op) (cdr (assoc op llvm-instructions)))

(define (llvm-repr exp)
  (cond ((number? exp) (number->string exp))
        ((symbol? exp) (c "\"%" (symbol->string exp) "\""))
        (else exp)))

(define (llvm-instruction target op x y)
  (c target " = " (llvm-instr-name op) " uint " 
     (llvm-repr x) ", " (llvm-repr y)))

(define (llvm-id target exp) ; Identity function
  (llvm-instruction target 'add 0 exp))

(define (llvm-call2 target function args)
  (define (build-arg-list arg-list fi)
    (if (null? arg-list) ""
        (c (if (= fi 1) "" ", ")
           (c "uint " (llvm-repr (car arg-list)))
           (build-arg-list (cdr arg-list) 0))))
  (c target " = call uint " (llvm-repr function) "(" (build-arg-list args 1) ")"))
(define (llvm-call target function . args)
  (llvm-call2 target function args))

(define (llvm-ret value) (c "ret uint " (llvm-repr value)))

(define (llvm-cast target type1 x type2)
  (c target " = cast " type1 " " x " to " type2))

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
     (llvm-cast t2 "uint" t1 "bool")
     (c "br bool " t2 ", label %" c-label ", label %" a-label))))

(define (llvm-malloc target size)
  (c target " = call uint* \"%malloc\"(uint " (llvm-repr size) ")"))

(define (llvm-store target value) 
  (c "store uint " value ", uint* " target))

(define (llvm-load target var) (c target " = load uint* " var))
(define (llvm-alloca-var target) (c target " = alloca uint"))

(define (llvm-shift-op target op value sh)
  (let ((t1 (make-var)))
    (append-code 
     (llvm-cast t1 "uint" sh "ubyte")
     (c target " = " (llvm-instr-name op)
	" uint " (llvm-repr value) ", ubyte " t1))))

(define (llvm-getelementptr target ptr index)
  (c target " = getelementptr uint* " ptr ", uint " index))

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
  
  (block-comment "compile" exp)

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
               ((or (string? exp) (symbol? exp))
                (let ((str (make-var))
                      (t1 (make-var))
                      (symbolp (if (symbol? exp) 4 1))
                      (str-repr (if (string? exp) exp (symbol->string exp))))
                  (append-code
                   (llvm-cast t1 (add-llvm-string str str-repr) str "uint")
                   (llvm-call target 'make-string/symbol t1 
                              (string-length str-repr) symbolp))))
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
        (value (compile (definition-value exp) c-t-env)))
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

(define (compile-lambda exp c-t-env)
  (let ((f-name (make-function-name))
        (t1 (make-var))
        (target (make-var))
        (l-body 
         (compile-sequence (lambda-body exp)
                           (extend-c-t-env (lambda-parameters exp) c-t-env))))
    (add-llvm-function f-name '(env) l-body)
    (make-code 
     target 
     (llvm-cast t1 "uint (uint)*" f-name "uint")
     (llvm-call target 'make-function t1 'env 
                (if (lambda-arbitrary-args? exp)
                    (length (lambda-parameters exp))
                    0)))))

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
    (cond ((llvm-malloc? exp) 
	   (let ((size (compile (first-arg exp) c-t-env)))
	     (make-code target (compiled-code size)
                        (llvm-malloc target (compiled-target size)))))
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
	  ((llvm-cast? exp)
	   (let ((value (compile (second-arg exp) c-t-env)))
	     (make-code target (compiled-code value)
			(llvm-cast target (first-arg exp) 
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
			(llvm-instruction 
                         t1 (operator exp) 
                         (compiled-target x) (compiled-target y))
			(llvm-cast t2 "bool" t1 "uint")
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
         (llvm-cast func "uint" f-func "uint (uint)*")
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
)
