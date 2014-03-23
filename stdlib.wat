(def quote (--vau (x) ignore x))
(def list (wrap (--vau arglist ignore arglist)))
(def string (--vau (sym) ignore (symbol-name sym)))
(def get-current-environment (--vau () e e))

(def make-macro-expander
 (wrap
  (--vau (expander) ignore
   (--vau operands env
    (eval (eval (cons expander operands) (make-environment)) env)))))

(def vau
 (make-macro-expander
  (--vau (params env-param &rest body) ignore
   (list --vau params env-param (cons begin body)))))

(def macro
 (make-macro-expander
  (vau (params &rest body) ignore
   (list make-macro-expander (list* vau params ignore body)))))

(def lambda
 (macro (params &rest body)
  (list wrap (list* vau params ignore body))))
(def loop
 (macro body
  (list --loop (list* begin body))))
(def catch
 (macro (protected handler)
  (list --catch (list lambda () protected) handler)))

(def push-prompt
 (vau (prompt &rest body) e
  (eval (list --push-prompt (eval prompt e) (list* begin body)) e)))
(def take-subcont
 (macro (prompt k &rest body)
  (list --take-subcont prompt (list* lambda (list k) body))))
(def push-subcont
 (macro (k &rest body)
  (list --push-subcont k (list* lambda () body))))

(def dlet
 (vau (dv val &rest body) e
  (eval (cons --dlet (list (eval dv e) (eval val e) (list* begin body)))
   e)))


(def array (lambda args (list-to-array args)))

(def define-js-unop
 (macro (op)
  (list def op (list js-unop (list string op)))))

(define-js-unop !)
(define-js-unop typeof)
(define-js-unop ~)

(def define-js-binop
 (macro (op)
  (list def op (list js-binop (list string op)))))

(define-js-binop !=)
(define-js-binop !==)
(define-js-binop %)
(define-js-binop &)
(define-js-binop *)
(define-js-binop +)
(define-js-binop -)
(define-js-binop /)
(define-js-binop <)
(define-js-binop <<)
(define-js-binop <=)
(define-js-binop ==)
(define-js-binop ===)
(define-js-binop >)
(define-js-binop >>)
(define-js-binop >>>)
(define-js-binop ^)
(define-js-binop in)
(define-js-binop instanceof)
(define-js-binop |)


(def compose
 (lambda (f g) (lambda (arg) (f (g arg)))))

(def car (lambda ((x &rest ignore)) x))
(def cdr (lambda ((ignore &rest x)) x))
(def caar (compose car car))
(def cadr (compose car cdr))
(def cdar (compose cdr car))
(def cddr (compose cdr cdr))

(def define-macro
 (macro ((name &rest params) &rest body)
  (list def name (list* macro params body))))

(define-macro (define lhs &rest rhs)
 (if (cons? lhs)
  (list def (car lhs) (list* lambda (cdr lhs) rhs))
  (list def lhs (car rhs))))

(define (map-list f lst)
  (if (nil? lst)
   ()
   (cons (f (car lst)) (map-list f (cdr lst)))))

(define-macro (let bindings &rest body)
 (cons
  (list* lambda (map-list car bindings) body)
  (map-list cadr bindings)))

(define-macro (let* bindings &rest body)
 (if (nil? bindings)
  (list* let () body)
  (list let (list (car bindings))
   (list* let* (cdr bindings) body))))

(define-macro (defun (name &rest params) &rest body)
 (list def name (list* typed-lambda params body)))

(def typed-lambda
 (macro (params &rest body)
  (let (((vau-list typed-body) (xform-typed-lambda params body)))
   (list wrap (list* vau vau-list ignore typed-body)))))

(define-macro (the type obj)
 (list --type-check (symbol-name type) type obj))

(def Arguments $Arguments)
(def Array $Array)
(def Date $Date)
(def Function $Function)
(def Number $Number)
(def Object $Object)
(def RegExp $RegExp)
(def String $String)

(define (call-with-escape fun)
 (let ((fresh (list null)))
  (catch (fun (lambda opt-arg (throw (list fresh opt-arg))))
   (lambda (exc)
    (if (&& (cons? exc) (=== fresh (car exc)))
     (let ((opt-arg (cadr exc)))
      (if (cons? opt-arg) (car opt-arg) ())) ; return null?
     (throw exc))))))

(define-macro (label name &rest body)
 (list call-with-escape (list* lambda (list name) body)))

(define (call-while test-fun body-fun)
 (label return
  (loop
   (if (test-fun)
    (body-fun)
    (return null)))))

(define-macro (while test &rest body)
 (list call-while
  (list lambda () test)
  (list* lambda () body)))

(define-macro (when test &rest body)
 (list if test (list* begin body) null))

(define-macro (unless test &rest body)
 (list* when (list ! test) body))

(define-macro (&& a b)
 (list if a b false))

(define-macro (|| a b)
 (list if a true b))

(define-macro (= name value)
 (list --set! name value))

(define (cat &rest objects)
 (#join (list-to-array objects) ""))

(define (log &rest objects)
 (apply #log (list* $console objects)))

(define (--print-stacktrace-and-throw err)
 (define (print-frame k)
  (#log $console (#toString (.dbg k)) (.e k))
  (if (.next k)
   (print-frame (.next k))
   null))
 (take-subcont (--get-root-prompt) k
  (print-frame k)
  (push-prompt (--get-root-prompt)
   (push-subcont k
    (throw err)))))

(define object
 (vau pairs e
  (let ((obj (--make-object)))
   (map-list
    (lambda (pair)
     (let ((name (eval (car pair) e))
     (value (eval (cadr pair) e)))
      ((js-setter name) obj value)))
    pairs)
   obj)))

(define-macro (define-prototype name prop-names)
 (list define name
  (list* --make-prototype (symbol-name name)
   (map-list symbol-name prop-names))))

(define (--put-method ctor name js-fun)
 ((js-setter name) (.prototype ctor) js-fun))

(define-macro (define-method (name (self ctor) &rest args) &rest body)
  (list --put-method ctor (symbol-name name)
   (list js-function (list* typed-lambda (list* self args) body))))

(define-macro (define-generic (name &rest ignore))
 (list define name
  (lambda args
   (apply (js-invoker (symbol-name name)) args))))

(define (@ object key)
 ((js-getter key) object))

(define (js-callback fun)
 (js-function (lambda args (push-prompt (--get-root-prompt) (apply fun args)))))

(define (map-array f arr)
 (let* ((i 0) (len (.length arr)) (res (array)))
  (while (< i len)
   (#push res (f (@ arr i)))
   (= i (+ i 1)))
  res))

(define provide
  (vau (symbolz &rest body) env
    (eval (list def symbolz
   (list let ()
     (list* begin body)
     (list* list symbolz)))
 env)))

(define module
  (vau (exports &rest body) e
    (let ((env (make-environment e)))
      (eval (list* provide exports body) env)
      env)))

(define define-module
  (vau (name exports &rest body) e
    (eval (list define name (list* module exports body)) e)))

(define import
  (vau (module imports) e
    (let* ((m (eval module e))
  (values (map-list (lambda (import) (eval import m)) imports)))
      (eval (list def imports (list* list values))
   e))))

