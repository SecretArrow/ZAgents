# Sample Chat Modules

Complete, installable example modules for ZAgents. Each folder is a
ready-to-package module demonstrating one slice of the official SDK —
see [`../docs/modules/`](../docs/modules/) for the full reference and
[`../sdk/`](../sdk/) for the SDK itself.

| Sample | Permissions | Demonstrates |
|---|---|---|
| [`counter/`](counter/) | `storage` | Per-chat key/value store — the counter restarts at zero in every other chat (private-window isolation) |
| [`network-fetcher/`](network-fetcher/) | `network`, `chat` | `zagents.http.request` through the app transport, restricted by a manifest `allowedHosts` allowlist (`api.github.com` only) |
| [`file-notes/`](file-notes/) | `files` | Sandboxed filesystem under the per-chat `state/` directory: mkdir / appendFile / readFile / readdir / stat |
| [`chat-streamer/`](chat-streamer/) | `chat` | Progressive output into the conversation with `zagents.chat.emit` |
| [`onhomeroom-daily/`](onhomeroom-daily/) | `storage`, `network`, `agent` | Real-world daily bot for app.onhomeroom.com — challenge board, yes votes, chat replies, proposal pipeline. Every sentence is composed live by the chat agent via `zagents.agent.compose` (no templates). The app collects the account with a per-chat setup form before the first run (`zagents.info.setup`); text commands (`setup <email> <password>`, `status`, `reset`) still re-configure an already set-up chat |
| [`airplane-mode/`](airplane-mode/) | `device` | Android airplane mode + carrier IP rotation: **CYCLE** — the one-command IP rotation `/airplane cycle` (aliases `ip`, `rotate`) via `zagents.device.airplaneCycle` (v1.34.0): airplane ON → hold → OFF → settle; the radio re-registers with a NEW IP and the cycle always ends OFF/online (rooted, needs the "Device commands (root)" switch). **AUTO** toggle via `zagents.device.shell` (`su -c`) on rooted phones, **MANUAL** guided mode on non-rooted ones — the state is always verified with the world-readable `zagents.device.airplane` probe (no root, works offline). Driven by the `/airplane cycle \| on \| off \| status` slash commands — the manifest `commands` field routes the message to the module instead of the LLM, and the commands keep working while airplane mode is ON |
| [`evm-wallet/`](evm-wallet/) | `storage`, `network`, `chat` | Full per-chat EVM wallet via `/wallet` slash commands: GENERATE-ONLY accounts (fresh random key per chat — no import, no seed phrases, aligned with the app's Web3 red lines), EIP-55 checksum addresses, native + ERC-20 balances, gas price, 10 verified networks (Ethereum, Sepolia, BSC, Polygon, Arbitrum, Base, OP Mainnet + 3 testnets; default Sepolia), and EIP-155 signed transfers (pure-JS Keccak-256 / secp256k1 / RFC 6979 / RLP, zero npm deps) with a mandatory two-step confirm — `/wallet send` prints the FULL summary, `/wallet confirm` signs + broadcasts, `/wallet cancel` discards. Allowlist-restricted JSON-RPC via `zagents.http`; the canonical EIP-155 spec vector is reproduced byte-for-byte in the module test harness |

## Ready-made ZIPs — download and install directly

Every sample also ships pre-packaged **next to its folder** as
`<name>.zip` (`counter.zip`, `network-fetcher.zip`, `file-notes.zip`,
`chat-streamer.zip`, `onhomeroom-daily.zip`, `airplane-mode.zip`,
`evm-wallet.zip`).
Download one, then install
it via **Settings → Modules → Install module** — no packaging needed.
A test guards these archives: each `<name>.zip` must always match its
folder exactly, so they can never silently go stale. To rebuild one by
hand, see the packaging section below.

## Package a sample into an installable ZIP

The app installs modules from ZIP archives. From the repository root:

```bash
# Flat layout (module.json at the ZIP root):
cd samples/counter && zip -r ../../hello-counter.zip . && cd ../..

# or zip the FOLDER — the app unwraps a single top-level directory
# automatically (same layout as a GitHub "Download ZIP"):
cd samples && zip -r ../counter.zip counter && cd ..
```

On Windows: right-click the sample folder → *Send to → Compressed
(zipped) folder* — both layouts install fine.

## Install and run

1. ZAgents app → **Settings → Modules → Install module** → pick the ZIP.
2. Start a chat, then either:
   - type **`/plugins`** and pick the module from the interactive menu,
   - type **`/plugins hello-counter`** (module `name` from the manifest),
   - or tap the module chip on the new-chat screen.
3. Approve the requested permissions in the activation dialog.
4. Modules that declare a `setup` block (onhomeroom-daily) show a
   per-chat setup form first — fill it once and the module runs right
   after; other chats ask again by design.
5. The module runs once: console output and the return value are posted
   into the conversation with a module badge; the agent can read and
   discuss them.

## Expected output highlights

* `hello-counter` — run it twice in the same chat: the count goes
  1 → 2. Open a different chat and run it again: it starts from 1.
  That difference *is* the per-chat isolation guarantee.
* `network-fetcher` — posts the fetched quote into the conversation;
  editing the code to hit another host fails with
  `Host is not allowed by this module (allowedHosts)`.
* `file-notes` — every activation appends one timestamp line to
  `state/notes/session.txt`; the file lives per chat and per module.
* `chat-streamer` — three step messages appear progressively while the
  module runs.
* `onhomeroom-daily` — after the per-chat setup form (email + password),
  one cycle per activation: challenge board lines, yes votes, at most one
  composed text per run, a run summary line. Run it in two chats with two
  different accounts and the sessions never mix.
* `airplane-mode` — type `/airplane status` (or `on` / `off`) in a chat:
  the module runs directly (no LLM turn) and reports the verified
  airplane state. Rooted phones toggle automatically; non-rooted phones
  get the guided MANUAL steps (flip the radio in Quick Settings, then
  re-run `/airplane status` — the probe verifies the real state, a bare
  "yes" is never trusted). `/airplane cycle` (v1.3, aliases `ip` /
  `rotate`) rotates the carrier IP in ONE command: airplane ON → hold →
  OFF → settle, verified, always ends OFF — online with a fresh IP. The
  commands keep working while airplane mode is ON; when the radio comes
  back, auto-retry continues the chat.
* `evm-wallet` — `/wallet create` mints a fresh per-chat account (testnet
  by default); `/wallet send 0x… 0.05` prints the full transaction
  summary and waits: `/wallet confirm` signs with the chat's own key and
  broadcasts (hash + explorer link), `/wallet cancel` discards, and a
  pending offer never survives a network switch. Balances, gas price,
  ERC-20 tokens and receipts are read from the allowlisted public RPCs.
