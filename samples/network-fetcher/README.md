# Network Fetcher (sample)

ZAgents chat module demonstrating the **`network`** permission with a
manifest `allowedHosts` allowlist.

* Manifest: `module.json` — requests `network` + `chat`, allows only
  `api.github.com` (subdomain wildcards like `*.example.com` are also
  supported by the bridge).
* Entry: `main.js` — `zagents.http.request`, `res.ok/status/text()`,
  progressive output via `zagents.chat.emit`.
* Security demo: changing the code to call any other host fails with
  `Host is not allowed by this module (allowedHosts)` — enforced by the
  native bridge, not by the module itself.

Package and install: see [`../README.md`](../README.md).
