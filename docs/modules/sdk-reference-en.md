# ZAgents Module SDK (v1.24.2)

Official guide for building **chat modules**: JavaScript packages that run
natively inside a ZAgents chat session, isolated per chat like a browser
private window.

Where things live in this repository:

| Path | Contents |
|---|---|
| `sdk/` | Official SDK — `zagents-sdk.js` shim, `index.d.ts` TypeScript definitions, `package.json` |
| `samples/` | Complete, installable example modules (counter, network fetcher, file notes, chat streamer, onhomeroom daily) |
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
  "timeoutSeconds": 30,
  "setup": {
    "title": "My Module account",
    "description": "Collected once per chat before the first run.",
    "fields": [
      { "key": "username", "label": "Username", "type": "text", "required": true },
      { "key": "password", "label": "Password", "type": "password", "required": true },
      { "key": "retries", "label": "Max retries", "type": "number" },
      { "key": "verbose", "label": "Verbose logging", "type": "boolean" }
    ]
  }
}
```

| Field | Required | Notes |
|---|---|---|
| `name` | yes | Lowercase `[a-z0-9._-]`, max 40 chars. Also the install directory name. |
| `version` | — | Shown in the Modules screen. |
| `title` | — | Display name (defaults to `name`). |
| `description` | — | Shown to the user and injected into the chat context. |
| `entry` | — | Entry point, default `main.js`. |
| `permissions` | — | `storage`, `network`, `files`, `chat`, `agent` — the user approves each activation. |
| `allowedHosts` | — | Restrict `zagents.http` to these hosts (`*.example.com` allows subdomains). Omit for any host. |
| `timeoutSeconds` | — | Execution budget per run (30 default, 120 max). |
| `setup` | — | Per-chat setup form — see below. |

Without `module.json`, a `package.json` (`name`, `version`, `main`) is
honored; with neither, the ZIP file name becomes the module name.

### Setup form — module.json `setup`

Declare the user input your module needs and the app collects it with a
**per-chat form BEFORE the module's first run in that chat** — no failed
first cycle, no `setup <…>` parsing required:

* `title`, `description` — form heading and helper line (optional).
* `fields` — up to 12 entries. Each field: `key` (machine name,
  `[a-z0-9_]`, max 40), `label`, `type` (`text`, `password`, `number`,
  `boolean`), `required`, `placeholder`, `description`.
* While any **required** field is unfilled for this chat, the host keeps
  the module from executing and shows the form instead; submitting it
  saves the values and runs the module automatically.
* Values live in the (chat, module) storage under the cooperative key
  `zagentsSetup` — written by the host on submit, and mirrored by the
  module itself when it changes its configuration another way (e.g. a
  text-command setup), so the gate always reflects reality. Other chats
  ask again: setup is per chat by design.
* Read the values in the module via `zagents.info.setup` (see below) or
  `await zagents.storage.get('zagentsSetup')`.
* A manifest without a `setup` block (or without required fields) never
  triggers the form — behavior is unchanged for existing modules.

## 2. Installing and running

1. **Modules screen** → *Install module* → pick the ZIP.
2. Run it inside a chat:
   * Type **`/plugins`** → pick the module from the interactive menu, or
   * Type **`/plugins my-module`**, or
   * Select it as a chip on the new-chat screen, or
   * Modules screen → module → *Start in new chat*.

### Building a module FROM chat — `/make_plugins`

Since v1.27.0 the chat agent can build a module for you inside a running
chat: type **`/make_plugins <description>`** (aliases `/make_plugin`,
`/make_module`). The agent writes the module folder, self-checks it,
packs the zip and calls `module_stage_repair`; you confirm the install
on the card. Reference session data (uploads, workspace files, earlier
messages) in your description and it gets copied INTO the module —
modules cannot read the chat workspace at runtime, so the zip is always
self-contained.

3. The entry point executes once per activation. Console output and the
   return value are posted into the conversation as a module message; the
   agent can read and discuss it.
   **Shebang-friendly:** a leading `#!...` line (Node-style shebang) and a
   UTF-8 BOM are stripped automatically before the source runs, so scripts
   copied straight from a Node project work as-is.
   **Setup-first:** when the manifest declares required setup fields, the
   app shows the per-chat setup form instead of running the module; the
   run happens right after the form is submitted (see above).
   **Setup tip:** when a module is selected on a NEW chat (staged), the
   first message you send is exposed to the module as `zagents.info.prompt`
   — modules can still implement commands like `setup <credentials>`,
   `status` or `reset` on that message for re-configuring an already
   set-up chat.

## 3. The `zagents` SDK

Available as a global — or `const zagents = require('zagents-sdk')`.

### `zagents.info`
Metadata: `name`, `version`, `title`, `sessionId`, `entry` — plus `prompt`
(the activating user message) when the run was triggered by a staged
module's first message, `userAgent` — the identity the user picked in
Settings → User Agent — and `setup`: the per-chat setup-form values
submitted for this chat (empty object when not set up yet).

**User-Agent policy:** modules always present the identity configured in
Settings → User Agent. `zagents.http` sends it on every request, and a
module-supplied `User-Agent` header is dropped by the bridge — the
setting wins, always. Read the active identity via
`zagents.info.userAgent` (for display or debugging only).

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
HTTP through the app (status + body + response headers), optionally
host-restricted by the manifest `allowedHosts`.

```js
const res = await zagents.http.request('https://api.example.com/data', {
  method: 'POST',
  body: JSON.stringify({ q: 'hi' }),
  headers: { 'Content-Type': 'application/json' },
});
if (res.ok) {
  const data = await res.json();
  const cookie = res.headers['set-cookie']; // lowercased response headers
}
```

Options: `method`, `body`, `headers` (hop-by-hop fields like `Host` and
`Connection` are dropped; `User-Agent` is dropped too — requests always
carry the Settings → User Agent identity, see `zagents.info.userAgent`),
`timeoutMs` (whole-request cap, max 60000) and
`headOnly: true` — return as soon as the status line + headers arrive,
without reading the body (kick off an SSE stream without waiting for it
to end).

### `zagents.agent` — permission `agent`
Ask the chat's own agent (the provider/model configured for THIS chat) to
compose ONE short casual English sentence from the live context your
module supplies. There are no templates: every sentence is generated at
the moment it is needed, and the host enforces the composer contract
before the module sees the text:

* exactly one sentence, casual, human-sounding, English;
* never contains `!` `:` `;` `—` `–` `?` and no emoji;
* at most `maxWords` words (default 24, clamp 1–40);
* never repeats anything passed in `avoid` (recent texts);
* a corrective retry happens automatically, then a deterministic
  sanitize pass — outputs that still violate the rules raise an error so
  the module can skip that action gracefully.

```js
const { text } = await zagents.agent.compose({
  task: 'chat-reply',
  context: recentChatLines.join('\n'),
  instruction: 'react to the last message',
  maxWords: 16,
  avoid: recentSentTexts,
});
```

Failures (no API key, provider down, repeated violations) throw — wrap
the call in try/catch and skip the text action when composition is not
possible.

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
* **Agent** — requires `agent`; generation goes through the chat's own
  LLM plus the host-side composer gate, so module output stays inside
  the regulated contract.
* **Resources** — timeout, output caps, storage caps.
* **Termination** — deactivating a module or stopping the chat cancels a
  live run safely: delivery stops, persisted state is kept.

## 5. Minimal example

The same example, ready to install, lives at [`samples/counter/`](../../samples/counter/)
— together with more complete samples covering every permission:

| Sample | Demonstrates |
|---|---|
| [`samples/counter/`](../../samples/counter/) | `storage` — per-chat activation counter |
| [`samples/network-fetcher/`](../../samples/network-fetcher/) | `network` — `zagents.http` + `allowedHosts` |
| [`samples/file-notes/`](../../samples/file-notes/) | `files` — sandboxed note taking under `state/` |
| [`samples/chat-streamer/`](../../samples/chat-streamer/) | `chat` — progressive `chat.emit` output |
| [`samples/onhomeroom-daily/`](../../samples/onhomeroom-daily/) | `agent` — real-world daily bot whose every sentence is composed by the chat agent; per-chat setup form for its account |

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
