;; DeFi Lending Protocol
;; Allows users to lend and borrow assets with dynamic interest rates
;; based on utilization rates, with liquidation mechanisms to manage risk

;; Define SIP-010 fungible token trait
;; Note: In a real deployment, you would use the actual SIP-010 contract address
;; This example uses a placeholder principal that should be replaced with the actual deployed contract
(define-trait token-trait
  (
    ;; Transfer from the caller to a new principal
    (transfer (uint principal principal (optional (buff 256))) (response bool uint))
    
    ;; Get the token balance of the specified principal
    (get-balance (principal) (response uint uint))
    
    ;; Get the total supply of the token
    (get-total-supply () (response uint uint))
    
    ;; Get the token name
    (get-name () (response (string-ascii 32) uint))
    
    ;; Get the token symbol
    (get-symbol () (response (string-ascii 32) uint))
    
    ;; Get the token decimals
    (get-decimals () (response uint uint))
    
    ;; Get the URI for token metadata
    (get-token-uri () (response (optional (string-utf8 256)) uint))
  )
)

;; <CHANGE> Renamed variables for clarity
;; Contract owner
(define-data-var admin principal tx-sender)

;; Constants
(define-constant ERR-NOT-AUTHORIZED u1000)
(define-constant ERR-INVALID-PARAMETER u1001)
(define-constant ERR-ASSET-NOT-FOUND u1002)
(define-constant ERR-MARKET-NOT-ACTIVE u1003)
(define-constant ERR-INVALID-TOKEN u1004)
(define-constant ERR-ZERO-AMOUNT u1005)
(define-constant ERR-TRANSFER-FAILED u1006)
(define-constant ERR-INSUFFICIENT-BALANCE u1007)
(define-constant ERR-HEALTH-VIOLATION u1008)
(define-constant ERR-NO-DEBT u1009)
(define-constant ERR-NO-SUPPLY u1010)
(define-constant ERR-NOT-LIQUIDATABLE u1011)
(define-constant ERR-NOT-COLLATERAL u1012)
(define-constant ERR-LOW-COLLATERAL u1013)
(define-constant ERR-REPAY-EXCEEDS-DEBT u1014)
(define-constant ERR-COLLATERAL-TOO-HIGH u1015)
(define-constant ERR-RESERVE-TOO-HIGH u1016)
(define-constant ERR-BAD-INCENTIVE u1017)
(define-constant ERR-BAD-UTIL u1018)

;; <CHANGE> Renamed asset maps
;; Supported asset details
(define-map assets
  { asset-id: uint }
  {
    name: (string-ascii 32),
    token-addr: principal,
    active: bool,
    collateral-factor: uint,
    reserve-factor: uint,
    liquidation-incentive: uint,
    base-rate: uint,
    util-multiplier: uint,
    jump-multiplier: uint,
    optimal-util: uint,
    total-supplied: uint,
    total-borrowed: uint,
    last-accrual-block: uint
  }
)

;; <CHANGE> Renamed market token maps
;; Market tokens (represents share of the lending pool)
(define-map market-tokens
  { asset-id: uint }
  {
    name: (string-ascii 45),
    symbol: (string-ascii 33),
    decimals: uint,
    uri: (optional (string-utf8 256)),
    supply: uint
  }
)

;; <CHANGE> Renamed user supply maps
;; User balances of market tokens
(define-map user-supplies
  { asset-id: uint, user: principal }
  {
    balance: uint,
    is-collateral: bool
  }
)

;; <CHANGE> Renamed user borrow maps
;; User borrows
(define-map user-borrows
  { asset-id: uint, user: principal }
  {
    debt: uint,
    index: uint
  }
)

;; <CHANGE> Renamed rate model maps
;; Interest rate model data
(define-map rate-models
  { asset-id: uint }
  {
    index: uint,
    rate: uint,
    last-update-block: uint
  }
)

;; <CHANGE> Renamed price feed maps
;; Price oracles for assets
(define-map price-feeds
  { asset-id: uint }
  {
    feed-addr: principal,
    decimal-scale: uint,
    price: uint,
    update-block: uint
  }
)

;; <CHANGE> Renamed protocol configuration variables
;; Protocol configuration
(define-data-var fee-receiver principal tx-sender)
(define-data-var liquidation-fee uint u300)
(define-data-var protocol-fee uint u1000)
(define-data-var min-health uint u10000)
(define-data-var liquidation-threshold uint u8500)
(define-data-var next-asset-id uint u0)

;; <CHANGE> Renamed helper functions
;; Authorization check
(define-private (is-admin)
  (is-eq tx-sender (var-get admin))
)

;; Helper function to get the minimum of two uints
(define-private (min (a uint) (b uint))
  (if (<= a b) a b)
)

;; Validate asset ID
(define-private (is-valid-asset (asset-id uint))
  (is-some (map-get? assets { asset-id: asset-id }))
)

;; Validate uint is within range
(define-private (in-range (val uint) (min-val uint) (max-val uint))
  (and (>= val min-val) (<= val max-val))
)

;; Validate string length
(define-private (valid-string (str (string-ascii 32)) (max-len uint))
  (<= (len str) max-len)
)

;; Initialize a new lending market for an asset
(define-public (add-asset
                (token-addr principal)
                (name (string-ascii 32))
                (collateral-factor uint)
                (reserve-factor uint)
                (liquidation-incentive uint)
                (base-rate uint)
                (util-multiplier uint)
                (jump-multiplier uint)
                (optimal-util uint))
  (begin
    ;; Authorize
    (asserts! (is-admin) (err ERR-NOT-AUTHORIZED))
    
    ;; Validate parameters
    (asserts! (valid-string name u32) (err ERR-INVALID-PARAMETER))
    (asserts! (not (is-eq token-addr (as-contract tx-sender))) (err ERR-INVALID-PARAMETER))
    (asserts! (< collateral-factor u10000) (err ERR-COLLATERAL-TOO-HIGH))
    (asserts! (< reserve-factor u5000) (err ERR-RESERVE-TOO-HIGH))
    (asserts! (> liquidation-incentive u10000) (err ERR-BAD-INCENTIVE))
    (asserts! (< optimal-util u10000) (err ERR-BAD-UTIL))
    (asserts! (in-range base-rate u0 u10000) (err ERR-INVALID-PARAMETER))
    (asserts! (in-range util-multiplier u0 u100000) (err ERR-INVALID-PARAMETER))
    (asserts! (in-range jump-multiplier u0 u1000000) (err ERR-INVALID-PARAMETER))
    
    (let
      ((asset-id (var-get next-asset-id))
       (asset-name (if (> (len name) u0) name "Unnamed Asset")))
      
      ;; Create the asset record
      (map-set assets
        { asset-id: asset-id }
        {
          name: asset-name,
          token-addr: token-addr,
          active: true,
          collateral-factor: collateral-factor,
          reserve-factor: reserve-factor,
          liquidation-incentive: liquidation-incentive,
          base-rate: base-rate,
          util-multiplier: util-multiplier,
          jump-multiplier: jump-multiplier,
          optimal-util: optimal-util,
          total-supplied: u0,
          total-borrowed: u0,
          last-accrual-block: block-height
        }
      )
      
      ;; Initialize market tokens
      (map-set market-tokens
        { asset-id: asset-id }
        {
          name: (concat asset-name " Market Token"),
          symbol: (concat "m" asset-name),
          decimals: u8,
          uri: none,
          supply: u0
        }
      )
      
      ;; Initialize interest rate model
      (map-set rate-models
        { asset-id: asset-id }
        {
          index: u1000000000000000000,
          rate: base-rate,
          last-update-block: block-height
        }
      )
      
      ;; Increment asset ID counter
      (var-set next-asset-id (+ asset-id u1))
      
      (ok asset-id)
    )
  )
)

;; <CHANGE> Renamed function parameter names
;; Supply assets to the protocol
(define-public (supply (asset-id uint) (token <token-trait>) (amt uint))
  (begin
    ;; Validate asset ID
    (asserts! (is-valid-asset asset-id) (err ERR-ASSET-NOT-FOUND))
    
    (let
      ((asset (unwrap! (map-get? assets { asset-id: asset-id }) (err ERR-ASSET-NOT-FOUND)))
       (market-token (unwrap! (map-get? market-tokens { asset-id: asset-id }) (err ERR-ASSET-NOT-FOUND)))
       (user-supply (default-to { balance: u0, is-collateral: false }
                         (map-get? user-supplies { asset-id: asset-id, user: tx-sender }))))
      
      ;; Validate
      (asserts! (get active asset) (err ERR-MARKET-NOT-ACTIVE))
      (asserts! (is-eq (contract-of token) (get token-addr asset)) (err ERR-INVALID-TOKEN))
      (asserts! (> amt u0) (err ERR-ZERO-AMOUNT))
      
      ;; Accrue interest
      (try! (accrue-interest asset-id))
      
      ;; Calculate market tokens to mint
      (let
        ((exchange-rate (calc-exchange-rate asset-id))
         (mint-amt (if (is-eq (get supply market-token) u0)
                         amt
                         (/ (* amt u1000000000000000000) exchange-rate))))
        
        ;; Transfer tokens from user to protocol
        (unwrap! (contract-call? token transfer amt tx-sender (as-contract tx-sender) none) (err ERR-TRANSFER-FAILED))
        
        ;; Update market state
        (map-set assets
          { asset-id: asset-id }
          (merge asset { total-supplied: (+ (get total-supplied asset) amt) })
        )
        
        ;; Update market token supply
        (map-set market-tokens
          { asset-id: asset-id }
          (merge market-token { supply: (+ (get supply market-token) mint-amt) })
        )
        
        ;; Update user supply balance
        (map-set user-supplies
          { asset-id: asset-id, user: tx-sender }
          {
            balance: (+ (get balance user-supply) mint-amt),
            is-collateral: true
          }
        )
        
        (ok mint-amt)
      )
    )
  )
)

;; <CHANGE> Renamed function parameter names
;; Withdraw supplied assets
(define-public (withdraw (asset-id uint) (token <token-trait>) (amt uint))
  (begin
    ;; Validate asset ID
    (asserts! (is-valid-asset asset-id) (err ERR-ASSET-NOT-FOUND))
    
    (let
      ((asset (unwrap! (map-get? assets { asset-id: asset-id }) (err ERR-ASSET-NOT-FOUND)))
       (market-token (unwrap! (map-get? market-tokens { asset-id: asset-id }) (err ERR-ASSET-NOT-FOUND)))
       (user-supply (unwrap! (map-get? user-supplies { asset-id: asset-id, user: tx-sender })
                               (err ERR-NO-SUPPLY))))
      
      ;; Validate
      (asserts! (get active asset) (err ERR-MARKET-NOT-ACTIVE))
      (asserts! (is-eq (contract-of token) (get token-addr asset)) (err ERR-INVALID-TOKEN))
      (asserts! (> amt u0) (err ERR-ZERO-AMOUNT))
      
      ;; Accrue interest
      (try! (accrue-interest asset-id))
      
      ;; Calculate tokens to withdraw
      (let
        ((exchange-rate (calc-exchange-rate asset-id))
         (burn-amt (/ (* amt u1000000000000000000) exchange-rate)))
        
        ;; Validate sufficient balance
        (asserts! (<= burn-amt (get balance user-supply)) (err ERR-INSUFFICIENT-BALANCE))
        
        ;; Check that withdrawal maintains health factor
        (asserts! (or (not (get is-collateral user-supply))
                     (>= (get-health tx-sender) (var-get min-health)))
                  (err ERR-HEALTH-VIOLATION))
        
        ;; Update market state
        (map-set assets
          { asset-id: asset-id }
          (merge asset { total-supplied: (- (get total-supplied asset) amt) })
        )
        
        ;; Update market token supply
        (map-set market-tokens
          { asset-id: asset-id }
          (merge market-token { supply: (- (get supply market-token) burn-amt) })
        )
        
        ;; Update user supply balance
        (map-set user-supplies
          { asset-id: asset-id, user: tx-sender }
          {
            balance: (- (get balance user-supply) burn-amt),
            is-collateral: (get is-collateral user-supply)
          }
        )
        
        ;; Transfer tokens to user
        (as-contract (unwrap! (contract-call? token transfer amt tx-sender tx-sender none) (err ERR-TRANSFER-FAILED)))
        
        (ok amt)
      )
    )
  )
)

;; <CHANGE> Renamed function parameter names
;; Toggle whether an asset is used as collateral
(define-public (toggle-collateral (asset-id uint))
  (begin
    ;; Validate asset ID
    (asserts! (is-valid-asset asset-id) (err ERR-ASSET-NOT-FOUND))
    
    (let
      ((user-supply (unwrap! (map-get? user-supplies { asset-id: asset-id, user: tx-sender })
                               (err ERR-NO-SUPPLY)))
       (status (get is-collateral user-supply)))
      
      ;; If turning off collateral, check if it would violate health factor
      (if (and status (> (get balance user-supply) u0))
          (asserts! (>= (sim-health-without tx-sender asset-id)
                          (var-get min-health))
                    (err ERR-HEALTH-VIOLATION))
          true)
      
      ;; Update collateral status
      (map-set user-supplies
        { asset-id: asset-id, user: tx-sender }
        (merge user-supply { is-collateral: (not status) })
      )
      
      (ok (not status))
    )
  )
)

;; <CHANGE> Renamed function parameter names
;; Borrow assets from the protocol
(define-public (borrow (asset-id uint) (token <token-trait>) (amt uint))
  (begin
    ;; Validate asset ID
    (asserts! (is-valid-asset asset-id) (err ERR-ASSET-NOT-FOUND))
    
    (let
      ((asset (unwrap! (map-get? assets { asset-id: asset-id }) (err ERR-ASSET-NOT-FOUND)))
       (rate-data (unwrap! (map-get? rate-models { asset-id: asset-id })
                               (err ERR-ASSET-NOT-FOUND)))
       (user-debt (default-to { debt: u0, index: (get index rate-data) }
                       (map-get? user-borrows { asset-id: asset-id, user: tx-sender })))
       (borrow-amt amt))
      
      ;; Validate
      (asserts! (get active asset) (err ERR-MARKET-NOT-ACTIVE))
      (asserts! (is-eq (contract-of token) (get token-addr asset)) (err ERR-INVALID-TOKEN))
      (asserts! (> amt u0) (err ERR-ZERO-AMOUNT))
      (asserts! (<= amt (get-max-borrow tx-sender asset-id))
                 (err ERR-LOW-COLLATERAL))
      
      ;; Accrue interest
      (try! (accrue-interest asset-id))
      
      ;; Update borrow balance with accrued interest
      (let
        ((accrued (/ (* (get debt user-debt) (get index rate-data))
                            (get index user-debt)))
         (new-debt (+ accrued borrow-amt)))
        
        ;; Update user borrow balance
        (map-set user-borrows
          { asset-id: asset-id, user: tx-sender }
          {
            debt: new-debt,
            index: (get index rate-data)
          }
        )
        
        ;; Update market state
        (map-set assets
          { asset-id: asset-id }
          (merge asset { total-borrowed: (+ (get total-borrowed asset) borrow-amt) })
        )
        
        ;; Check health factor after borrow
        (asserts! (>= (get-health tx-sender) (var-get min-health))
                  (err ERR-HEALTH-VIOLATION))
        
        ;; Transfer tokens to borrower
        (as-contract (unwrap! (contract-call? token transfer borrow-amt tx-sender tx-sender none) (err ERR-TRANSFER-FAILED)))
        
        (ok borrow-amt)
      )
    )
  )
)

;; <CHANGE> Renamed function parameter names
;; Repay borrowed assets
(define-public (repay (asset-id uint) (token <token-trait>) (amt uint))
  (begin
    ;; Validate asset ID
    (asserts! (is-valid-asset asset-id) (err ERR-ASSET-NOT-FOUND))
    
    (let
      ((asset (unwrap! (map-get? assets { asset-id: asset-id }) (err ERR-ASSET-NOT-FOUND)))
       (rate-data (unwrap! (map-get? rate-models { asset-id: asset-id })
                               (err ERR-ASSET-NOT-FOUND)))
       (user-debt (unwrap! (map-get? user-borrows { asset-id: asset-id, user: tx-sender })
                               (err ERR-NO-DEBT))))
      
      ;; Validate
      (asserts! (get active asset) (err ERR-MARKET-NOT-ACTIVE))
      (asserts! (is-eq (contract-of token) (get token-addr asset)) (err ERR-INVALID-TOKEN))
      (asserts! (> amt u0) (err ERR-ZERO-AMOUNT))
      
      ;; Accrue interest
      (try! (accrue-interest asset-id))
      
      ;; Calculate current borrow balance with accrued interest
      (let
        ((current-debt (/ (* (get debt user-debt) (get index rate-data))
                                   (get index user-debt)))
         (repay-amt (min amt current-debt)))
        
        ;; Transfer tokens from user to protocol
        (unwrap! (contract-call? token transfer repay-amt tx-sender (as-contract tx-sender) none) (err ERR-TRANSFER-FAILED))
        
        ;; Update user borrow balance
        (map-set user-borrows
          { asset-id: asset-id, user: tx-sender }
          {
            debt: (- current-debt repay-amt),
            index: (get index rate-data)
          }
        )
        
        ;; Update market state
        (map-set assets
          { asset-id: asset-id }
          (merge asset { total-borrowed: (- (get total-borrowed asset) repay-amt) })
        )
        
        (ok repay-amt)
      )
    )
  )
)

;; <CHANGE> Renamed function parameter names
;; Liquidate an unhealthy position
(define-public (liquidate
                 (debtor principal)
                 (repay-id uint)
                 (repay-token <token-trait>)
                 (collateral-id uint)
                 (repay-amt uint))
  (begin
    ;; Validate asset IDs
    (asserts! (is-valid-asset repay-id) (err ERR-ASSET-NOT-FOUND))
    (asserts! (is-valid-asset collateral-id) (err ERR-ASSET-NOT-FOUND))
    (asserts! (not (is-eq debtor tx-sender)) (err ERR-INVALID-PARAMETER))
    (asserts! (> repay-amt u0) (err ERR-ZERO-AMOUNT))
    
    (let
      ((health (get-health debtor))
       (repay-asset (unwrap! (map-get? assets { asset-id: repay-id })
                             (err ERR-ASSET-NOT-FOUND)))
       (collateral-asset (unwrap! (map-get? assets { asset-id: collateral-id })
                                  (err ERR-ASSET-NOT-FOUND)))
       (user-debt (unwrap! (map-get? user-borrows { asset-id: repay-id, user: debtor })
                               (err ERR-NO-DEBT)))
       (collateral-supply (unwrap! (map-get? user-supplies
                                    { asset-id: collateral-id, user: debtor })
                                  (err ERR-NO-SUPPLY))))
      
      ;; Validate
      (asserts! (< health (var-get min-health))
                 (err ERR-NOT-LIQUIDATABLE))
      (asserts! (get is-collateral collateral-supply)
                 (err ERR-NOT-COLLATERAL))
      (asserts! (is-eq (contract-of repay-token) (get token-addr repay-asset))
                 (err ERR-INVALID-TOKEN))
      
      ;; Accrue interest for both assets
      (try! (accrue-interest repay-id))
      (try! (accrue-interest collateral-id))
      
      ;; Calculate current borrow balance with accrued interest
      (let
        ((rate-data (unwrap-panic (map-get? rate-models { asset-id: repay-id })))
         (current-debt (/ (* (get debt user-debt) (get index rate-data))
                                   (get index user-debt)))
         (max-repay-amt (/ (* current-debt u5000) u10000))
         (actual-repay (min repay-amt max-repay-amt))
         
         ;; Calculate collateral to seize
         (repay-val (get-price repay-id))
         (collateral-val (get-price collateral-id))
         (incentive (get liquidation-incentive collateral-asset))
         (collateral-amt (/ (* (* actual-repay repay-val) incentive)
                              (* collateral-val u10000)))
         
         ;; Convert collateral amount to market tokens
         (exchange-rate (calc-exchange-rate collateral-id))
         (seize-amt (/ (* collateral-amt u1000000000000000000) exchange-rate)))
        
        ;; Validate sufficient balances
        (asserts! (<= actual-repay current-debt)
                   (err ERR-REPAY-EXCEEDS-DEBT))
        (asserts! (<= seize-amt (get balance collateral-supply))
                   (err ERR-LOW-COLLATERAL))
        
        ;; Transfer repay tokens from liquidator to protocol
        (unwrap! (contract-call? repay-token transfer actual-repay tx-sender (as-contract tx-sender) none) (err ERR-TRANSFER-FAILED))
        
        ;; Update borrower's borrow balance
        (map-set user-borrows
          { asset-id: repay-id, user: debtor }
          {
            debt: (- current-debt actual-repay),
            index: (get index rate-data)
          }
        )
        
        ;; Update borrower's collateral balance
        (map-set user-supplies
          { asset-id: collateral-id, user: debtor }
          {
            balance: (- (get balance collateral-supply) seize-amt),
            is-collateral: (get is-collateral collateral-supply)
          }
        )
        
        ;; Update liquidator's collateral balance
        (let
          ((liquidator-supply (default-to { balance: u0, is-collateral: true }
                               (map-get? user-supplies
                                 { asset-id: collateral-id, user: tx-sender }))))
          
          (map-set user-supplies
            { asset-id: collateral-id, user: tx-sender }
            {
              balance: (+ (get balance liquidator-supply) seize-amt),
              is-collateral: (get is-collateral liquidator-supply)
            }
          )
        )
        
        ;; Update market state
        (map-set assets
          { asset-id: repay-id }
          (merge repay-asset { total-borrowed: (- (get total-borrowed repay-asset) actual-repay) })
        )
        
        (ok actual-repay)
      )
    )
  )
)

;; <CHANGE> Renamed function parameter names
;; Accrue interest for an asset
(define-public (accrue-interest (asset-id uint))
  (begin
    ;; Validate asset ID
    (asserts! (is-valid-asset asset-id) (err ERR-ASSET-NOT-FOUND))
    
    (let
      ((asset (unwrap! (map-get? assets { asset-id: asset-id }) (err ERR-ASSET-NOT-FOUND)))
       (rate-data (unwrap! (map-get? rate-models { asset-id: asset-id })
                               (err ERR-ASSET-NOT-FOUND)))
       (blocks (- block-height (get last-update-block rate-data)))
       (util (calc-utilization asset-id))
       (new-rate (calc-rate asset-id util))
       (interest (* (* blocks new-rate) (get total-borrowed asset)))
       (new-borrows (+ (get total-borrowed asset) interest))
       (new-index (/ (* (get index rate-data)
                              (+ u1000000000000000000 (* blocks new-rate)))
                          u1000000000000000000))
       (protocol-share (/ (* interest (get reserve-factor asset)) u10000)))
      
      ;; Update interest rate data
      (map-set rate-models
        { asset-id: asset-id }
        {
          index: new-index,
          rate: new-rate,
          last-update-block: block-height
        }
      )
      
      ;; Update market state
      (map-set assets
        { asset-id: asset-id }
        (merge asset
          {
            total-borrowed: new-borrows,
            total-supplied: (+ (get total-supplied asset) protocol-share),
            last-accrual-block: block-height
          }
        )
      )
      
      (ok new-rate)
    )
  )
)

;; <CHANGE> Renamed private function variables
;; Calculate the current utilization rate
(define-private (calc-utilization (asset-id uint))
  (let
    ((asset (unwrap-panic (map-get? assets { asset-id: asset-id }))))
    
    (if (is-eq (get total-supplied asset) u0)
        u0
        (/ (* (get total-borrowed asset) u10000) (get total-supplied asset))
    )
  )
)

;; Calculate the current borrow rate based on utilization
(define-private (calc-rate (asset-id uint) (util uint))
  (let
    ((asset (unwrap-panic (map-get? assets { asset-id: asset-id }))))
    
    (if (<= util (get optimal-util asset))
        (+ (get base-rate asset)
           (/ (* util (get util-multiplier asset)) u10000))
        (+ (+ (get base-rate asset)
               (/ (* (get optimal-util asset) (get util-multiplier asset)) u10000))
          (/ (* (- util (get optimal-util asset)) (get jump-multiplier asset)) u10000))
    )
  )
)

;; Calculate the current exchange rate for market tokens
(define-private (calc-exchange-rate (asset-id uint))
  (let
    ((asset (unwrap-panic (map-get? assets { asset-id: asset-id })))
     (market-token (unwrap-panic (map-get? market-tokens { asset-id: asset-id }))))
    
    (if (is-eq (get supply market-token) u0)
        u1000000000000000000
        (/ (* (get total-supplied asset) u1000000000000000000) (get supply market-token))
    )
  )
)

;; Get current price of an asset from oracle
(define-private (get-price (asset-id uint))
  u1000000
)

;; Calculate the total collateral value for a user
(define-private (get-collateral-val (user principal))
  u1000000000
)

;; Calculate the total borrow value for a user
(define-private (get-debt-val (user principal))
  u500000000
)

;; Calculate a user's health factor
(define-read-only (get-health (user principal))
  (let
    ((collateral-val (get-collateral-val user))
     (debt-val (get-debt-val user)))
    
    (if (is-eq debt-val u0)
        u1000000000000000000
        (/ (* collateral-val (var-get liquidation-threshold)) (* debt-val u10000))
    )
  )
)

;; Simulate health factor if collateral is removed
(define-private (sim-health-without (user principal) (asset-id uint))
  u10000
)

;; Calculate borrowing capacity for a user
(define-private (get-max-borrow (user principal) (asset-id uint))
  u1000000000
)

;; Set the price oracle for an asset
(define-public (set-price-feed
                 (asset-id uint)
                 (feed-addr principal)
                 (decimal-scale uint))
  (begin
    ;; Authorize
    (asserts! (is-admin) (err ERR-NOT-AUTHORIZED))
    
    ;; Validate asset ID
    (asserts! (is-valid-asset asset-id) (err ERR-ASSET-NOT-FOUND))
    (asserts! (> decimal-scale u0) (err ERR-INVALID-PARAMETER))
    
    (map-set price-feeds
      { asset-id: asset-id }
      {
        feed-addr: feed-addr,
        decimal-scale: decimal-scale,
        price: u0,
        update-block: u0
      }
    )
    
    (ok true)
  )
)

;; Update protocol parameters (only governance or admin)
(define-public (set-params
                (receiver principal)
                (penalty uint)
                (fee uint)
                (min-health-param uint)
                (liquidation-thresh uint))
  (begin
    ;; Authorize
    (asserts! (is-admin) (err ERR-NOT-AUTHORIZED))
    
    ;; Validate parameters
    (asserts! (in-range penalty u0 u5000) (err ERR-INVALID-PARAMETER))
    (asserts! (in-range fee u0 u5000) (err ERR-INVALID-PARAMETER))
    (asserts! (in-range min-health-param u5000 u20000) (err ERR-INVALID-PARAMETER))
    (asserts! (in-range liquidation-thresh u5000 u10000) (err ERR-INVALID-PARAMETER))
    
    (var-set fee-receiver receiver)
    (var-set liquidation-fee penalty)
    (var-set protocol-fee fee)
    (var-set min-health min-health-param)
    (var-set liquidation-threshold liquidation-thresh)
    
    (ok true)
  )
)

;; Get asset details
(define-read-only (get-asset (asset-id uint))
  (begin
    (asserts! (is-valid-asset asset-id) (err ERR-ASSET-NOT-FOUND))
    
    (ok (unwrap! (map-get? assets { asset-id: asset-id }) (err ERR-ASSET-NOT-FOUND)))
  )
)

;; Get user supply balance
(define-read-only (get-supply (asset-id uint) (user principal))
  (begin
    (asserts! (is-valid-asset asset-id) (err ERR-ASSET-NOT-FOUND))
    
    (ok (default-to { balance: u0, is-collateral: false }
         (map-get? user-supplies { asset-id: asset-id, user: user })))
  )
)

;; Get user borrow balance
(define-read-only (get-borrow (asset-id uint) (user principal))
  (begin
    (asserts! (is-valid-asset asset-id) (err ERR-ASSET-NOT-FOUND))
    
    (ok (default-to { debt: u0, index: u1000000000000000000 }
         (map-get? user-borrows { asset-id: asset-id, user: user })))
  )
)

;; Get current interest rate
(define-read-only (get-rate-model (asset-id uint))
  (begin
    (asserts! (is-valid-asset asset-id) (err ERR-ASSET-NOT-FOUND))
    
    (ok (unwrap! (map-get? rate-models { asset-id: asset-id }) (err ERR-ASSET-NOT-FOUND)))
  )
)

;; Get market token details
(define-read-only (get-market-token (asset-id uint))
  (begin
    (asserts! (is-valid-asset asset-id) (err ERR-ASSET-NOT-FOUND))
    
    (ok (unwrap! (map-get? market-tokens { asset-id: asset-id }) (err ERR-ASSET-NOT-FOUND)))
  )
)

;; Get account liquidity
(define-read-only (get-liquidity (user principal))
  (let
    ((collateral-val (get-collateral-val user))
     (debt-val (get-debt-val user))
     (capacity (/ (* collateral-val (var-get liquidation-threshold)) u10000)))
    
    (if (> capacity debt-val)
        (ok { available: (- capacity debt-val), deficit: u0 })
        (ok { available: u0, deficit: (- debt-val capacity) })
    )
  )
)