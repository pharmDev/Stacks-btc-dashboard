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
(define-public (add-funds (amount uint))
  (begin
    (asserts! (> amount u0) err-invalid-amount)
    (var-set total-balance (+ (var-get total-balance) amount))
    (ok (var-get total-balance))
  )
)

(define-public (add-expense (description (string-ascii 256)) (amount uint) (recipient principal) (category-id uint) (notes (string-ascii 512)))
  (let (
    (expense-id (var-get expense-counter))
    (current-time (get-current-time))
    (category (map-get? expense-categories { category-id: category-id }))
  )
    (begin
      (asserts! (is-owner) err-owner-only)
      (asserts! (> amount u0) err-invalid-amount)
      (asserts! (not (is-none category)) err-not-found)
      (asserts! (get active (unwrap! category err-not-found)) err-not-found)
      
      (map-set expenses 
        { expense-id: expense-id } 
        { 
          description: description, 
          amount: amount, 
          status: status-pending, 
          recipient: recipient,
          category-id: category-id,
          created-by: tx-sender,
          created-at: current-time,
          last-modified: current-time,
          approver: none,
          payment-tx: none,
          notes: notes
        }
      )
      (var-set expense-counter (+ expense-id u1))
      (var-set total-expenses-pending (+ (var-get total-expenses-pending) amount))
      (ok expense-id)
    )
  )
)

(define-public (approve-expense (expense-id uint))
  (let (
    (expense (unwrap! (map-get? expenses { expense-id: expense-id }) err-not-found))
    (current-time (get-current-time))
  )
    (begin
      (asserts! (is-owner) err-owner-only)
      (asserts! (is-eq (get status expense) status-pending) err-invalid-status)
      (asserts! (check-category-budget (get category-id expense) (get amount expense)) err-budget-exceeded)
      
      (map-set expenses 
        { expense-id: expense-id }
        (merge expense { 
          status: status-approved,
          approver: (some tx-sender),
          last-modified: current-time
        })
      )
      (ok true)
    )
  )
)

(define-public (reject-expense (expense-id uint) (rejection-note (string-ascii 512)))
  (let (
    (expense (unwrap! (map-get? expenses { expense-id: expense-id }) err-not-found))
    (current-time (get-current-time))
  )
    (begin
      (asserts! (is-owner) err-owner-only)
      (asserts! (is-eq (get status expense) status-pending) err-invalid-status)
      
      (map-set expenses 
        { expense-id: expense-id }
        (merge expense { 
          status: status-rejected,
          approver: (some tx-sender),
          last-modified: current-time,
          notes: rejection-note
        })
      )
      (var-set total-expenses-pending (- (var-get total-expenses-pending) (get amount expense)))
      (ok true)
    )
  )
)

(define-public (pay-expense (expense-id uint) (payment-tx (string-ascii 64)))
  (let (
    (expense (unwrap! (map-get? expenses { expense-id: expense-id }) err-not-found))
    (current-balance (var-get total-balance))
    (current-time (get-current-time))
  )
    (begin
      (asserts! (is-owner) err-owner-only)
      (asserts! (is-eq (get status expense) status-approved) err-invalid-status)
      (asserts! (>= current-balance (get amount expense)) err-insufficient-funds)
      
      (map-set expenses 
        { expense-id: expense-id }
        (merge expense { 
          status: status-paid,
          last-modified: current-time,
          payment-tx: (some payment-tx)
        })
      )
      (var-set total-balance (- current-balance (get amount expense)))
      (var-set total-expenses-paid (+ (var-get total-expenses-paid) (get amount expense)))
      (var-set total-expenses-pending (- (var-get total-expenses-pending) (get amount expense)))
      (update-category-spending (get category-id expense) (get amount expense))
      (as-contract (stx-transfer? (get amount expense) tx-sender (get recipient expense)))
    )
  )
)

(define-public (cancel-expense (expense-id uint))
  (let (
    (expense (unwrap! (map-get? expenses { expense-id: expense-id }) err-not-found))
    (current-time (get-current-time))
  )
    (begin
      (asserts! (or (is-owner) (is-eq tx-sender (get created-by expense))) err-owner-only)
      (asserts! (or (is-eq (get status expense) status-pending) (is-eq (get status expense) status-approved)) err-invalid-status)
      
      (map-set expenses 
        { expense-id: expense-id }
        (merge expense { 
          status: status-cancelled,
          last-modified: current-time
        })
      )
      (var-set total-expenses-pending (- (var-get total-expenses-pending) (get amount expense)))
      (ok true)
    )
  )
)

(define-public (add-category (name (string-ascii 64)) (budget uint))
  (let (
    (category-id (var-get category-counter))
  )
    (begin
      (asserts! (is-owner) err-owner-only)
      (var-set category-counter (+ category-id u1))
      (map-set expense-categories
        { category-id: category-id }
        {
          name: name,
          budget: budget,
          active: true
        }
      )
      (ok category-id)
    )
  )
)

;; read-only functions
(define-read-only (get-expense (expense-id uint))
  (map-get? expenses { expense-id: expense-id })
)

(define-read-only (get-category (category-id uint))
  (map-get? expense-categories { category-id: category-id })
)

(define-read-only (get-balance)
  (var-get total-balance)
)

(define-read-only (get-total-expenses-paid)
  (var-get total-expenses-paid)
)

(define-read-only (get-total-expenses-pending)
  (var-get total-expenses-pending)
)

(define-read-only (get-expenses-by-status (status uint))
  (map-filter (is-eq (get status (unwrap! (map-get? expenses { expense-id: it } err-not-found)))) { expense-id: it } expenses)
)

(define-read-only (get-category-spending (category-id uint) (year uint) (month uint))
  (let (
    (spending (default-to { total-spent: u0 } 
      (map-get? category-spending { category-id: category-id, year: year, month: month })))
  )
    (ok (get total-spent spending))
  )
)

(define-read-only (get-monthly-budget (year uint) (month uint))
  (let (
    (budget (default-to { budget-amount: u0 } 
      (map-get? monthly-budgets { year: year, month: month })))
  )
    (ok (get budget-amount budget))
  )
)

(define-read-only (get-category-expenses (category-id uint))
  (map-filter (is-eq (get category-id (unwrap! (map-get? expenses { expense-id: it } err-not-found)))) { expense-id: it } expenses)
)

(define-read-only (get-all-expenses)
  (ok (map-values expenses))
)

(define-read-only (get-all-categories)
  (ok (map-values expense-categories))
)
