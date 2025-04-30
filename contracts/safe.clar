;; IdentityVault Smart Contract
;; This contract manages identity data sovereignty permissions and access control

;; Error codes
(define-constant ERR-NO-AUTH (err u1))
(define-constant ERR-IDENTITY-EXISTS (err u2))
(define-constant ERR-IDENTITY-NOT-FOUND (err u3))
(define-constant ERR-INVALID-CLEARANCE (err u4))
(define-constant ERR-ACCESS-EXPIRED (err u5))
(define-constant ERR-BAD-FORMAT (err u6))

;; Data maps
(define-map identity-registry 
    principal 
    {
        status: bool,
        vault-hash: (optional (buff 32)),
        last-modified: uint,
        clearance-tier: uint
    }
)

(define-map vault-access-ledger
    { vault-owner: principal, accessor: principal }
    {
        is-authorized: bool,
        expiration-block: uint,
        clearance-tier: uint
    }
)

(define-map data-sensitivity-tiers
    uint
    {
        tier-label: (string-ascii 64),
        required-clearance: uint
    }
)

;; Private functions
(define-private (is-vault-admin (caller principal)) 
    (is-eq caller (var-get vault-administrator))
)

(define-private (verify-access-authorization (vault-owner principal) (accessor principal))
    (let (
        (access-record (default-to 
            { is-authorized: false, expiration-block: u0, clearance-tier: u0 }
            (map-get? vault-access-ledger { vault-owner: vault-owner, accessor: accessor })
        ))
    )
    (and 
        (get is-authorized access-record)
        (> (get expiration-block access-record) block-height)
    ))
)

(define-private (validate-hash-format (input (optional (buff 32))))
    (match input
        buffer (is-eq (len buffer) u32)
        false
    )
)

(define-private (is-registered-identity (entity principal))
    (is-some (map-get? identity-registry entity))
)

;; Public variables
(define-data-var vault-administrator principal tx-sender)
(define-data-var min-clearance-tier uint u1)
(define-data-var max-clearance-tier uint u5)

;; Public functions
(define-public (register-identity (initial-hash (optional (buff 32))))
    (let (
        (applicant tx-sender)
    )
    (asserts! (is-none (map-get? identity-registry applicant)) ERR-IDENTITY-EXISTS)
    (asserts! (validate-hash-format initial-hash) ERR-BAD-FORMAT)
    (ok (map-set identity-registry 
        applicant
        {
            status: true,
            vault-hash: initial-hash,
            last-modified: block-height,
            clearance-tier: (var-get min-clearance-tier)
        }
    )))
)

(define-public (update-vault-hash (new-hash (buff 32)))
    (let (
        (identity-owner tx-sender)
        (identity-record (unwrap! (map-get? identity-registry identity-owner) ERR-IDENTITY-NOT-FOUND))
    )
    (asserts! (is-eq (len new-hash) u32) ERR-BAD-FORMAT)
    (ok (map-set identity-registry
        identity-owner
        (merge identity-record {
            vault-hash: (some new-hash),
            last-modified: block-height
        })
    )))
)

(define-public (authorize-access (requestor principal) (tier-level uint) (duration uint))
    (let (
        (vault-owner tx-sender)
        (owner-record (unwrap! (map-get? identity-registry vault-owner) ERR-IDENTITY-NOT-FOUND))
        (end-block (+ block-height duration))
    )
    (asserts! (is-registered-identity requestor) ERR-BAD-FORMAT)
    (asserts! (<= tier-level (get clearance-tier owner-record)) ERR-INVALID-CLEARANCE)
    (asserts! (< block-height end-block) ERR-BAD-FORMAT)
    (ok (map-set vault-access-ledger
        { vault-owner: vault-owner, accessor: requestor }
        {
            is-authorized: true,
            expiration-block: end-block,
            clearance-tier: tier-level
        }
    )))
)

(define-public (revoke-access (accessor principal))
    (let (
        (vault-owner tx-sender)
    )
    (asserts! (is-registered-identity accessor) ERR-BAD-FORMAT)
    (ok (map-delete vault-access-ledger { vault-owner: vault-owner, accessor: accessor }))
))

(define-public (access-identity-vault (target-owner principal))
    (let (
        (requestor tx-sender)
        (access-record (unwrap! (map-get? vault-access-ledger { vault-owner: target-owner, accessor: requestor }) ERR-NO-AUTH))
    )
    (asserts! (verify-access-authorization target-owner requestor) ERR-ACCESS-EXPIRED)
    (ok (map-get? identity-registry target-owner))
))

(define-public (set-clearance-tier (target-identity principal) (new-tier uint))
    (let (
        (admin tx-sender)
    )
    (asserts! (is-vault-admin admin) ERR-NO-AUTH)
    (asserts! (is-registered-identity target-identity) ERR-BAD-FORMAT)
    (asserts! (and (>= new-tier (var-get min-clearance-tier)) 
                   (<= new-tier (var-get max-clearance-tier))) 
              ERR-INVALID-CLEARANCE)
    (match (map-get? identity-registry target-identity)
        identity-data (ok (map-set identity-registry
            target-identity
            (merge identity-data {
                clearance-tier: new-tier,
                last-modified: block-height
            })))
        ERR-IDENTITY-NOT-FOUND
    )
))
