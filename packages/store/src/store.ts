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
import { ARCHIVE_RETENTION_MS, SCHEMA_SQL } from "./schema.js";

export type SessionRow = {
  id: string;
  title: string | null;
  cwd: string;
  harnessId: string | null;
  model: string | null;
  createdAt: string;
  updatedAt: string;
  /** ISO timestamp when archived; null if active. */
  archivedAt: string | null;
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

export type SessionListFilter = "active" | "archived";

const SESSION_SELECT = `SELECT id, title, cwd, harness_id AS harnessId, model,
        created_at AS createdAt, updated_at AS updatedAt,
        archived_at AS archivedAt
 FROM sessions`;

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
    this.migrate();
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
      archivedAt: null,
    };
    this.db
      .prepare(
        `INSERT INTO sessions (id, title, cwd, harness_id, model, created_at, updated_at, archived_at)
         VALUES (@id, @title, @cwd, @harnessId, @model, @createdAt, @updatedAt, @archivedAt)`,
      )
      .run(row);
    return row;
  }

  getSession(sessionId: string): SessionRow | null {
    this.assertOpen();
    const raw = this.db
      .prepare(`${SESSION_SELECT} WHERE id = ?`)
      .get(sessionId) as SessionRow | undefined;
    return raw ? normalizeRow(raw) : null;
  }

  /** Active sessions by default; pass filter for archived. */
  listSessions(filter: SessionListFilter = "active"): SessionRow[] {
    this.assertOpen();
    const where =
      filter === "active" ? "WHERE archived_at IS NULL" : "WHERE archived_at IS NOT NULL";
    const order =
      filter === "active" ? "ORDER BY updated_at DESC" : "ORDER BY archived_at DESC";
    const rows = this.db.prepare(`${SESSION_SELECT} ${where} ${order}`).all() as SessionRow[];
    return rows.map(normalizeRow);
  }

  renameSession(sessionId: string, title: string): SessionRow {
    this.assertOpen();
    const existing = this.requireActiveSession(sessionId);
    const updatedAt = nowIso();
    this.db
      .prepare(`UPDATE sessions SET title = ?, updated_at = ? WHERE id = ?`)
      .run(title, updatedAt, sessionId);
    return { ...existing, title, updatedAt };
  }

  /**
   * Soft-delete: hide from active list. Permanent delete after ARCHIVE_RETENTION_MS.
   * Idempotent if already archived.
   */
  archiveSession(sessionId: string): SessionRow {
    this.assertOpen();
    const existing = this.getSession(sessionId);
    if (!existing) {
      throw new StoreError("session_not_found", `Session not found: ${sessionId}`);
    }
    if (existing.archivedAt) {
      return existing;
    }
    const archivedAt = nowIso();
    this.db
      .prepare(`UPDATE sessions SET archived_at = ?, updated_at = ? WHERE id = ?`)
      .run(archivedAt, archivedAt, sessionId);
    return { ...existing, archivedAt, updatedAt: archivedAt };
  }

  /** Hard-delete session + events (FK cascade). */
  deleteSession(sessionId: string): boolean {
    this.assertOpen();
    const result = this.db.prepare(`DELETE FROM sessions WHERE id = ?`).run(sessionId);
    return result.changes > 0;
  }

  /**
   * Permanently delete archives at or older than retention.
   * retentionMs 0 deletes all archives (archived_at <= now).
   * @returns number of sessions deleted
   */
  purgeExpiredArchives(retentionMs: number = ARCHIVE_RETENTION_MS): number {
    this.assertOpen();
    const cutoff = new Date(Date.now() - retentionMs).toISOString();
    const result = this.db
      .prepare(`DELETE FROM sessions WHERE archived_at IS NOT NULL AND archived_at <= ?`)
      .run(cutoff);
    return result.changes;
  }

  /**
   * Append a draft event. Assigns seq = last+1 and stamps ts after durable write.
   * Returns the full event frame.
   */
  appendEvent(sessionId: string, draft: EventDraft): EventFrame {
    this.assertOpen();
    const session = this.requireActiveSession(sessionId);

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

    // Touch for typecheck that session exists as active
    void session;

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

  /** Events with seq > afterSeq, ordered ascending. Works for archived (read-only replay). */
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

  private requireActiveSession(sessionId: string): SessionRow {
    const session = this.getSession(sessionId);
    if (!session) {
      throw new StoreError("session_not_found", `Session not found: ${sessionId}`);
    }
    if (session.archivedAt) {
      throw new StoreError("session_archived", `Session is archived: ${sessionId}`);
    }
    return session;
  }

  /** Add archived_at to DBs created before archive support. */
  private migrate(): void {
    const cols = this.db.prepare(`PRAGMA table_info(sessions)`).all() as Array<{ name: string }>;
    if (!cols.some((c) => c.name === "archived_at")) {
      this.db.exec(`ALTER TABLE sessions ADD COLUMN archived_at TEXT`);
    }
    this.db.exec(
      `CREATE INDEX IF NOT EXISTS idx_sessions_archived_at ON sessions(archived_at)`,
    );
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

function normalizeRow(raw: SessionRow): SessionRow {
  return {
    ...raw,
    archivedAt: raw.archivedAt ?? null,
  };
}

/** Ensure parent dir exists when opening a store under a nested path. */
export function ensureDataRoot(dataRoot: string): string {
  mkdirSync(dataRoot, { recursive: true });
  mkdirSync(dirname(join(dataRoot, "events.db")), { recursive: true });
  return dataRoot;
}
