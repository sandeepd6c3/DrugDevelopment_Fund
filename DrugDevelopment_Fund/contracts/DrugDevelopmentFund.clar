;; DrugDevelopment Fund Contract
;; Crowdfunded pharmaceutical research with milestone payments and profit sharing

;; Define the fungible token for profit sharing
(define-fungible-token research-share)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-invalid-amount (err u101))
(define-constant err-insufficient-balance (err u102))
(define-constant err-fund-closed (err u103))
(define-constant err-milestone-not-reached (err u104))

;; Contract state variables
(define-data-var funding-goal uint u1000000) ;; Target funding in microSTX
(define-data-var total-raised uint u0)
(define-data-var fund-active bool true)
(define-data-var current-milestone uint u0) ;; 0=Phase1, 1=Phase2, 2=Phase3, 3=Market
(define-data-var total-shares uint u0)

;; Investor tracking
(define-map investor-contributions principal uint)
(define-map investor-shares principal uint)

;; Milestone requirements (in microSTX)
(define-map milestone-requirements uint uint)

;; Initialize milestone requirements
(map-set milestone-requirements u0 u250000) ;; Phase 1: 25% of goal
(map-set milestone-requirements u1 u500000) ;; Phase 2: 50% of goal  
(map-set milestone-requirements u2 u750000) ;; Phase 3: 75% of goal
(map-set milestone-requirements u3 u1000000) ;; Market: 100% of goal

;; Function 1: Contribute to drug development fund
(define-public (contribute-to-fund (amount uint))
  (begin
    ;; Validate inputs
    (asserts! (var-get fund-active) err-fund-closed)
    (asserts! (> amount u0) err-invalid-amount)
    
    ;; Transfer STX from investor to contract
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    ;; Calculate profit shares (1 share per 1000 microSTX contributed)
    (let ((shares (/ amount u1000)))
      ;; Update investor records
      (map-set investor-contributions tx-sender 
               (+ (default-to u0 (map-get? investor-contributions tx-sender)) amount))
      (map-set investor-shares tx-sender
               (+ (default-to u0 (map-get? investor-shares tx-sender)) shares))
      
      ;; Mint profit-sharing tokens to investor
      (try! (ft-mint? research-share shares tx-sender))
      
      ;; Update contract totals
      (var-set total-raised (+ (var-get total-raised) amount))
      (var-set total-shares (+ (var-get total-shares) shares))
      
      ;; Check if funding goal reached and close fund
      (if (>= (var-get total-raised) (var-get funding-goal))
          (var-set fund-active false)
          true)
      
      (print {
        event: "contribution",
        investor: tx-sender,
        amount: amount,
        shares: shares,
        total-raised: (var-get total-raised)
      })
      (ok {contributed: amount, shares-received: shares}))))

;; Function 2: Release milestone payment for research progress
(define-public (release-milestone-payment (milestone uint) (research-team principal) (amount uint))
  (begin
    ;; Only contract owner can release milestone payments
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> amount u0) err-invalid-amount)
    
    ;; Verify milestone requirements are met
    (let ((required-funding (default-to u0 (map-get? milestone-requirements milestone))))
      (asserts! (>= (var-get total-raised) required-funding) err-milestone-not-reached)
      (asserts! (>= milestone (var-get current-milestone)) err-milestone-not-reached)
      
      ;; Ensure contract has sufficient balance
      (asserts! (>= (stx-get-balance (as-contract tx-sender)) amount) err-insufficient-balance)
      
      ;; Transfer milestone payment to research team
      (try! (as-contract (stx-transfer? amount tx-sender research-team)))
      
      ;; Update current milestone
      (var-set current-milestone (+ milestone u1))
      
      (print {
        event: "milestone-released",
        milestone: milestone,
        research-team: research-team,
        amount: amount,
        total-remaining: (- (stx-get-balance (as-contract tx-sender)) amount)
      })
      (ok {milestone: milestone, amount-released: amount}))))

;; Read-only functions for contract state
(define-read-only (get-fund-info)
  (ok {
    funding-goal: (var-get funding-goal),
    total-raised: (var-get total-raised),
    fund-active: (var-get fund-active),
    current-milestone: (var-get current-milestone),
    total-shares: (var-get total-shares),
    contract-balance: (stx-get-balance (as-contract tx-sender))
  }))

(define-read-only (get-investor-info (investor principal))
  (ok {
    contribution: (default-to u0 (map-get? investor-contributions investor)),
    shares: (default-to u0 (map-get? investor-shares investor)),
    share-balance: (ft-get-balance research-share investor)
  }))

(define-read-only (get-milestone-requirement (milestone uint))
  (ok (default-to u0 (map-get? milestone-requirements milestone))))