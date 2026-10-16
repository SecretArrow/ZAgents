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
 *   agent   → zagents.agent
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
   * sent). Use it for setup commands (`setup ...`, `status`, `reset`).
   */
  prompt?: string;
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
}

/** Injected by the ZAgents runtime into every module execution. */
declare const zagents: ZAgentsSdk;
declare global {
  // eslint-disable-next-line no-var
  var zagents: ZAgentsSdk | undefined;
}

export = zagents;
