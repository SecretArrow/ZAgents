# Airplane Mode — sample ZAgents chat module

Controls Android **airplane mode** from the chat. Two modes, chosen per
device automatically — no blind trust anywhere: every report states the
ACTUAL verified state.

## Usage

1. Install the ZIP (Settings → Modules → Install module, or Files screen).
2. In any chat:
   * pick the module from the module picker, then type `/airplane on` as
     the first message — or simply type `/airplane on` at any point in a
     chat (the module auto-activates and runs — no LLM involved);
   * `/airplane off` disables it, `/airplane status` reports the state
     and the active mode (AUTO / MANUAL).

## AUTO mode — rooted phones

* Requires `su` (grant ZAgents) **and** Settings → Modules →
  **Device commands (root)** switched ON (off by default).
* `cmd connectivity airplane-mode enable|disable` first, fallback
  `settings put global airplane_mode_on 0|1` + legacy `AIRPLANE_MODE`
  broadcast, then a verification read-back.

## MANUAL mode — non-rooted phones (v1.32.0)

* No root needed; the state is read from the **world-readable native
  probe** (`zagents.device.airplane`), which works OFFLINE.
* `/airplane on` / `off` print the exact guided steps; the user flips the
  radio from Quick Settings, and `/airplane status` verifies the REAL
  state — a bare "yes" is never trusted.
* The commands run **app-side**, so they keep working while airplane mode
  is ON and the AI chat itself is unreachable.
* While airplane mode is ON the AI chat is offline (expected). Turn it
  back OFF when done: auto-retry (v1.30.0+) delivers the queued messages
  and the task continues automatically — no retry budget is burned while
  the radio is off. The agent can double-check the state with its
  `device_status` tool at any time.

## Requirements

* ZAgents v1.32.0+ (airplane probe + `device_status` agent tool).
* Rooted phone only for AUTO toggles; MANUAL mode works on any device.

Package and install: see [`../README.md`](../README.md).
