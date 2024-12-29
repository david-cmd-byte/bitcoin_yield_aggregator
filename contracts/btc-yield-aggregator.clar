;; Bitcoin Yield Aggregator
;; 
;; A secure and efficient DeFi yield strategy management system that enables users to:
;; - Deposit tokens into various yield-generating protocols
;; - Manage protocol allocations dynamically
;; - Earn and claim rewards based on protocol performance
;; - Benefit from automated strategy rebalancing
;;
;; Security Features:
;; - Protocol whitelisting
;; - Emergency shutdown mechanism
;; - Rate limiting
;; - Comprehensive input validation
;; - Balance verification
;; - SIP-010 compliance checks

;; Principal Constants
(define-constant contract-owner tx-sender)

;; Error Constants
(define-constant ERR-NOT-AUTHORIZED (err u1000))
(define-constant ERR-INVALID-AMOUNT (err u1001))
(define-constant ERR-INSUFFICIENT-BALANCE (err u1002))
(define-constant ERR-PROTOCOL-NOT-WHITELISTED (err u1003))
(define-constant ERR-STRATEGY-DISABLED (err u1004))
(define-constant ERR-MAX-DEPOSIT-REACHED (err u1005))
(define-constant ERR-MIN-DEPOSIT-NOT-MET (err u1006))
(define-constant ERR-INVALID-PROTOCOL-ID (err u1007))
(define-constant ERR-PROTOCOL-EXISTS (err u1008))
(define-constant ERR-INVALID-APY (err u1009))
(define-constant ERR-INVALID-NAME (err u1010))
(define-constant ERR-INVALID-TOKEN (err u1011))
(define-constant ERR-TOKEN-NOT-WHITELISTED (err u1012))
(define-constant ERR-ZERO-AMOUNT (err u1013))
(define-constant ERR-INVALID-USER (err u1014))
(define-constant ERR-ALREADY-WHITELISTED (err u1015))
(define-constant ERR-AMOUNT-TOO-LARGE (err u1016))
(define-constant ERR-INVALID-STATE (err u1017))
(define-constant ERR-RATE-LIMITED (err u1018))

;; Protocol Constants
(define-constant PROTOCOL-ACTIVE true)
(define-constant PROTOCOL-INACTIVE false)
(define-constant MAX-PROTOCOL-ID u100)
(define-constant MAX-APY u10000)
(define-constant MIN-APY u0)
(define-constant MAX-TOKEN-TRANSFER u1000000000000)
(define-constant MIN-REQUIRED-RESPONSES u3)

;; State Variables
(define-data-var total-tvl uint u0)
(define-data-var platform-fee-rate uint u100)
(define-data-var min-deposit uint u100000)
(define-data-var max-deposit uint u1000000000)
(define-data-var emergency-shutdown bool false)

;; Data Maps
(define-map user-deposits 
    { user: principal } 
    { amount: uint, last-deposit-block: uint })

(define-map user-rewards 
    { user: principal } 
    { pending: uint, claimed: uint })

(define-map protocols 
    { protocol-id: uint } 
    { name: (string-ascii 64), active: bool, apy: uint })

(define-map strategy-allocations 
    { protocol-id: uint } 
    { allocation: uint })

(define-map whitelisted-tokens 
    { token: principal } 
    { approved: bool })

(define-map user-operations 
    { user: principal }
    { last-operation: uint, count: uint })

;; SIP-010 Token Interface
(define-trait sip-010-trait
    (
        (transfer (uint principal principal (optional (buff 34))) (response bool uint))
        (get-balance (principal) (response uint uint))
        (get-decimals () (response uint uint))
        (get-name () (response (string-ascii 32) uint))
        (get-symbol () (response (string-ascii 32) uint))
        (get-total-supply () (response uint uint))
    )
)

;; Authorization Functions
(define-private (is-contract-owner)
    (is-eq tx-sender contract-owner)
)

;; Validation Functions
(define-private (is-valid-protocol-id (protocol-id uint))
    (and 
        (> protocol-id u0)
        (<= protocol-id MAX-PROTOCOL-ID)
    )
)

(define-private (is-valid-apy (apy uint))
    (and 
        (>= apy MIN-APY)
        (<= apy MAX-APY)
    )
)

(define-private (is-valid-name (name (string-ascii 64)))
    (and 
        (not (is-eq name ""))
        (<= (len name) u64)
    )
)

(define-private (protocol-exists (protocol-id uint))
    (is-some (map-get? protocols { protocol-id: protocol-id }))
)

(define-private (check-valid-amount (amount uint))
    (begin
        (asserts! (> amount u0) ERR-ZERO-AMOUNT)
        (asserts! (<= amount MAX-TOKEN-TRANSFER) ERR-AMOUNT-TOO-LARGE)
        (ok amount)
    )
)

(define-private (check-valid-user (user principal))
    (begin
        (asserts! (not (is-eq user (as-contract tx-sender))) ERR-INVALID-USER)
        (ok user)
    )
)

(define-private (check-contract-state)
    (begin
        (asserts! (not (var-get emergency-shutdown)) ERR-STRATEGY-DISABLED)
        (ok true)
    )
)

;; Protocol Management Functions
(define-public (add-protocol (protocol-id uint) (name (string-ascii 64)) (initial-apy uint))
    (begin
        (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
        (asserts! (is-valid-protocol-id protocol-id) ERR-INVALID-PROTOCOL-ID)
        (asserts! (not (protocol-exists protocol-id)) ERR-PROTOCOL-EXISTS)
        (asserts! (is-valid-name name) ERR-INVALID-NAME)
        (asserts! (is-valid-apy initial-apy) ERR-INVALID-APY)
        
        (map-set protocols { protocol-id: protocol-id }
            { 
                name: name,
                active: PROTOCOL-ACTIVE,
                apy: initial-apy
            }
        )
        (map-set strategy-allocations { protocol-id: protocol-id } { allocation: u0 })
        (ok true)
    )
)

(define-public (update-protocol-status (protocol-id uint) (active bool))
    (begin
        (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
        (asserts! (is-valid-protocol-id protocol-id) ERR-INVALID-PROTOCOL-ID)
        (asserts! (protocol-exists protocol-id) ERR-INVALID-PROTOCOL-ID)
        
        (let ((protocol (unwrap-panic (get-protocol protocol-id))))
            (map-set protocols { protocol-id: protocol-id }
                (merge protocol { active: active })
            )
        )
        (ok true)
    )
)

(define-public (update-protocol-apy (protocol-id uint) (new-apy uint))
    (begin
        (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
        (asserts! (is-valid-protocol-id protocol-id) ERR-INVALID-PROTOCOL-ID)
        (asserts! (protocol-exists protocol-id) ERR-INVALID-PROTOCOL-ID)
        (asserts! (is-valid-apy new-apy) ERR-INVALID-APY)
        
        (let ((protocol (unwrap-panic (get-protocol protocol-id))))
            (map-set protocols { protocol-id: protocol-id }
                (merge protocol { apy: new-apy })
            )
        )
        (ok true)
    )
)

;; Token Management Functions
(define-private (validate-token (token-trait <sip-010-trait>))
    (let
        (
            (token-contract (contract-of token-trait))
            (token-info (map-get? whitelisted-tokens { token: token-contract }))
        )
        (asserts! (is-some token-info) ERR-TOKEN-NOT-WHITELISTED)
        (asserts! (get approved (unwrap-panic token-info)) ERR-PROTOCOL-NOT-WHITELISTED)
        
        (let
            (
                (name-response (try! (contract-call? token-trait get-name)))
                (symbol-response (try! (contract-call? token-trait get-symbol)))
                (decimals-response (try! (contract-call? token-trait get-decimals)))
            )
            (asserts! (and
                (> (len name-response) u0)
                (> (len symbol-response) u0)
                (>= decimals-response u0)
            ) ERR-INVALID-TOKEN)
        )
        
        (ok token-contract)
    )
)

;; Deposit Management Functions
(define-public (deposit (token-trait <sip-010-trait>) (amount uint))
    (let
        (
            (user-principal tx-sender)
            (current-deposit (default-to { amount: u0, last-deposit-block: u0 }
                (map-get? user-deposits { user: user-principal })))
        )
        (try! (check-valid-amount amount))
        (try! (check-valid-user user-principal))
        (try! (validate-token-extended token-trait))
        (try! (check-rate-limit user-principal))
        (try! (check-contract-state))
        
        (asserts! (>= amount (var-get min-deposit)) ERR-MIN-DEPOSIT-NOT-MET)
        (asserts! (<= (+ amount (get amount current-deposit)) (var-get max-deposit)) ERR-MAX-DEPOSIT-REACHED)

        (let ((user-balance (try! (contract-call? token-trait get-balance user-principal))))
            (asserts! (>= user-balance amount) ERR-INSUFFICIENT-BALANCE)
        )

        (try! (safe-token-transfer token-trait amount user-principal (as-contract tx-sender)))
        
        (map-set user-deposits 
            { user: user-principal }
            { 
                amount: (+ amount (get amount current-deposit)),
                last-deposit-block: block-height
            })
        
        (var-set total-tvl (+ (var-get total-tvl) amount))
        (update-rate-limit user-principal)
        
        (try! (rebalance-protocols))
        (ok true)
    )
)

(define-public (withdraw (token-trait <sip-010-trait>) (amount uint))
    (let
        (
            (user-principal tx-sender)
            (current-deposit (default-to { amount: u0, last-deposit-block: u0 }
                (map-get? user-deposits { user: user-principal })))
        )
        (try! (check-valid-amount amount))
        (try! (check-valid-user user-principal))
        (try! (validate-token-extended token-trait))
        (try! (check-rate-limit user-principal))
        (asserts! (<= amount (get amount current-deposit)) ERR-INSUFFICIENT-BALANCE)

        (let ((contract-balance (try! (contract-call? token-trait get-balance (as-contract tx-sender)))))
            (asserts! (>= contract-balance amount) ERR-INSUFFICIENT-BALANCE)
        )

        (map-set user-deposits
            { user: user-principal }
            {
                amount: (- (get amount current-deposit) amount),
                last-deposit-block: (get last-deposit-block current-deposit)
            })
        
        (var-set total-tvl (- (var-get total-tvl) amount))
        (update-rate-limit user-principal)
        
        (as-contract
            (try! (safe-token-transfer token-trait amount tx-sender user-principal)))
        
        (ok true)
    )
)

;; Token Transfer Helper
(define-private (safe-token-transfer (token-trait <sip-010-trait>) (amount uint) (sender principal) (recipient principal))
    (begin
        (asserts! (not (var-get emergency-shutdown)) ERR-STRATEGY-DISABLED)
        (try! (check-valid-amount amount))
        (try! (check-valid-user recipient))
        (try! (validate-token token-trait))
        
        (let ((sender-balance (unwrap-panic (contract-call? token-trait get-balance sender))))
            (asserts! (>= sender-balance amount) ERR-INSUFFICIENT-BALANCE)
        )
        (contract-call? token-trait transfer amount sender recipient none)
    )
)

;; Reward Management Functions
(define-private (calculate-rewards (user principal) (blocks uint))
    (let
        (
            (user-deposit (unwrap-panic (get-user-deposit user)))
            (weighted-apy (get-weighted-apy))
        )
        (/ (* (get amount user-deposit) weighted-apy blocks) (* u10000 u144 u365))
    )
)

(define-public (claim-rewards (token-trait <sip-010-trait>))
    (let
        (
            (user-principal tx-sender)
            (rewards (calculate-rewards user-principal (- block-height 
                (get last-deposit-block (unwrap-panic (get-user-deposit user-principal))))))
        )
        (try! (validate-token-extended token-trait))
        (try! (check-rate-limit user-principal))
        (asserts! (> rewards u0) ERR-INVALID-AMOUNT)
        
        (let ((contract-balance (try! (contract-call? token-trait get-balance (as-contract tx-sender)))))
            (asserts! (>= contract-balance rewards) ERR-INSUFFICIENT-BALANCE)
        )

        (map-set user-rewards
            { user: user-principal }
            {
                pending: u0,
                claimed: (+ rewards 
                    (get claimed (default-to { pending: u0, claimed: u0 }
                        (map-get? user-rewards { user: user-principal }))))
            })
        
        (update-rate-limit user-principal)
        
        (as-contract
            (try! (safe-token-transfer token-trait rewards tx-sender user-principal)))
        
        (ok rewards)
    )
)

;; Protocol Optimization Functions
(define-private (rebalance-protocols)
    (let
        (
            (total-allocations (fold + (map get-protocol-allocation (get-protocol-list)) u0))
        )
        (asserts! (<= total-allocations u10000) ERR-INVALID-AMOUNT)
        (ok true)
    )
)

(define-private (get-weighted-apy)
    (fold + (map get-weighted-protocol-apy (get-protocol-list)) u0)
)

(define-private (get-weighted-protocol-apy (protocol-id uint))
    (let
        (
            (protocol (unwrap-panic (get-protocol protocol-id)))
            (allocation (get allocation (unwrap-panic 
                (map-get? strategy-allocations { protocol-id: protocol-id }))))
        )
        (if (get active protocol)
            (/ (* (get apy protocol) allocation) u10000)
            u0
        )
    )
)

;; Read-Only Functions
(define-read-only (get-protocol (protocol-id uint))
    (map-get? protocols { protocol-id: protocol-id })
)

(define-read-only (get-user-deposit (user principal))
    (map-get? user-deposits { user: user })
)

(define-read-only (get-total-tvl)
    (var-get total-tvl)
)

(define-read-only (is-whitelisted (token <sip-010-trait>))
    (default-to false (get approved (map-get? whitelisted-tokens { token: (contract-of token) })))
)

;; Administrative Functions
(define-public (set-platform-fee (new-fee uint))
    (begin
        (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
        (asserts! (<= new-fee u1000) ERR-INVALID-AMOUNT)
        (var-set platform-fee-rate new-fee)
        (ok true)
    )
)

(define-public (set-emergency-shutdown (shutdown bool))
    (begin
        (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
        (asserts! (not (is-eq shutdown (var-get emergency-shutdown))) ERR-INVALID-STATE)
        (print { event: "emergency-shutdown", status: shutdown })
        (var-set emergency-shutdown shutdown)
        (ok true)
    )
)

(define-public (whitelist-token (token <sip-010-trait>))
    (begin
        (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
        (let 
            (
                (token-contract (contract-of token))
            )
            (asserts! (not (is-whitelisted token)) ERR-ALREADY-WHITELISTED)
            
            (try! (contract-call? token get-name))
            (try! (contract-call? token get-symbol))
            (try! (contract-call? token get-decimals))
            (try! (contract-call? token get-total-supply))
            
            (map-set whitelisted-tokens { token: token-contract } { approved: true })
            (print { event: "token-whitelisted", token: token-contract })
            (ok true)
        )
    )
)

;; Helper Functions
(define-private (get-protocol-list)
    (list u1 u2 u3 u4 u5)
)

(define-private (get-protocol-allocation (protocol-id uint))
    (get allocation (default-to { allocation: u0 }
        (map-get? strategy-allocations { protocol-id: protocol-id })))
)

(define-private (check-rate-limit (user principal))
    (let ((user-ops (default-to { last-operation: u0, count: u0 }
            (map-get? user-operations { user: user }))))
        (asserts! (or
            (> block-height (+ (get last-operation user-ops) u144))
            (< (get count user-ops) u10)
        ) ERR-RATE-LIMITED)
        (ok true)
    )
)

(define-private (update-rate-limit (user principal))
    (let ((user-ops (default-to { last-operation: u0, count: u0 }
            (map-get? user-operations { user: user }))))
        (map-set user-operations
            { user: user }
            {
                last-operation: block-height,
                count: (if (> block-height (+ (get last-operation user-ops) u144))
                    u1
                    (+ (get count user-ops) u1))
            }
        )
    )
)

(define-private (validate-token-extended (token-trait <sip-010-trait>))
    (let
        (
            (token-contract (contract-of token-trait))
            (token-info (map-get? whitelisted-tokens { token: token-contract }))
        )
        (try! (validate-token token-trait))
        
        (asserts! (not (is-eq token-contract (as-contract tx-sender))) ERR-INVALID-TOKEN)
        
        (let ((total-supply (try! (contract-call? token-trait get-total-supply))))
            (asserts! (> total-supply u0) ERR-INVALID-TOKEN)
        )
        
        (let ((decimals (try! (contract-call? token-trait get-decimals))))
            (asserts! (and (>= decimals u6) (<= decimals u18)) ERR-INVALID-TOKEN)
        )
        
        (ok token-contract)
    )
)