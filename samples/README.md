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
| [`onhomeroom-daily/`](onhomeroom-daily/) | `storage`, `network`, `agent` | Real-world daily bot for app.onhomeroom.com — challenge board, yes votes, chat replies, proposal pipeline. Every sentence is composed live by the chat agent via `zagents.agent.compose` (no templates), with setup commands on the first message (`setup <email> <password>`, `status`, `reset`) |

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
4. The module runs once: console output and the return value are posted
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
* `onhomeroom-daily` — after `setup <email> <password>`, one cycle per
  activation: challenge board lines, yes votes, at most one composed text
  per run, a run summary line. Run it in two chats with two different
  accounts and the sessions never mix.
