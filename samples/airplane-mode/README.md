# Airplane Mode (root) — sample ZAgents chat module

Controls Android **airplane mode** from the chat, through the `device`
permission (`zagents.device.shell` → `su -c <command>`). Works from the
first message of a fresh chat AND mid-chat, because the manifest declares
the **`airplane` slash command** (v1.31.0 module command passthrough).

## Usage

1. Install the ZIP (Settings → Modules → Install module, or Files screen).
2. Turn ON **Settings → Modules → Device commands (root)** (off by default).
3. In any chat:
   * pick the module from the module picker, then type `/airplane on` as
     the first message — or simply type `/airplane on` at any point in a
     chat (the module auto-activates and runs — no LLM involved);
   * `/airplane off` disables it, `/airplane status` reports the state.

## Requirements

* Rooted Android phone (`su` must grant ZAgents).
* ZAgents v1.31.0+.
* Toggling is **verified** against `settings get global airplane_mode_on`
  and the report shows the ACTUAL device state.

## How it toggles

1. `cmd connectivity airplane-mode enable|disable` (preferred);
2. fallback `settings put global airplane_mode_on 0|1` + legacy
   `AIRPLANE_MODE` broadcast;
3. verification read-back; the final message always states the real state.

Package and install: see [`../README.md`](../README.md).
