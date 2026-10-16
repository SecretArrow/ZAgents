# ZAgents Module SDK (v1.21.1)

Official guide for building **chat modules**: JavaScript packages that run
natively inside a ZAgents chat session, isolated per chat like a browser
private window.

Where things live in this repository:

| Path | Contents |
|---|---|
| `sdk/` | Official SDK — `zagents-sdk.js` shim, `index.d.ts` TypeScript definitions, `package.json` |
| `samples/` | Complete, installable example modules (counter, network fetcher, file notes, chat streamer) |
| `docs/modules/` | This reference (English + Bahasa Indonesia) — also shipped in-app |

## 1. Package layout

A module is a ZIP archive:

```
my-module.zip
├── module.json        (manifest — recommended)
├── main.js            (entry point, default)
├── lib/util.js        (any extra files, required relatively)
└── node_modules/…     (optional; or use packages installed via npm tools)
```

### Manifest — `module.json`

```json
{
  "name": "my-module",
  "version": "1.0.0",
  "title": "My Module",
  "description": "What the module does for the user.",
  "entry": "main.js",
  "permissions": ["storage", "network", "files", "chat"],
  "allowedHosts": ["api.example.com"],
  "timeoutSeconds": 30
}
```

| Field | Required | Notes |
|---|---|---|
| `name` | yes | Lowercase `[a-z0-9._-]`, max 40 chars. Also the install directory name. |
| `version` | — | Shown in the Modules screen. |
| `title` | — | Display name (defaults to `name`). |
| `description` | — | Shown to the user and injected into the chat context. |
| `entry` | — | Entry point, default `main.js`. |
| `permissions` | — | `storage`, `network`, `files`, `chat` — the user approves each activation. |
| `allowedHosts` | — | Restrict `zagents.http` to these hosts (`*.example.com` allows subdomains). Omit for any host. |
| `timeoutSeconds` | — | Execution budget per run (30 default, 120 max). |

Without `module.json`, a `package.json` (`name`, `version`, `main`) is
honored; with neither, the ZIP file name becomes the module name.

## 2. Installing and running

1. **Modules screen** → *Install module* → pick the ZIP.
2. Run it inside a chat:
   * Type **`/plugins`** → pick the module from the interactive menu, or
   * Type **`/plugins my-module`**, or
   * Select it as a chip on the new-chat screen, or
   * Modules screen → module → *Start in new chat*.
3. The entry point executes once per activation. Console output and the
   return value are posted into the conversation as a module message; the
   agent can read and discuss it.

## 3. The `zagents` SDK

Available as a global — or `const zagents = require('zagents-sdk')`.

### `zagents.info`
Metadata: `name`, `version`, `title`, `sessionId`, `entry`.

### `zagents.log(...)` — always available
Console output, captured into the module message.

### `zagents.storage` — permission `storage`
Per-chat key/value store. Different chats NEVER share it.

```js
await zagents.storage.set('visits', 1);
const visits = await zagents.storage.get('visits'); // 1
const keys = await zagents.storage.keys();          // ['visits']
await zagents.storage.remove('visits');
```

Caps: 64 KB per value, 1 MB per (chat, module) store.

### `zagents.fs` — permission `files`
File access confined to the module's per-chat `state/` directory.

```js
await zagents.fs.writeFile('note.txt', 'hello');
const text = await zagents.fs.readFile('note.txt');
await zagents.fs.appendFile('note.txt', '\nmore');
const files = await zagents.fs.readdir('.');
await zagents.fs.mkdir('sub');
await zagents.fs.unlink('note.txt');
const info = await zagents.fs.stat('sub'); // { isDirectory, size, modified }
```

Paths outside the state directory are rejected.

### `zagents.http` — permission `network`
HTTP through the app (status + body), optionally host-restricted.

```js
const res = await zagents.http.request('https://api.example.com/data', {
  method: 'POST',
  body: JSON.stringify({ q: 'hi' }),
});
if (res.ok) {
  const data = await res.json();
}
```

### `zagents.chat` — permission `chat`
Post progressive output into the conversation while running:

```js
await zagents.chat.emit('Step 1 done…');
```

## 4. Isolation model (private window per chat)

* **Process** — every execution boots a fresh JS context; nothing
  survives between runs.
* **State & storage** — `<session>/modules/<name>/` is created per chat;
  `storage.json` and `state/` are invisible to every other chat and to
  other modules.
* **Permissions** — declared in the manifest, approved by the user at
  activation, enforced twice (SDK + Dart bridge).
* **Network** — requires `network`; `allowedHosts` narrows it further.
* **Resources** — timeout, output caps, storage caps.
* **Termination** — deactivating a module or stopping the chat cancels a
  live run safely: delivery stops, persisted state is kept.

## 5. Minimal example

The same example, ready to install, lives at [`samples/counter/`](../../samples/counter/)
— together with three more complete samples covering every permission:

| Sample | Demonstrates |
|---|---|
| [`samples/counter/`](../../samples/counter/) | `storage` — per-chat activation counter |
| [`samples/network-fetcher/`](../../samples/network-fetcher/) | `network` — `zagents.http` + `allowedHosts` |
| [`samples/file-notes/`](../../samples/file-notes/) | `files` — sandboxed note taking under `state/` |
| [`samples/chat-streamer/`](../../samples/chat-streamer/) | `chat` — progressive `chat.emit` output |

`module.json`

```json
{
  "name": "hello-counter",
  "version": "1.0.0",
  "title": "Hello Counter",
  "description": "Counts activations per chat.",
  "permissions": ["storage"]
}
```

`main.js`

```js
async function main() {
  const previous = (await zagents.storage.get('count')) || 0;
  await zagents.storage.set('count', previous + 1);
  zagents.log('Hello from the module! Count in THIS chat: ' + (previous + 1));
  return { count: previous + 1 };
}
module.exports = main();
```
