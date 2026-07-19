import Database from "better-sqlite3";
import { randomUUID } from "node:crypto";
import { mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import {
  PROTOCOL_VERSION,
  EventFrameSchema,
  type EventDraft,
  type EventFrame,
} from "@code-free/protocol";
import { SCHEMA_SQL } from "./schema.js";

export type SessionRow = {
  id: string;
  title: string | null;
  cwd: string;
  harnessId: string | null;
  model: string | null;
  createdAt: string;
  updatedAt: string;
};

export type CreateSessionInput = {
  cwd: string;
  title?: string;
  harnessId?: string;
  model?: string;
  id?: string;
};

export type EventStoreOptions = {
  /** Directory for the SQLite file (data root). */
  dataRoot: string;
  /** Filename under dataRoot. Default: events.db */
  dbName?: string;
};

/**
 * Single-writer SQLite event log.
 * Seq is assigned only after a durable append succeeds.
 */
export class EventStore {
  readonly dbPath: string;
  private readonly db: Database.Database;
  private closed = false;

  constructor(options: EventStoreOptions) {
    mkdirSync(options.dataRoot, { recursive: true });
    this.dbPath = join(options.dataRoot, options.dbName ?? "events.db");
    this.db = new Database(this.dbPath);
    this.db.exec(SCHEMA_SQL);
  }

  close(): void {
    if (this.closed) return;
    this.closed = true;
    this.db.close();
  }

  createSession(input: CreateSessionInput): SessionRow {
    this.assertOpen();
    const now = nowIso();
    const id = input.id ?? randomUUID();
    const row: SessionRow = {
      id,
      title: input.title ?? null,
      cwd: input.cwd,
      harnessId: input.harnessId ?? null,
      model: input.model ?? null,
      createdAt: now,
      updatedAt: now,
    };
    this.db
      .prepare(
        `INSERT INTO sessions (id, title, cwd, harness_id, model, created_at, updated_at)
         VALUES (@id, @title, @cwd, @harnessId, @model, @createdAt, @updatedAt)`,
      )
      .run(row);
    return row;
  }

  getSession(sessionId: string): SessionRow | null {
    this.assertOpen();
    const raw = this.db
      .prepare(
        `SELECT id, title, cwd, harness_id AS harnessId, model,
                created_at AS createdAt, updated_at AS updatedAt
         FROM sessions WHERE id = ?`,
      )
      .get(sessionId) as SessionRow | undefined;
    return raw ?? null;
  }

  listSessions(): SessionRow[] {
    this.assertOpen();
    return this.db
      .prepare(
        `SELECT id, title, cwd, harness_id AS harnessId, model,
                created_at AS createdAt, updated_at AS updatedAt
         FROM sessions ORDER BY updated_at DESC`,
      )
      .all() as SessionRow[];
  }

  renameSession(sessionId: string, title: string): SessionRow {
    this.assertOpen();
    const existing = this.getSession(sessionId);
    if (!existing) {
      throw new StoreError("session_not_found", `Session not found: ${sessionId}`);
    }
    const updatedAt = nowIso();
    this.db
      .prepare(`UPDATE sessions SET title = ?, updated_at = ? WHERE id = ?`)
      .run(title, updatedAt, sessionId);
    return { ...existing, title, updatedAt };
  }

  /**
   * Append a draft event. Assigns seq = last+1 and stamps ts after durable write.
   * Returns the full event frame.
   */
  appendEvent(sessionId: string, draft: EventDraft): EventFrame {
    this.assertOpen();
    const session = this.getSession(sessionId);
    if (!session) {
      throw new StoreError("session_not_found", `Session not found: ${sessionId}`);
    }

    const type = draft.type;
    const payload = draft.payload ?? {};
    const payloadJson = JSON.stringify(payload);

    const appendTx = this.db.transaction(() => {
      const last = this.db
        .prepare(`SELECT COALESCE(MAX(seq), 0) AS maxSeq FROM events WHERE session_id = ?`)
        .get(sessionId) as { maxSeq: number };
      const seq = last.maxSeq + 1;
      const ts = nowIso();
      this.db
        .prepare(
          `INSERT INTO events (session_id, seq, ts, type, payload_json)
           VALUES (?, ?, ?, ?, ?)`,
        )
        .run(sessionId, seq, ts, type, payloadJson);
      this.db
        .prepare(`UPDATE sessions SET updated_at = ? WHERE id = ?`)
        .run(ts, sessionId);
      return { seq, ts };
    });

    const { seq, ts } = appendTx();

    const frame = EventFrameSchema.parse({
      protocolVersion: PROTOCOL_VERSION,
      kind: "event",
      sessionId,
      seq,
      ts,
      type,
      payload,
    });
    return frame;
  }

  /** Events with seq > afterSeq, ordered ascending. */
  listEventsAfter(sessionId: string, afterSeq: number): EventFrame[] {
    this.assertOpen();
    const rows = this.db
      .prepare(
        `SELECT session_id AS sessionId, seq, ts, type, payload_json AS payloadJson
         FROM events
         WHERE session_id = ? AND seq > ?
         ORDER BY seq ASC`,
      )
      .all(sessionId, afterSeq) as Array<{
      sessionId: string;
      seq: number;
      ts: string;
      type: string;
      payloadJson: string;
    }>;

    return rows.map((r) =>
      EventFrameSchema.parse({
        protocolVersion: PROTOCOL_VERSION,
        kind: "event",
        sessionId: r.sessionId,
        seq: r.seq,
        ts: r.ts,
        type: r.type,
        payload: JSON.parse(r.payloadJson) as Record<string, unknown>,
      }),
    );
  }

  lastSeq(sessionId: string): number {
    this.assertOpen();
    const row = this.db
      .prepare(`SELECT COALESCE(MAX(seq), 0) AS maxSeq FROM events WHERE session_id = ?`)
      .get(sessionId) as { maxSeq: number };
    return row.maxSeq;
  }

  private assertOpen(): void {
    if (this.closed) {
      throw new StoreError("store_closed", "EventStore is closed");
    }
  }
}

export class StoreError extends Error {
  readonly code: string;

  constructor(code: string, message: string) {
    super(message);
    this.name = "StoreError";
    this.code = code;
  }
}

function nowIso(): string {
  return new Date().toISOString();
}

/** Ensure parent dir exists when opening a store under a nested path. */
export function ensureDataRoot(dataRoot: string): string {
  mkdirSync(dataRoot, { recursive: true });
  mkdirSync(dirname(join(dataRoot, "events.db")), { recursive: true });
  return dataRoot;
}
