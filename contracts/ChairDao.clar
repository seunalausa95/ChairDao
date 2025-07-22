;; ChairDAO - Decentralized Salon Booking Platform
;; A blockchain-based system for salon chair reservations and reputation management

;; Constants
(define-constant contract-owner tx-sender)
(define-constant min-stake-amount u100000000) ;; 100 STX minimum stake
(define-constant booking-fee-percent u5) ;; 5% booking fee
(define-constant max-rating u5) ;; Maximum rating (5 stars)
(define-constant max-date u99991231) ;; Maximum valid date YYYYMMDD
(define-constant min-date u20240101) ;; Minimum valid date YYYYMMDD
(define-constant max-time u2359) ;; Maximum valid time HHMM
(define-constant max-duration u480) ;; Maximum duration 8 hours in minutes
(define-constant max-price u100000000) ;; Maximum price 100 STX

;; Error codes
(define-constant err-owner-only (err u100))
(define-constant err-already-registered (err u101))
(define-constant err-not-registered (err u102))
(define-constant err-insufficient-stake (err u103))
(define-constant err-slot-unavailable (err u104))
(define-constant err-not-booked (err u105))
(define-constant err-already-rated (err u106))
(define-constant err-invalid-rating (err u107))
(define-constant err-unauthorized (err u108))
(define-constant err-invalid-amount (err u109))
(define-constant err-slot-in-past (err u110))
(define-constant err-invalid-date (err u111))
(define-constant err-invalid-time (err u112))
(define-constant err-invalid-duration (err u113))
(define-constant err-invalid-price (err u114))

;; Data variables
(define-data-var dao-treasury uint u0)
(define-data-var next-slot-id uint u1)
(define-data-var next-booking-id uint u1)

;; Data maps
(define-map stylists principal 
  {
    name: (string-ascii 50),
    stake-amount: uint,
    reputation-sum: uint,
    rating-count: uint,
    active: bool,
    registration-height: uint
  }
)

(define-map time-slots uint 
  {
    stylist: principal,
    date: uint,  ;; YYYYMMDD format
    time: uint,  ;; HHMM format (24hr)
    duration: uint, ;; in minutes
    price: uint,
    booked: bool
  }
)

(define-map bookings uint 
  {
    slot-id: uint,
    customer: principal,
    paid-amount: uint,
    rated: bool,
    rating: uint,
    booking-height: uint
  }
)

(define-map stylist-slots {stylist: principal, date: uint} (list 20 uint))
(define-map customer-bookings principal (list 20 uint))

;; Input validation functions
(define-private (is-valid-name (name (string-ascii 50)))
  (and (> (len name) u0) (<= (len name) u50)))

(define-private (is-valid-date (date uint))
  (and (>= date min-date) (<= date max-date)))

(define-private (is-valid-time (time uint))
  (<= time max-time))

(define-private (is-valid-duration (duration uint))
  (and (> duration u0) (<= duration max-duration)))

(define-private (is-valid-price (price uint))
  (and (> price u0) (<= price max-price)))

;; Stylist registration and management

;; Register as a stylist with a stake
(define-public (register-stylist (name (string-ascii 50)))
  (let ((stake-amount (stx-get-balance tx-sender))
        (validated-name name))
    (begin
      (asserts! (is-valid-name validated-name) err-invalid-amount)
      (asserts! (>= stake-amount min-stake-amount) err-insufficient-stake)
      (asserts! (is-none (map-get? stylists tx-sender)) err-already-registered)

      ;; Transfer stake to contract
      (try! (stx-transfer? min-stake-amount tx-sender (as-contract tx-sender)))

      ;; Register stylist
      (map-set stylists tx-sender {
        name: validated-name,
        stake-amount: min-stake-amount,
        reputation-sum: u0,
        rating-count: u0,
        active: true,
        registration-height: block-height
      })

      (ok true))))

;; Increase stylist stake
(define-public (increase-stake (amount uint))
  (let ((stylist-data (unwrap! (map-get? stylists tx-sender) err-not-registered)))
    (begin
      (asserts! (> amount u0) err-invalid-amount)

      ;; Transfer additional stake to contract
      (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))

      ;; Update stylist data
      (map-set stylists tx-sender {
        name: (get name stylist-data),
        stake-amount: (+ (get stake-amount stylist-data) amount),
        reputation-sum: (get reputation-sum stylist-data),
        rating-count: (get rating-count stylist-data),
        active: (get active stylist-data),
        registration-height: (get registration-height stylist-data)
      })

      (ok true))))

;; Withdraw stake (partial or full)
(define-public (withdraw-stake (amount uint))
  (let (
    (stylist-data (unwrap! (map-get? stylists tx-sender) err-not-registered))
    (current-stake (get stake-amount stylist-data))
  )
    (begin
      (asserts! (> amount u0) err-invalid-amount)
      (asserts! (<= amount current-stake) err-insufficient-stake)
      (asserts! (>= (- current-stake amount) min-stake-amount) err-insufficient-stake)

      ;; Transfer stake back to stylist
      (try! (as-contract (stx-transfer? amount (as-contract tx-sender) tx-sender)))

      ;; Update stylist data
      (map-set stylists tx-sender {
        name: (get name stylist-data),
        stake-amount: (- current-stake amount),
        reputation-sum: (get reputation-sum stylist-data),
        rating-count: (get rating-count stylist-data),
        active: (get active stylist-data),
        registration-height: (get registration-height stylist-data)
      })

      (ok true))))

;; Time slot management

;; Create a new time slot
(define-public (create-time-slot (date uint) (time uint) (duration uint) (price uint))
  (let (
    (stylist-data (unwrap! (map-get? stylists tx-sender) err-not-registered))
    (slot-id (var-get next-slot-id))
    (validated-date date)
    (validated-time time)
    (validated-duration duration)
    (validated-price price)
    (current-slots (default-to (list ) (map-get? stylist-slots {stylist: tx-sender, date: validated-date})))
  )
    (begin
      (asserts! (get active stylist-data) err-not-registered)
      (asserts! (is-valid-date validated-date) err-invalid-date)
      (asserts! (is-valid-time validated-time) err-invalid-time)
      (asserts! (is-valid-duration validated-duration) err-invalid-duration)
      (asserts! (is-valid-price validated-price) err-invalid-price)

      ;; Create the time slot
      (map-set time-slots slot-id {
        stylist: tx-sender,
        date: validated-date,
        time: validated-time,
        duration: validated-duration,
        price: validated-price,
        booked: false
      })

      ;; Add to stylist's slots for the date
      (map-set stylist-slots 
        {stylist: tx-sender, date: validated-date}
        (unwrap! (as-max-len? (append current-slots slot-id) u20) err-unauthorized))

      ;; Increment slot ID
      (var-set next-slot-id (+ slot-id u1))

      (ok slot-id))))

;; Booking management

;; Book a time slot
(define-public (book-slot (slot-id uint))
  (let (
    (slot (unwrap! (map-get? time-slots slot-id) err-not-booked))
    (booking-id (var-get next-booking-id))
    (current-bookings (default-to (list ) (map-get? customer-bookings tx-sender)))
    (price (get price slot))
    (fee (/ (* price booking-fee-percent) u100))
    (total-cost (+ price fee))
  )
    (begin
      (asserts! (not (get booked slot)) err-slot-unavailable)
      (asserts! (> (get date slot) block-height) err-slot-in-past)

      ;; Transfer payment
      (try! (stx-transfer? total-cost tx-sender (as-contract tx-sender)))

      ;; Update DAO treasury
      (var-set dao-treasury (+ (var-get dao-treasury) fee))

      ;; Mark slot as booked
      (map-set time-slots slot-id (merge slot {booked: true}))

      ;; Create booking record
      (map-set bookings booking-id {
        slot-id: slot-id,
        customer: tx-sender,
        paid-amount: price,
        rated: false,
        rating: u0,
        booking-height: block-height
      })

      ;; Add to customer's bookings
      (map-set customer-bookings 
        tx-sender
        (unwrap! (as-max-len? (append current-bookings booking-id) u20) err-unauthorized))

      ;; Increment booking ID
      (var-set next-booking-id (+ booking-id u1))

      (ok booking-id))))

;; Rate a completed booking
(define-public (rate-booking (booking-id uint) (rating uint))
  (let (
    (booking (unwrap! (map-get? bookings booking-id) err-not-booked))
    (slot (unwrap! (map-get? time-slots (get slot-id booking)) err-not-booked))
    (stylist (get stylist slot))
    (stylist-data (unwrap! (map-get? stylists stylist) err-not-registered))
  )
    (begin
      (asserts! (is-eq tx-sender (get customer booking)) err-unauthorized)
      (asserts! (not (get rated booking)) err-already-rated)
      (asserts! (<= rating max-rating) err-invalid-rating)
      (asserts! (> rating u0) err-invalid-rating)

      ;; Update booking with rating
      (map-set bookings booking-id (merge booking {rated: true, rating: rating}))

      ;; Update stylist reputation
      (map-set stylists stylist {
        name: (get name stylist-data),
        stake-amount: (get stake-amount stylist-data),
        reputation-sum: (+ (get reputation-sum stylist-data) rating),
        rating-count: (+ (get rating-count stylist-data) u1),
        active: (get active stylist-data),
        registration-height: (get registration-height stylist-data)
      })

      (ok true))))

;; DAO treasury management

;; Withdraw from treasury (owner only)
(define-public (withdraw-treasury (amount uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= amount (var-get dao-treasury)) err-insufficient-stake)

    ;; Transfer from treasury
    (try! (as-contract (stx-transfer? amount (as-contract tx-sender) tx-sender)))

    ;; Update treasury balance
    (var-set dao-treasury (- (var-get dao-treasury) amount))

    (ok true)))

;; Read-only functions

;; Get stylist information
(define-read-only (get-stylist-info (stylist principal))
  (map-get? stylists stylist))

;; Get stylist average rating
(define-read-only (get-stylist-rating (stylist principal))
  (let ((stylist-data (unwrap-panic (map-get? stylists stylist))))
    (if (> (get rating-count stylist-data) u0)
      (/ (get reputation-sum stylist-data) (get rating-count stylist-data))
      u0)))

;; Get time slot information
(define-read-only (get-time-slot (slot-id uint))
  (map-get? time-slots slot-id))

;; Get booking information
(define-read-only (get-booking (booking-id uint))
  (map-get? bookings booking-id))

;; Get stylist's slots for a date
(define-read-only (get-stylist-slots (stylist principal) (date uint))
  (map-get? stylist-slots {stylist: stylist, date: date}))

;; Get customer's bookings
(define-read-only (get-customer-bookings (customer principal))
  (map-get? customer-bookings customer))

;; Get DAO treasury balance
(define-read-only (get-treasury-balance)
  (var-get dao-treasury))