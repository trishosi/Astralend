# Astralend

## Overview

**Astralend** is a decentralized finance (DeFi) lending protocol built on the Stacks blockchain. It enables users to lend and borrow digital assets with dynamically adjusting interest rates based on asset utilization rates. The protocol ensures system stability through over-collateralization, liquidation mechanisms, and continuous interest accrual.

---

## Key Features

### 1. Dynamic Interest Rate Model

Astralend calculates interest rates dynamically based on asset utilization:

* Low utilization → lower interest rates.
* High utilization → higher interest rates to incentivize repayments or additional deposits.
* Rate parameters include:

  * **Minimum rate** (base)
  * **Rate multiplier**
  * **Surge multiplier**
  * **Target utilization rate**

---

### 2. Lending & Borrowing

* **Lenders** supply supported assets to earn yield.
* **Borrowers** can take loans using supplied assets as collateral.
* Borrowers maintain a **health factor**—if it drops below the liquidation threshold, their positions can be liquidated.

---

### 3. Collateral & Liquidation

* Each supplied asset can be toggled on or off as collateral.
* Liquidators repay unhealthy positions to earn a **liquidation bonus** (e.g., 110% of repaid value).
* The protocol ensures users maintain a **minimum health factor** to remain solvent.

---

### 4. Market Tokenization

* Each resource market issues **Market Tokens** representing the user’s share of the lending pool.
* The **exchange rate** between Market Tokens and the underlying asset increases as interest accrues.

---

### 5. Protocol Governance & Fees

* The **system administrator** initializes pools and updates configurations.
* Fees and reserves are automatically accumulated to the protocol’s treasury.
* Configurable parameters include:

  * **System fee percentage**
  * **Liquidation penalty**
  * **Minimum health factor**
  * **Reserve and collateral factors**

---

## Core Data Structures

| Data Structure        | Purpose                                                  |
| --------------------- | -------------------------------------------------------- |
| `available-resources` | Stores all supported asset pools and parameters.         |
| `pool-tokens`         | Tracks metadata and circulating supply of market tokens. |
| `account-deposits`    | Records each user’s deposit and collateral status.       |
| `account-loans`       | Stores user borrowing information with interest indices. |
| `rate-model-data`     | Keeps per-asset interest and rate index data.            |
| `pricing-oracles`     | Links assets to oracle contracts for price feeds.        |

---

## Main Functions

### Administrative

* **`initialize-pool`**: Create a new lending market for a supported token.

### User Actions

* **`deposit-resource`**: Supply tokens to earn yield.
* **`withdraw-resource`**: Withdraw deposited tokens.
* **`toggle-backing`**: Enable or disable a deposit as collateral.
* **`borrow-resource`**: Borrow assets against collateral.
* **`repay-loan`**: Repay outstanding borrow amounts.
* **`liquidate-position`**: Liquidate undercollateralized accounts.

### Internal Logic

* **`calculate-interest`**: Accrues interest over time.
* **`calculate-usage-rate`**: Determines pool utilization.
* **`calculate-lending-rate`**: Adjusts interest rates dynamically.
* **`calculate-conversion-rate`**: Determines market token-to-asset exchange rates.
* **`get-wellness-factor`**: Measures borrower’s solvency health.

---

## Constants and Limits

| Constant                        | Description                                |
| ------------------------------- | ------------------------------------------ |
| `ERR-NOT-AUTHORIZED`            | Action restricted to admin.                |
| `ERR-POOL-NOT-ACTIVE`           | Market not available for trading.          |
| `ERR-INSUFFICIENT-COLLATERAL`   | User lacks sufficient collateral.          |
| `ERR-HEALTH-FACTOR-VIOLATION`   | Operation risks insolvency.                |
| `ERR-POSITION-NOT-LIQUIDATABLE` | Attempted liquidation of healthy position. |

---

## Interest Model Example

| Utilization Rate     | Borrow Rate                              |
| -------------------- | ---------------------------------------- |
| < Target (e.g., 75%) | Base + Linear growth via rate multiplier |
| > Target             | Base + Jump via surge multiplier         |

---

## Safety Mechanisms

* **Health Factor Enforcement**: Prevents users from over-borrowing.
* **Liquidation Triggers**: Automatically liquidates unsafe loans.
* **Accrued Interest Tracking**: Ensures all pool participants are fairly compensated.

---

## Deployment Notes

* Replace placeholder oracle and token contract principals with real deployed addresses.
* Ensure the **system administrator** principal is correctly configured before initializing markets.
* Price oracle integration must return consistent price data for accurate liquidation and borrowing behavior.

---

## Example Flow

1. **Initialize Pool**
   Admin calls `initialize-pool` with asset parameters.

2. **Deposit Tokens**
   User calls `deposit-resource` to earn yield and optionally enable collateralization.

3. **Borrow Assets**
   If collateralized, user calls `borrow-resource` to take out a loan.

4. **Accrue Interest**
   Interest accrues per block via `calculate-interest`.

5. **Repay or Liquidate**
   Borrowers repay loans using `repay-loan`.
   If health factor < 1.0, anyone can call `liquidate-position`.
