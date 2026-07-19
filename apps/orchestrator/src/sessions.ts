import type { EventFrame, EventDraft } from "@code-free/protocol";
import { EventStore, type SessionRow } from "@code-free/store";

export type SessionSummary = {
  id: string;
  title: string | null;
  cwd: string;
  harnessId: string | null;
  model: string | null;
  createdAt: string;
  updatedAt: string;
  lastSeq: number;
};

/**
 * Session manager: durable state via EventStore; no adapter host in Phase 1.
 */
export class SessionManager {
  constructor(private readonly store: EventStore) {}

  create(input: {
    cwd: string;
    title?: string;
    harnessId?: string;
    model?: string;
    seed?: string;
  }): { session: SessionSummary; started: EventFrame } {
    const row = this.store.createSession({
      cwd: input.cwd,
      title: input.title,
      harnessId: input.harnessId,
      model: input.model,
    });
    const started = this.store.appendEvent(row.id, {
      type: "session.started",
      payload: {
        cwd: row.cwd,
        harnessId: row.harnessId,
        model: row.model,
        seed: input.seed ?? null,
      },
    });
    return { session: this.toSummary(row), started };
  }

  list(): SessionSummary[] {
    return this.store.listSessions().map((r) => this.toSummary(r));
  }

  get(sessionId: string): SessionSummary | null {
    const row = this.store.getSession(sessionId);
    return row ? this.toSummary(row) : null;
  }

  rename(sessionId: string, title: string): SessionSummary {
    return this.toSummary(this.store.renameSession(sessionId, title));
  }

  append(sessionId: string, draft: EventDraft): EventFrame {
    return this.store.appendEvent(sessionId, draft);
  }

  eventsAfter(sessionId: string, afterSeq: number): EventFrame[] {
    return this.store.listEventsAfter(sessionId, afterSeq);
  }

  lastSeq(sessionId: string): number {
    return this.store.lastSeq(sessionId);
  }

  /**
   * Phase 1: no adapter. Persist user message and a clear session.error so UI
   * is honest rather than hanging on a fake turn.
   */
  sendUserMessage(sessionId: string, text: string): EventFrame[] {
    if (!this.store.getSession(sessionId)) {
      throw new SessionError("session_not_found", `Session not found: ${sessionId}`);
    }
    const user = this.store.appendEvent(sessionId, {
      type: "message.user",
      payload: { text, id: cryptoRandomId() },
    });
    const err = this.store.appendEvent(sessionId, {
      type: "session.error",
      payload: {
        code: "no_adapter",
        message:
          "No harness adapter configured (Phase 1). User message was recorded; attach an adapter in a later phase.",
      },
    });
    return [user, err];
  }

  cancel(sessionId: string): EventFrame {
    if (!this.store.getSession(sessionId)) {
      throw new SessionError("session_not_found", `Session not found: ${sessionId}`);
    }
    return this.store.appendEvent(sessionId, {
      type: "session.ended",
      payload: { reason: "cancel", note: "No active turn (Phase 1 stub)" },
    });
  }

  private toSummary(row: SessionRow): SessionSummary {
    return {
      id: row.id,
      title: row.title,
      cwd: row.cwd,
      harnessId: row.harnessId,
      model: row.model,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      lastSeq: this.store.lastSeq(row.id),
    };
  }
}

export class SessionError extends Error {
  readonly code: string;
  constructor(code: string, message: string) {
    super(message);
    this.name = "SessionError";
    this.code = code;
  }
}

function cryptoRandomId(): string {
  return globalThis.crypto.randomUUID();
}
