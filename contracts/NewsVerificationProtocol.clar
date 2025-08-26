;; title: NewsVerificationProtocol
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;



;; NewsVerification Protocol
;; A decentralized fact-checking system with community validation and reputation-based scoring
;; Built on Stacks blockchain using Clarity

;; Define constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-unauthorized (err u101))
(define-constant err-news-not-found (err u102))
(define-constant err-already-voted (err u103))
(define-constant err-invalid-vote (err u104))
(define-constant err-invalid-news-id (err u105))

;; Data structures
;; News article structure
(define-map news-articles
  { news-id: uint }
  {
    url: (string-ascii 256),
    title: (string-ascii 128),
    submitter: principal,
    timestamp: uint,
    total-votes: uint,
    accuracy-score: uint,  ;; Out of 100
    verified: bool
  }
)

;; Community votes tracking
(define-map community-votes
  { news-id: uint, voter: principal }
  {
    vote: uint,  ;; 1 = true/accurate, 0 = false/inaccurate
    reputation-weight: uint,
    timestamp: uint
  }
)

;; User reputation tracking
(define-map user-reputation
  principal
  {
    reputation-score: uint,  ;; Out of 100, starts at 50
    successful-votes: uint,
    total-votes: uint,
    last-activity: uint
  }
)

;; Global counters
(define-data-var next-news-id uint u1)
(define-data-var total-articles uint u0)

;; Function 1: Submit news article for verification
(define-public (submit-news-article (url (string-ascii 256)) (title (string-ascii 128)))
  (let (
    (news-id (var-get next-news-id))
  )
    (begin
      ;; Validate inputs
      (asserts! (> (len url) u0) err-invalid-news-id)
      (asserts! (> (len title) u0) err-invalid-news-id)
      
      ;; Store the news article
      (map-set news-articles
        { news-id: news-id }
        {
          url: url,
          title: title,
          submitter: tx-sender,
          timestamp: stacks-block-height,
          total-votes: u0,
          accuracy-score: u50,  ;; Start with neutral score
          verified: false
        }
      )
      
      ;; Initialize user reputation if first time
      (match (map-get? user-reputation tx-sender)
        existing-rep 
          ;; User exists, update last activity
          (map-set user-reputation tx-sender
            (merge existing-rep { last-activity:stacks-block-height }))
        ;; New user, create reputation entry
        (map-set user-reputation tx-sender
          {
            reputation-score: u50,
            successful-votes: u0,
            total-votes: u0,
            last-activity:stacks-block-height
          }
        )
      )
      
      ;; Update counters
      (var-set next-news-id (+ news-id u1))
      (var-set total-articles (+ (var-get total-articles) u1))
      
      (ok news-id)
    )
  )
)

;; Function 2: Vote on news article accuracy (community validation)
(define-public (vote-on-accuracy (news-id uint) (vote uint))
  (let (
    (news-data (unwrap! (map-get? news-articles { news-id: news-id }) err-news-not-found))
    (voter-reputation (default-to { reputation-score: u50, successful-votes: u0, total-votes: u0, last-activity: u0 }
                       (map-get? user-reputation tx-sender)))
    (existing-vote (map-get? community-votes { news-id: news-id, voter: tx-sender }))
  )
    (begin
      ;; Validate vote (must be 0 or 1)
      (asserts! (or (is-eq vote u0) (is-eq vote u1)) err-invalid-vote)
      
      ;; Check if user already voted
      (asserts! (is-none existing-vote) err-already-voted)
      
      ;; Record the vote
      (map-set community-votes
        { news-id:news-id, voter: tx-sender }
        {
          vote: vote,
          reputation-weight: (get reputation-score voter-reputation),
          timestamp:stacks-block-height
        }
      )
      
      ;; Update user's voting history
      (map-set user-reputation tx-sender
        (merge voter-reputation {
          total-votes: (+ (get total-votes voter-reputation) u1),
          last-activity: stacks-block-height
        })
      )
      
      ;; Calculate new accuracy score using weighted reputation
      (let (
        (new-total-votes (+ (get total-votes news-data) u1))
        (weighted-vote (* vote (get reputation-score voter-reputation)))
        (current-weighted-score (* (get accuracy-score news-data) (get total-votes news-data)))
        (new-weighted-score (+ current-weighted-score weighted-vote))
        (new-accuracy-score (if (> new-total-votes u0)
                              (/ new-weighted-score new-total-votes)
                              u50))
      )
        ;; Update news article with new vote count and accuracy score
        (map-set news-articles
          { news-id: news-id }
          (merge news-data {
            total-votes: new-total-votes,
            accuracy-score: new-accuracy-score,
            verified: (>= new-total-votes u5)  ;; Consider verified after 5+ votes
          })
        )
      )
      
      (ok true)
    )
  )
)
;; Read-only functions for querying data
(define-read-only (get-news-article (news-id uint))
  (map-get? news-articles { news-id: news-id }))

(define-read-only (get-user-reputation (user principal))
  (map-get? user-reputation user))

(define-read-only (get-user-vote (news-id uint) (voter principal))
  (map-get? community-votes { news-id: news-id, voter: voter }))

(define-read-only (get-total-articles)
  (ok (var-get total-articles)))

(define-read-only (get-next-news-id)
  (ok (var-get next-news-id)))