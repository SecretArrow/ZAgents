/**
 * ZAgents Module SDK — official shim for chat modules.
 *
 * Inside a ZAgents chat session the runtime injects the `zagents` global
 * automatically. Requiring this shim is optional and equivalent:
 *
 *   const zagents = require('zagents-sdk');
 *
 * Every capability is permission-gated: the module manifest
 * (module.json) declares what it needs, the user approves at activation,
 * and unauthorized calls throw `Permission denied`.
 *
 * Full reference: docs/modules/sdk-reference-{en,id}.md (also shipped
 * in-app under Settings → Modules → SDK docs) — runnable examples in
 * samples/. Each chat session is a private window: storage, state,
 * config and processes never mix between chats.
 */
if (typeof zagents === 'undefined') {
  throw new Error(
    'zagents SDK is only available inside ZAgents chat sessions ' +
    '(run the module with /plugins or from the Modules screen).'
  );
}
module.exports = zagents;
