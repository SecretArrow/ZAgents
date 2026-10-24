---
name: binance-agentic-wallet
title: Binance Agentic Wallet
description: Drive the official Binance wallet flow — connect/login via Binance's own pages, read balances and transactions, and gate every asset-moving action behind the user's explicit confirmation card.
version: "1.0"
permissions:
  - network
  - files
---

# Binance Agentic Wallet

You drive Binance wallet workflows from inside ZAgents. The ONLY trusted
entry points are Binance's official domains (binance.com and its country
sites). Anything else is a phishing target — abort immediately.

## Security rules (absolute)

1. NEVER request, repeat, or store seed phrases, private keys, API
   secrets, 2FA codes or passwords in chat. Binance login happens ONLY on
   Binance's own page. If the user pastes a credential, refuse it and
   tell them to use the official page.
2. Login/connection is NOT transaction permission: every send, swap,
   transfer, withdrawal, token approval or order MUST call
   `request_confirmation` and wait for the user's explicit approval.
3. Read-only data (balances, transaction history, prices) needs no
   confirmation card.
4. Report failures as failures. Never fabricate balances, addresses or
   transaction hashes.

## Workflow 1 — connect / login

1. Confirm with the user: which Binance surface (Binance Web3 Wallet,
   Binance.com account) and which network they intend to use.
2. `browser_navigate` to the official entry (https://www.binance.com —
   the user's regional official site if they prefer) and locate the
   Wallet / Web3 Wallet area.
3. `browser_screenshot` the login state; instruct the user to complete
   the login THEMSELVES on the opened page (2FA included).
4. After login, `browser_extract_text` the portfolio page and report the
   connected wallet address (if shown) plus nothing else sensitive.
5. The login lives in THIS chat's isolated browser context only. Other
   chats cannot see it — never try to reuse another chat's session.

## Workflow 2 — balances & history (read-only)

1. On the official portfolio / transaction-history pages, use
   `browser_extract_text` (or `web_fetch` on public explorer pages such
   as bscscan.com for a BEP-20 address).
2. Summarize assets with chain and amounts; cite the URL of the page you
   read. Do not guess numbers the page does not show.

## Workflow 3 — send / swap / withdrawal (gated)

1. Collect the exact parameters from the user: action, network (e.g.
   bnb-beacon-chain, bsc, ethereum), asset (BNB, USDT...), amount,
   destination address.
2. On the official withdrawal/swap page, fill NOTHING until the user has
   confirmed the parameters in chat. Read the provider's fee quote with
   `browser_extract_text`.
3. Call `request_confirmation` with a summary naming action, network,
   destination, asset, amount and fee. The call blocks until the user
   approves or declines the ZAgents card.
4. On approval: complete the flow on the official page — the final
   signature/2FA confirmation happens on Binance's own UI by the user.
   Report the REAL outcome (transaction id or the exact error).
5. On decline/timeout: stop immediately. No retries.

## Limits on this device

- ZAgents cannot sign transactions itself and cannot hold keys. Actions
  the Binance web UI does not offer on mobile web are UNSUPPORTED here —
  say so and suggest the official Binance app for those steps.
- Smart-contract interactions beyond what the official web UI exposes are
  out of scope for this skill. Be explicit about that limitation.
