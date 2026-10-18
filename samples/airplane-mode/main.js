/**
 * Airplane Mode (root) — ZAgents chat module.
 *
 * Toggles Android airplane mode through the `device` permission
 * (`zagents.device.shell`, which runs `su -c <command>` on rooted
 * phones). Works from the very first message (module staged on the
 * draft) and mid-chat via the module command passthrough:
 *
 *   /airplane on      enable airplane mode (verified)
 *   /airplane off     disable airplane mode (verified)
 *   /airplane status  report the current state
 *
 * Requirements:
 *   - a ROOTED phone (su) — the module checks and reports otherwise;
 *   - ZAgents v1.31.0+;
 *   - Settings → Modules → "Device commands (root)" switched ON.
 *
 * Toggle strategy (robust across Android versions):
 *   1. preferred: `cmd connectivity airplane-mode enable|disable`
 *   2. fallback:  `settings put global airplane_mode_on 0|1` +
 *                 `am broadcast -a android.intent.action.AIRPLANE_MODE
 *                 --ez state true|false`
 *   3. verification: `settings get global airplane_mode_on` — the final
 *      report is always the ACTUAL device state, never an assumption.
 */
async function main() {
  const info = zagents.info || {};

  // Parse the command: "/airplane on" arrives as zagents.info.prompt on
  // the staged-module path AND on the mid-chat passthrough; a bare
  // activation (no message) defaults to a status report.
  const prompt = String(info.prompt || '').trim().toLowerCase();
  const parts = prompt.split(/\s+/).filter(Boolean);
  let arg = 'status';
  if (parts.length > 0) {
    if (parts[0] === '/airplane') {
      arg = parts[1] || 'status';
    } else if (parts[0] === 'on' || parts[0] === 'off' || parts[0] === 'status') {
      arg = parts[0];
    }
  }

  // SDK availability (older host without the device slice).
  if (!zagents.device || typeof zagents.device.shell !== 'function') {
    zagents.log('This module needs ZAgents v1.31.0+ (zagents.device SDK).');
    return { ok: false, reason: 'sdk-missing' };
  }

  const su = (cmd) => zagents.device.shell(cmd, { root: true, timeoutMs: 20000 });

  try {
    // -- Root check ---------------------------------------------------------
    const id = await su('id -u');
    if (!id.ok || id.stdout.trim().split(/\s+/).pop() !== '0') {
      const why = id.error || id.stderr.trim() || 'su unavailable or denied';
      zagents.log('Root check failed: ' + why);
      zagents.log('Airplane control requires a ROOTED device (su).');
      return { ok: false, reason: 'no-root', detail: why };
    }

    // -- State helpers ------------------------------------------------------
    const readState = async () => {
      const r = await su('settings get global airplane_mode_on');
      return r.ok && r.stdout.trim() === '1';
    };

    const current = await readState();

    if (arg === 'status' || (arg !== 'on' && arg !== 'off')) {
      zagents.log('Airplane mode: ' + (current ? 'ON' : 'OFF'));
      zagents.log('(commands: /airplane on | off | status)');
      return { ok: true, action: 'status', on: current };
    }

    const target = arg === 'on';
    if (current === target) {
      zagents.log('Airplane mode already ' + (target ? 'ON' : 'OFF') + ' — nothing to do.');
      return { ok: true, action: arg, changed: false, on: current };
    }

    // -- Toggle: preferred path --------------------------------------------
    let method = 'cmd connectivity';
    const cmd = await su('cmd connectivity airplane-mode ' + (target ? 'enable' : 'disable'));
    let now = await readState();

    // -- Toggle: fallback path ---------------------------------------------
    if (now !== target) {
      method = 'settings+broadcast';
      await su('settings put global airplane_mode_on ' + (target ? 1 : 0));
      await su(
        'am broadcast -a android.intent.action.AIRPLANE_MODE --ez state ' +
          (target ? 'true' : 'false'),
      );
      now = await readState();
    }

    // -- Verified report ----------------------------------------------------
    zagents.log('Airplane mode: ' + (now ? 'ON' : 'OFF') + ' (requested ' + arg.toUpperCase() + ')');
    zagents.log('Method: ' + method);
    zagents.log('Verified: settings get global airplane_mode_on → ' + (now ? 1 : 0));
    if (now !== target) {
      zagents.log('Warning: the device did not confirm the new state — some ROMs need a manual check.');
      return { ok: false, action: arg, on: now, method };
    }
    return { ok: true, action: arg, changed: true, on: now, method };
  } catch (e) {
    const message = e && e.message ? e.message : String(e);
    if (/Permission denied/i.test(message)) {
      zagents.log('Permission denied: declare "device" in module.json and approve it at activation.');
    } else if (/disabled/i.test(message)) {
      zagents.log(message);
      zagents.log('Enable "Device commands (root)" under Settings → Modules first.');
    } else {
      zagents.log('Airplane module failed: ' + message);
    }
    return { ok: false, reason: 'error', detail: message };
  }
}

module.exports = main();
