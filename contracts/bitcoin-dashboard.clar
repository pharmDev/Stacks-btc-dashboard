;; bitcoin-dashboard
;; Contract for managing bitcoin expenses with budget tracking and workflow

;; constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-insufficient-funds (err u102))
(define-constant err-invalid-status (err u105))
(define-constant err-budget-exceeded (err u106))
(define-constant err-invalid-amount (err u107))
(define-constant err-invalid-date (err u108))

;; expense status constants
(define-constant status-pending u1)
(define-constant status-approved u2)
(define-constant status-rejected u3)
(define-constant status-paid u4)
(define-constant status-cancelled u5)

;; data maps and vars
(define-map expenses 
  { expense-id: uint } 
  { 
    description: (string-ascii 256),
    amount: uint,
    status: uint,
    recipient: principal,
    category-id: uint,
    created-by: principal,
    created-at: uint,
    last-modified: uint,
    approver: (optional principal),
    payment-tx: (optional (string-ascii 64)),
    notes: (string-ascii 512)
  }
)

(define-map expense-categories
  { category-id: uint }
  {
    name: (string-ascii 64),
    budget: uint,
    active: bool
  }
)

(define-map category-spending
  { category-id: uint, year: uint, month: uint }
  { total-spent: uint }
)

(define-map monthly-budgets
  { year: uint, month: uint }
  { budget-amount: uint }
)

(define-data-var expense-counter uint u0)
(define-data-var category-counter uint u0)
(define-data-var total-balance uint u0)
(define-data-var total-expenses-paid uint u0)
(define-data-var total-expenses-pending uint u0)

;; private functions
;;

;; public functions
;;
