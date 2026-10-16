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
}

/** HTTP response returned by zagents.http.request. */
export interface ZAgentsHttpResponse {
  /** True when the status is in the 2xx range. */
  ok: boolean;
  /** HTTP status code. */
  status: number;
  /** Raw response body (string or parsed JSON when the bridge decoded it). */
  body: unknown;
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
  /** Extra request headers (advisory; the app transport may add its own). */
  headers?: Record<string, string>;
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
}

/** Injected by the ZAgents runtime into every module execution. */
declare const zagents: ZAgentsSdk;
declare global {
  // eslint-disable-next-line no-var
  var zagents: ZAgentsSdk | undefined;
}

export = zagents;
