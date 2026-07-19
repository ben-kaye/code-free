import type { Cap, EventDraft } from "@code-free/protocol";

/**
 * Orch stamps seq/ts after durable append. Adapters emit drafts only.
 */
export type EventSink = {
  /**
   * May throw on durability/host failure; adapters must not swallow.
   * Orch stamps seq/ts after durable append.
   */
  emit(draft: EventDraft): void;
  /** Optional lossy/debug line from the harness (never secrets). */
  emitRaw?(line: string): void;
};

/**
 * Spec for starting (or resuming) a harness run for one Code Free session.
 * Policy is orch-owned (not a TaskSpec field); may pass via `extra` until a typed handoff exists.
 */
export type TaskSpec = {
  sessionId: string;
  cwd: string;
  /**
   * Model id, or composite `id#effort` when thinking level is selected.
   * Adapters that support effort parse the suffix; unknown suffixes are ignored.
   */
  model?: string;
  /** Harness-side session id when resuming (e.g. Grok ACP sessionId). */
  resumeToken?: string;
  extra?: Record<string, unknown>;
};

/** One selectable thinking / reasoning effort for a model (X-axis of the picker matrix). */
export type ReasoningEffortInfo = {
  id: string;
  label?: string;
  /** True when this is the harness default for the model. */
  default?: boolean;
};

/**
 * Model catalog entry from adapter `listModels`.
 * Rows in the shell matrix; optional `reasoningEfforts` are the thinking-level columns.
 */
export type ModelInfo = {
  id: string;
  name?: string;
  /** When present and non-empty, shell shows a thinking-level axis. */
  reasoningEfforts?: ReasoningEffortInfo[];
  /** Preferred effort id when the user has not chosen one. */
  defaultReasoningEffort?: string;
};

/**
 * One live harness process (or equivalent) bound to a session.
 * One active turn at a time; send rejects or queues only if the adapter documents it.
 */
export type AdapterRun = {
  send(text: string): Promise<void>;
  cancel(): Promise<void>;
  approve?(approvalId: string, decision: "allow" | "deny"): Promise<void>;
  /** Kill child / free resources. Idempotent. */
  dispose(): Promise<void>;
  /** Current harness resume token, if known. */
  resumeToken?: string;
};

/**
 * Factory for a harness. No UI; maps harness I/O ↔ EventDraft via EventSink.
 */
export type HarnessAdapter = {
  readonly id: string;
  readonly name: string;
  /** Mutable Cap[] so it assigns directly to protocol HarnessInfo.caps. */
  readonly caps: Cap[];
  start(spec: TaskSpec, sink: EventSink): Promise<AdapterRun>;
  listModels?(): Promise<ModelInfo[]>;
};

export type AdapterErrorCode =
  | "binary_not_found"
  | "spawn_failed"
  | "turn_in_progress"
  | "not_running"
  | "harness_error"
  | "protocol_error";

export class AdapterError extends Error {
  readonly code: AdapterErrorCode;

  constructor(code: AdapterErrorCode, message: string) {
    super(message);
    this.name = "AdapterError";
    this.code = code;
  }
}
