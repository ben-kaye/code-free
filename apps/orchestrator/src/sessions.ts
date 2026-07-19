import type { EventFrame, EventDraft } from "@code-free/protocol";
import { AdapterError } from "@code-free/adapter-core";
import {
  EventStore,
  StoreError,
  ARCHIVE_RETENTION_MS,
  type SessionRow,
  type SessionListFilter,
} from "@code-free/store";
import type { AdapterHost } from "./adapter-host.js";

export type SessionSummary = {
  id: string;
  title: string | null;
  cwd: string;
  harnessId: string | null;
  model: string | null;
  createdAt: string;
  updatedAt: string;
  lastSeq: number;
  /** Present when the session is archived (soft-deleted). */
  archivedAt: string | null;
};

/**
 * Session manager: durable state via EventStore; turns via AdapterHost when present.
 */
export class SessionManager {
  constructor(
    private readonly store: EventStore,
    private readonly host: AdapterHost | null = null,
  ) {}

  create(input: {
    cwd: string;
    title?: string;
    harnessId?: string;
    model?: string;
    seed?: string;
  }): { session: SessionSummary; started: EventFrame } {
    let harnessId = input.harnessId;
    if (!harnessId && this.host) {
      harnessId = this.host.defaultHarnessId();
    }
    if (harnessId && this.host && !this.host.getAdapter(harnessId)) {
      throw new SessionError("unknown_harness", `Unknown harness: ${harnessId}`);
    }

    const row = this.store.createSession({
      cwd: input.cwd,
      title: input.title,
      harnessId,
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

  list(filter: SessionListFilter = "active"): SessionSummary[] {
    return this.store.listSessions(filter).map((r) => this.toSummary(r));
  }

  get(sessionId: string): SessionSummary | null {
    const row = this.store.getSession(sessionId);
    return row ? this.toSummary(row) : null;
  }

  rename(sessionId: string, title: string): SessionSummary {
    try {
      return this.toSummary(this.store.renameSession(sessionId, title));
    } catch (err) {
      throw mapStoreError(err);
    }
  }

  archive(sessionId: string): SessionSummary {
    try {
      // Best-effort dispose of live harness
      void this.host?.disposeSession(sessionId);
      return this.toSummary(this.store.archiveSession(sessionId));
    } catch (err) {
      throw mapStoreError(err);
    }
  }

  /** Drop archives older than 7 days. Returns count deleted. */
  purgeExpiredArchives(): number {
    return this.store.purgeExpiredArchives(ARCHIVE_RETENTION_MS);
  }

  append(sessionId: string, draft: EventDraft): EventFrame {
    try {
      return this.store.appendEvent(sessionId, draft);
    } catch (err) {
      throw mapStoreError(err);
    }
  }

  eventsAfter(sessionId: string, afterSeq: number): EventFrame[] {
    return this.store.listEventsAfter(sessionId, afterSeq);
  }

  lastSeq(sessionId: string): number {
    return this.store.lastSeq(sessionId);
  }

  /**
   * Persist user message + turn_start, ensure harness run, return immediate frames.
   * The actual turn continues asynchronously via `driveTurn` (caller must kick it).
   */
  beginUserMessage(
    sessionId: string,
    text: string,
  ): { events: EventFrame[]; driveTurn: (() => Promise<void>) | null } {
    try {
      const row = this.store.getSession(sessionId);
      if (!row) {
        throw new SessionError("session_not_found", `Session not found: ${sessionId}`);
      }
      if (row.archivedAt) {
        throw new SessionError("session_archived", `Session is archived: ${sessionId}`);
      }

      const user = this.store.appendEvent(sessionId, {
        type: "message.user",
        payload: { text, id: cryptoRandomId() },
      });

      // No adapter host or no harness → honest no_adapter (Phase 1 path)
      if (!this.host || !row.harnessId || !this.host.getAdapter(row.harnessId)) {
        const err = this.store.appendEvent(sessionId, {
          type: "session.error",
          payload: {
            code: "no_adapter",
            message:
              "No harness adapter configured. User message was recorded; attach an adapter.",
          },
        });
        return { events: [user, err], driveTurn: null };
      }

      if (this.host.isTurnBusy(sessionId)) {
        // Roll back is not possible easily; append error and fail command
        const err = this.store.appendEvent(sessionId, {
          type: "session.error",
          payload: {
            code: "turn_in_progress",
            message: "A turn is already in progress for this session",
          },
        });
        return { events: [user, err], driveTurn: null };
      }

      const turnStart = this.store.appendEvent(sessionId, {
        type: "status.turn_start",
        payload: {},
      });

      const harnessId = row.harnessId;
      const cwd = row.cwd;
      const model = row.model ?? undefined;
      const host = this.host;

      const driveTurn = async () => {
        try {
          await host.getOrStart({
            sessionId,
            harnessId,
            cwd,
            model,
          });
          await host.sendTurn(sessionId, text);
        } catch (err) {
          const code = err instanceof AdapterError ? err.code : "harness_error";
          const message = err instanceof Error ? err.message : String(err);
          try {
            host.reportError(sessionId, code, message);
          } catch {
            /* store may be closed */
          }
        }
      };

      return { events: [user, turnStart], driveTurn };
    } catch (err) {
      throw mapStoreError(err);
    }
  }

  /**
   * Phase 1 compat: sync send that records user + no_adapter or waits for mock.
   * Prefer beginUserMessage + async drive in the WS layer.
   */
  sendUserMessage(sessionId: string, text: string): EventFrame[] {
    const { events } = this.beginUserMessage(sessionId, text);
    return events;
  }

  async cancel(sessionId: string): Promise<EventFrame> {
    try {
      if (!this.store.getSession(sessionId)) {
        throw new SessionError("session_not_found", `Session not found: ${sessionId}`);
      }
      if (this.host?.hasRun(sessionId)) {
        await this.host.cancel(sessionId);
        return this.store.appendEvent(sessionId, {
          type: "session.ended",
          payload: { reason: "cancel" },
        });
      }
      return this.store.appendEvent(sessionId, {
        type: "session.ended",
        payload: { reason: "cancel", note: "No active turn" },
      });
    } catch (err) {
      throw mapStoreError(err);
    }
  }

  async approve(
    sessionId: string,
    approvalId: string,
    decision: "allow" | "deny",
  ): Promise<void> {
    if (!this.host) {
      throw new SessionError("not_implemented", "Approvals require an adapter host");
    }
    try {
      await this.host.approve(sessionId, approvalId, decision);
    } catch (err) {
      if (err instanceof AdapterError) {
        throw new SessionError(err.code, err.message);
      }
      throw err;
    }
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
      archivedAt: row.archivedAt,
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

function mapStoreError(err: unknown): never {
  if (err instanceof StoreError) {
    throw new SessionError(err.code, err.message);
  }
  if (err instanceof SessionError) {
    throw err;
  }
  throw err;
}

function cryptoRandomId(): string {
  return globalThis.crypto.randomUUID();
}
