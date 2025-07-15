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
(define-private (is-owner)
  (is-eq tx-sender contract-owner)
)

(define-private (get-current-time)
  block-height
)

(define-private (get-year-month (timestamp uint))
  (let (
    (year u2023) ;; Simplified - in production would calculate from block height
    (month u1)   ;; Simplified - in production would calculate from block height
  )
    { year: year, month: month }
  )
)

(define-private (update-category-spending (category-id uint) (amount uint))
  (let (
    (time-data (get-year-month (get-current-time)))
    (year (get year time-data))
    (month (get month time-data))
    (current-spending (default-to { total-spent: u0 } 
      (map-get? category-spending { category-id: category-id, year: year, month: month })))
    (new-total (+ (get total-spent current-spending) amount))
  )
    (map-set category-spending
      { category-id: category-id, year: year, month: month }
      { total-spent: new-total }
    )
    new-total
  )
)

(define-private (check-category-budget (category-id uint) (amount uint))
  (let (
    (category (unwrap! (map-get? expense-categories { category-id: category-id }) false))
    (time-data (get-year-month (get-current-time)))
    (year (get year time-data))
    (month (get month time-data))
    (current-spending (default-to { total-spent: u0 } 
      (map-get? category-spending { category-id: category-id, year: year, month: month })))
    (budget (get budget category))
    (projected-spending (+ (get total-spent current-spending) amount))
  )
    (<= projected-spending budget)
  )
)

;; public functions
;;
