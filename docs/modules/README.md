# Module Documentation

Official documentation for **ZAgents chat modules** (plugins).

| Document | Language | Contents |
|---|---|---|
| [`sdk-reference-en.md`](sdk-reference-en.md) | English | Package layout, manifest, installation, full `zagents` API reference, isolation model, examples |
| [`sdk-reference-id.md`](sdk-reference-id.md) | Bahasa Indonesia | Same reference in Indonesian |

Both references ship **inside the app** as well: *Settings → Modules →
SDK docs* (language follows the app language).

## Related directories

* [`../sdk/`](../sdk/) — the official SDK (`zagents-sdk.js`, TypeScript
  definitions `index.d.ts`, `package.json`).
* [`../../samples/`](../../samples/) — complete, installable example
  modules covering every permission (`storage`, `network`, `files`,
  `chat`).

## Quick manifest checklist

- [ ] `name` — lowercase `[a-z0-9._-]`, max 40 chars (also the install
      directory name)
- [ ] `entry` — JavaScript entry point present in the ZIP (default
      `main.js`)
- [ ] `permissions` — request the minimum set the module needs
- [ ] `allowedHosts` — declare when the module talks to the network
- [ ] `timeoutSeconds` — raise only when the workload needs it
      (max 120)
