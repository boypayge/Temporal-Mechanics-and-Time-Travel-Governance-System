;; Future Knowledge Ethics Contract
;; Governs use of information obtained from future timelines

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u500))
(define-constant ERR-INVALID-KNOWLEDGE (err u501))
(define-constant ERR-ETHICAL-VIOLATION (err u502))
(define-constant ERR-DISCLOSURE-FORBIDDEN (err u503))
(define-constant ERR-INSUFFICIENT-CLEARANCE (err u504))

;; Data Variables
(define-data-var knowledge-counter uint u0)
(define-data-var ethics-active bool true)
(define-data-var disclosure-threshold uint u7)
(define-data-var monitoring-active bool true)

;; Data Maps
(define-map future-knowledge uint {
    knowledge-id: uint,
    holder: principal,
    source-timeline: uint,
    source-block: uint,
    knowledge-type: (string-ascii 50),
    sensitivity-level: uint,
    registered-block: uint,
    disclosure-status: (string-ascii 20),
    ethical-review: bool,
    impact-assessment: uint,
    restrictions: (list 10 (string-ascii 50))
})

(define-map knowledge-holders principal (list 20 uint))

(define-map disclosure-requests uint {
    knowledge-id: uint,
    requester: principal,
    purpose: (string-ascii 200),
    request-block: uint,
    approved: bool,
    reviewer: (optional principal),
    conditions: (list 5 (string-ascii 100))
})

(define-map ethical-violations uint {
    knowledge-id: uint,
    violator: principal,
    violation-type: (string-ascii 50),
    severity: uint,
    report-block: uint,
    investigated: bool,
    penalty-applied: bool
})

(define-map authorized-reviewers principal uint)
(define-map ethics-monitors principal bool)

;; Authorization Management
(define-public (add-ethics-reviewer (reviewer principal) (clearance-level uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (<= clearance-level u10) ERR-INSUFFICIENT-CLEARANCE)
        (ok (map-set authorized-reviewers reviewer clearance-level))
    )
)

(define-public (add-ethics-monitor (monitor principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (ok (map-set ethics-monitors monitor true))
    )
)

(define-public (remove-reviewer (reviewer principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (ok (map-delete authorized-reviewers reviewer))
    )
)

;; Knowledge Registration
(define-public (register-future-knowledge
    (source-timeline uint)
    (source-block uint)
    (knowledge-type (string-ascii 50))
    (sensitivity-level uint))
    (let ((knowledge-id (+ (var-get knowledge-counter) u1)))
        (asserts! (var-get ethics-active) ERR-ETHICAL-VIOLATION)
        (asserts! (> source-timeline u0) ERR-INVALID-KNOWLEDGE)
        (asserts! (> source-block block-height) ERR-INVALID-KNOWLEDGE)
        (asserts! (<= sensitivity-level u10) ERR-INVALID-KNOWLEDGE)
        (map-set future-knowledge knowledge-id {
            knowledge-id: knowledge-id,
            holder: tx-sender,
            source-timeline: source-timeline,
            source-block: source-block,
            knowledge-type: knowledge-type,
            sensitivity-level: sensitivity-level,
            registered-block: block-height,
            disclosure-status: "restricted",
            ethical-review: false,
            impact-assessment: u0,
            restrictions: (list)
        })
        (let ((current-holdings (default-to (list) (map-get? knowledge-holders tx-sender))))
            (map-set knowledge-holders tx-sender (unwrap! (as-max-len? (append current-holdings knowledge-id) u20) ERR-INVALID-KNOWLEDGE))
        )
        (var-set knowledge-counter knowledge-id)
        (ok knowledge-id)
    )
)

(define-public (conduct-ethical-review (knowledge-id uint) (impact-score uint))
    (let ((knowledge-data (unwrap! (map-get? future-knowledge knowledge-id) ERR-INVALID-KNOWLEDGE))
          (reviewer-clearance (default-to u0 (map-get? authorized-reviewers tx-sender))))
        (asserts! (> reviewer-clearance u0) ERR-NOT-AUTHORIZED)
        (asserts! (>= reviewer-clearance (get sensitivity-level knowledge-data)) ERR-INSUFFICIENT-CLEARANCE)
        (asserts! (<= impact-score u10) ERR-INVALID-KNOWLEDGE)
        (map-set future-knowledge knowledge-id (merge knowledge-data {
            ethical-review: true,
            impact-assessment: impact-score,
            disclosure-status: (if (< impact-score (var-get disclosure-threshold))
                                 "approved"
                                 "restricted")
        }))
        (ok true)
    )
)

;; Disclosure Management
(define-public (request-disclosure
    (knowledge-id uint)
    (purpose (string-ascii 200)))
    (let ((knowledge-data (unwrap! (map-get? future-knowledge knowledge-id) ERR-INVALID-KNOWLEDGE))
          (request-id (+ knowledge-id block-height)))
        (asserts! (var-get ethics-active) ERR-ETHICAL-VIOLATION)
        (asserts! (get ethical-review knowledge-data) ERR-ETHICAL-VIOLATION)
        (map-set disclosure-requests request-id {
            knowledge-id: knowledge-id,
            requester: tx-sender,
            purpose: purpose,
            request-block: block-height,
            approved: false,
            reviewer: none,
            conditions: (list)
        })
        (ok request-id)
    )
)

(define-public (approve-disclosure (request-id uint) (conditions (list 5 (string-ascii 100))))
    (let ((request-data (unwrap! (map-get? disclosure-requests request-id) ERR-DISCLOSURE-FORBIDDEN))
          (knowledge-data (unwrap! (map-get? future-knowledge (get knowledge-id request-data)) ERR-INVALID-KNOWLEDGE))
          (reviewer-clearance (default-to u0 (map-get? authorized-reviewers tx-sender))))
        (asserts! (>= reviewer-clearance (get sensitivity-level knowledge-data)) ERR-INSUFFICIENT-CLEARANCE)
        (asserts! (is-eq (get disclosure-status knowledge-data) "approved") ERR-DISCLOSURE-FORBIDDEN)
        (map-set disclosure-requests request-id (merge request-data {
            approved: true,
            reviewer: (some tx-sender),
            conditions: conditions
        }))
        (ok true)
    )
)

(define-public (deny-disclosure (request-id uint))
    (let ((request-data (unwrap! (map-get? disclosure-requests request-id) ERR-DISCLOSURE-FORBIDDEN))
          (knowledge-data (unwrap! (map-get? future-knowledge (get knowledge-id request-data)) ERR-INVALID-KNOWLEDGE))
          (reviewer-clearance (default-to u0 (map-get? authorized-reviewers tx-sender))))
        (asserts! (>= reviewer-clearance (get sensitivity-level knowledge-data)) ERR-INSUFFICIENT-CLEARANCE)
        (map-set disclosure-requests request-id (merge request-data {
            reviewer: (some tx-sender)
        }))
        (ok true)
    )
)

;; Violation Reporting and Enforcement
(define-public (report-ethical-violation
    (knowledge-id uint)
    (violator principal)
    (violation-type (string-ascii 50))
    (severity uint))
    (let ((violation-id (+ knowledge-id block-height)))
        (asserts! (default-to false (map-get? ethics-monitors tx-sender)) ERR-NOT-AUTHORIZED)
        (asserts! (<= severity u10) ERR-ETHICAL-VIOLATION)
        (map-set ethical-violations violation-id {
            knowledge-id: knowledge-id,
            violator: violator,
            violation-type: violation-type,
            severity: severity,
            report-block: block-height,
            investigated: false,
            penalty-applied: false
        })
        (ok violation-id)
    )
)

(define-public (investigate-violation (violation-id uint))
    (let ((violation-data (unwrap! (map-get? ethical-violations violation-id) ERR-ETHICAL-VIOLATION)))
        (asserts! (default-to false (map-get? ethics-monitors tx-sender)) ERR-NOT-AUTHORIZED)
        (map-set ethical-violations violation-id (merge violation-data {
            investigated: true
        }))
        (ok true)
    )
)

(define-public (apply-penalty (violation-id uint))
    (let ((violation-data (unwrap! (map-get? ethical-violations violation-id) ERR-ETHICAL-VIOLATION)))
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (get investigated violation-data) ERR-ETHICAL-VIOLATION)
        (map-set ethical-violations violation-id (merge violation-data {
            penalty-applied: true
        }))
        (ok true)
    )
)

;; Knowledge Management
(define-public (classify-knowledge (knowledge-id uint) (new-sensitivity uint))
    (let ((knowledge-data (unwrap! (map-get? future-knowledge knowledge-id) ERR-INVALID-KNOWLEDGE))
          (reviewer-clearance (default-to u0 (map-get? authorized-reviewers tx-sender))))
        (asserts! (>= reviewer-clearance u8) ERR-INSUFFICIENT-CLEARANCE)
        (asserts! (<= new-sensitivity u10) ERR-INVALID-KNOWLEDGE)
        (map-set future-knowledge knowledge-id (merge knowledge-data {
            sensitivity-level: new-sensitivity,
            disclosure-status: (if (< new-sensitivity (var-get disclosure-threshold))
                                 "approved"
                                 "restricted")
        }))
        (ok true)
    )
)

(define-public (add-restrictions (knowledge-id uint) (restrictions (list 10 (string-ascii 50))))
    (let ((knowledge-data (unwrap! (map-get? future-knowledge knowledge-id) ERR-INVALID-KNOWLEDGE)))
        (asserts! (or (is-eq tx-sender (get holder knowledge-data))
                     (> (default-to u0 (map-get? authorized-reviewers tx-sender)) u5)) ERR-NOT-AUTHORIZED)
        (map-set future-knowledge knowledge-id (merge knowledge-data {
            restrictions: restrictions
        }))
        (ok true)
    )
)

;; Read-only Functions
(define-read-only (get-knowledge (knowledge-id uint))
    (map-get? future-knowledge knowledge-id)
)

(define-read-only (get-holder-knowledge (holder principal))
    (default-to (list) (map-get? knowledge-holders holder))
)

(define-read-only (get-disclosure-request (request-id uint))
    (map-get? disclosure-requests request-id)
)

(define-read-only (get-violation-report (violation-id uint))
    (map-get? ethical-violations violation-id)
)

(define-read-only (is-disclosure-allowed (knowledge-id uint))
    (match (map-get? future-knowledge knowledge-id)
        knowledge-data (and
            (get ethical-review knowledge-data)
            (is-eq (get disclosure-status knowledge-data) "approved"))
        false
    )
)

(define-read-only (get-system-status)
    {
        total-knowledge-entries: (var-get knowledge-counter),
        ethics-active: (var-get ethics-active),
        disclosure-threshold: (var-get disclosure-threshold),
        monitoring-active: (var-get monitoring-active)
    }
)

;; Administrative Functions
(define-public (set-disclosure-threshold (threshold uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (<= threshold u10) ERR-INVALID-KNOWLEDGE)
        (var-set disclosure-threshold threshold)
        (ok true)
    )
)

(define-public (suspend-ethics-system)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (var-set ethics-active false)
        (var-set monitoring-active false)
        (ok true)
    )
)

(define-public (reactivate-ethics-system)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (var-set ethics-active true)
        (var-set monitoring-active true)
        (ok true)
    )
)
