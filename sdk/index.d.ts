/**
 * TypeScript definitions for the ZAgents Module SDK.
 *
 * The `zagents` global is injected by the ZAgents runtime into every
 * chat-module execution. Adding this file (or installing the shim as a
 * dev dependency) gives IDE autocomplete and compile-time checking for
 * module sources — see `samples/` for complete working modules.
 *
 * Every capability below maps to a manifest permission (`module.json`):
 *   storage → zagents.storage      network → zagents.http
 *   files   → zagents.fs           chat    → zagents.chat
 *   agent   → zagents.agent        device  → zagents.device
 * Calling an API whose permission was not granted throws
 * `Permission denied: <permission>` at runtime.
 */

/** Metadata about the running module instance (always available). */
export interface ZAgentsInfo {
  /** Sanitized module name — same as the install directory. */
  name: string;
  /** Version from the manifest. */
  version: string;
  /** Display title from the manifest. */
  title: string;
  /** The chat session this execution belongs to (per-chat isolation key). */
  sessionId: string;
  /** Entry point that is executing (e.g. `main.js`). */
  entry: string;
  /**
   * The User-Agent identity this module presents — always the one the
   * user picked in Settings → User Agent. The same string is sent on
   * every `zagents.http` request and cannot be overridden by headers.
   */
  userAgent?: string;
  /**
   * The user message that activated this run — present only on the
   * staged-module path (module picked on a fresh draft, first message
   * sent). Use it for re-configuration commands (`setup ...`, `status`,
   * `reset`) on an already set-up chat.
   */
  prompt?: string;
  /**
   * Per-chat setup-form values the app collected before this run
   * (module.json `setup` block) — empty object when not set up yet.
   * The same values live under the cooperative storage key
   * `zagentsSetup`; other chats ask again by design.
   */
  setup?: Record<string, unknown>;
}

/** HTTP response returned by zagents.http.request. */
export interface ZAgentsHttpResponse {
  /** True when the status is in the 2xx range. */
  ok: boolean;
  /** HTTP status code. */
  status: number;
  /** Raw response body (string or parsed JSON when the bridge decoded it). */
  body: unknown;
  /** Lowercased response headers (repeated values joined with ", "). */
  headers: Record<string, string>;
  /** Body as text. */
  text(): Promise<string>;
  /** Body parsed as JSON (throws when the body is not valid JSON). */
  json(): Promise<unknown>;
}

export interface ZAgentsHttpRequestOptions {
  /** HTTP method — default `GET`. */
  method?: 'GET' | 'POST' | 'PUT' | 'DELETE' | 'PATCH' | string;
  /** Request body (stringified by the bridge). */
  body?: string | null;
  /** Extra request headers (hop-by-hop fields AND `User-Agent` are dropped
   *  by the bridge — the identity always comes from Settings → User Agent,
   *  readable via `zagents.info.userAgent`). */
  headers?: Record<string, string>;
  /** Whole-request cap in milliseconds (max 60000). */
  timeoutMs?: number;
  /** Return as soon as headers arrive — for SSE kick-off calls. */
  headOnly?: boolean;
}

/** Per-chat key/value store — never shared between chats. */
export interface ZAgentsStorage {
  /** Reads a value (null when absent). Permission: `storage`. */
  get(key: string): Promise<unknown>;
  /** Writes a value (64 KB per encoded value, 1 MB per chat+module). */
  set(key: string, value: unknown): Promise<void>;
  /** Lists all keys of THIS chat's store. */
  keys(): Promise<string[]>;
  /** Removes a key. */
  remove(key: string): Promise<void>;
}

/** Sandbox filesystem rooted at the module's per-chat `state/` directory. */
export interface ZAgentsFs {
  readFile(path: string): Promise<string>;
  writeFile(path: string, data: string): Promise<void>;
  appendFile(path: string, data: string): Promise<void>;
  readdir(path: string): Promise<string[]>;
  mkdir(path: string): Promise<void>;
  unlink(path: string): Promise<void>;
  stat(path: string): Promise<{
    isDirectory: boolean;
    size: number;
    modified: string;
  }>;
}

/** Options for zagents.agent.compose. */
export interface ZAgentsAgentComposeOptions {
  /** Short label of what is being composed (e.g. `chat-reply`). */
  task?: string;
  /** The LIVE context the sentence must fit into. Required. */
  context: string;
  /** Optional extra instruction from the module. */
  instruction?: string;
  /** Maximum words (default 24, clamped 1-40). */
  maxWords?: number;
  /** Recent texts the sentence must not repeat (max 20). */
  avoid?: string[];
  /** Allow one trailing period (proposal bodies). Default false. */
  trailingPeriod?: boolean;
}

/** Result of zagents.device.shell. */
export interface ZAgentsShellResult {
  /** True only when the process ran, was not killed by the timeout, and
   *  exited with code 0. */
  ok: boolean;
  /** Process exit code (-1 when the process could not start or was
   *  destroyed after the timeout). */
  exitCode: number;
  /** Standard output (capped by the host). */
  stdout: string;
  /** Standard error (capped by the host). */
  stderr: string;
  /** True when the process exceeded the time budget and was destroyed. */
  timedOut: boolean;
  /** Bridge-level failure (missing `su` binary, spawn error, ...). */
  error: string | null;
}

/** Options for zagents.device.shell. */
export interface ZAgentsShellOptions {
  /** Run through `su -c` — requires a rooted phone. Default false. */
  root?: boolean;
  /** Whole-command cap in milliseconds (1000–120000, default 30000). */
  timeoutMs?: number;
}

/** The SDK object injected as a global and exported by `zagents-sdk`. */
export interface ZAgentsSdk {
  /** Instance metadata. */
  readonly info: ZAgentsInfo;
  /** Console output captured into the module message (always available). */
  log(...args: unknown[]): Promise<void>;
  /** Post progressive output into the conversation. Permission: `chat`. */
  chat: {
    emit(text: string): Promise<void>;
  };
  /** Permission-gated HTTP through the app transport. Permission: `network`. */
  http: {
    request(
      url: string,
      options?: ZAgentsHttpRequestOptions,
    ): Promise<ZAgentsHttpResponse>;
  };
  /** Per-chat key/value store. Permission: `storage`. */
  storage: ZAgentsStorage;
  /** Per-chat sandboxed file access. Permission: `files`. */
  fs: ZAgentsFs;
  /**
   * Ask the chat's own agent to compose ONE sentence from live context.
   * The host enforces the composer rules (casual English, no forbidden
   * characters, word cap, no repeats) before returning.
   * Permission: `agent`.
   */
  agent: {
    compose(
      options: ZAgentsAgentComposeOptions,
    ): Promise<{ text: string }>;
  };
  /**
   * Run ONE shell command on the device (`sh -c`, or `su -c` with
   * `root: true`) — for rooted-phone automation such as airplane-mode
   * toggles. Gated twice: the manifest `device` permission AND the
   * Settings → Modules "Device commands" master switch (off by default).
   * Permission: `device`.
   */
  device: {
    shell(
      command: string,
      options?: ZAgentsShellOptions,
    ): Promise<ZAgentsShellResult>;
  };
}

/** Injected by the ZAgents runtime into every module execution. */
declare const zagents: ZAgentsSdk;
declare global {
  // eslint-disable-next-line no-var
  var zagents: ZAgentsSdk | undefined;
}

export = zagents;
