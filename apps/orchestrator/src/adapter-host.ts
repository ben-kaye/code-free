import {
  AdapterError,
  type AdapterRun,
  type EventSink,
  type HarnessAdapter,
  type ModelInfo,
  type TaskSpec,
} from "@code-free/adapter-core";
import type { EventDraft, HarnessInfo } from "@code-free/protocol";

export type EmitFn = (sessionId: string, draft: EventDraft) => void;

/**
 * Registry + live run map. Orch-owned; adapters have no UI.
 */
export class AdapterHost {
  private readonly adapters = new Map<string, HarnessAdapter>();
  /** sessionId → live run */
  private readonly runs = new Map<string, LiveRun>();

  constructor(private readonly emit: EmitFn) {}

  register(adapter: HarnessAdapter): void {
    this.adapters.set(adapter.id, adapter);
  }

  listHarnesses(): HarnessInfo[] {
    return [...this.adapters.values()].map((a) => ({
      id: a.id,
      name: a.name,
      caps: [...a.caps],
    }));
  }

  getAdapter(harnessId: string): HarnessAdapter | undefined {
    return this.adapters.get(harnessId);
  }

  defaultHarnessId(): string | undefined {
    const first = this.adapters.values().next().value as HarnessAdapter | undefined;
    return first?.id;
  }

  async listModels(harnessId?: string): Promise<ModelInfo[]> {
    const id = harnessId ?? this.defaultHarnessId();
    if (!id) return [];
    const adapter = this.adapters.get(id);
    if (!adapter?.listModels) return [];
    return adapter.listModels();
  }

  hasRun(sessionId: string): boolean {
    return this.runs.has(sessionId);
  }

  isTurnBusy(sessionId: string): boolean {
    return this.runs.get(sessionId)?.busy === true;
  }

  /**
   * Get or start a harness run for the session. Throws AdapterError on spawn/protocol failure.
   */
  async getOrStart(spec: TaskSpec & { harnessId: string }): Promise<AdapterRun> {
    const existing = this.runs.get(spec.sessionId);
    if (existing) return existing.run;

    const adapter = this.adapters.get(spec.harnessId);
    if (!adapter) {
      throw new AdapterError(
        "not_running",
        `No adapter registered for harness: ${spec.harnessId}`,
      );
    }

    const sink: EventSink = {
      emit: (draft) => this.emit(spec.sessionId, draft),
      emitRaw: (line) =>
        this.emit(spec.sessionId, { type: "raw", payload: { line: line.slice(0, 500) } }),
    };

    const run = await adapter.start(
      {
        sessionId: spec.sessionId,
        cwd: spec.cwd,
        model: spec.model,
        resumeToken: spec.resumeToken,
        extra: spec.extra,
      },
      sink,
    );

    const live: LiveRun = { run, busy: false, harnessId: spec.harnessId };
    this.runs.set(spec.sessionId, live);
    return run;
  }

  /**
   * Drive a user turn. Caller has already appended message.user + status.turn_start.
   * Awaits harness send completion, then emits status.turn_end (or session.error).
   */
  async sendTurn(sessionId: string, text: string): Promise<void> {
    const live = this.runs.get(sessionId);
    if (!live) {
      throw new AdapterError("not_running", "No active harness run for session");
    }
    if (live.busy) {
      throw new AdapterError("turn_in_progress", "A turn is already in progress");
    }
    live.busy = true;
    try {
      await live.run.send(text);
      this.emit(sessionId, {
        type: "status.turn_end",
        payload: { reason: "completed" },
      });
    } catch (err) {
      const code = err instanceof AdapterError ? err.code : "harness_error";
      const message = err instanceof Error ? err.message : String(err);
      this.emit(sessionId, {
        type: "session.error",
        payload: { code, message },
      });
      this.emit(sessionId, {
        type: "status.turn_end",
        payload: { reason: "error", code },
      });
    } finally {
      live.busy = false;
    }
  }

  async cancel(sessionId: string): Promise<void> {
    const live = this.runs.get(sessionId);
    if (!live) return;
    try {
      await live.run.cancel();
    } catch {
      /* best effort */
    }
  }

  async approve(
    sessionId: string,
    approvalId: string,
    decision: "allow" | "deny",
  ): Promise<void> {
    const live = this.runs.get(sessionId);
    if (!live?.run.approve) {
      throw new AdapterError("not_running", "No active run with approvals");
    }
    await live.run.approve(approvalId, decision);
  }

  /** Durable error + turn_end for failures outside an active sendTurn. */
  reportError(sessionId: string, code: string, message: string): void {
    this.emit(sessionId, {
      type: "session.error",
      payload: { code, message },
    });
    this.emit(sessionId, {
      type: "status.turn_end",
      payload: { reason: "error", code },
    });
  }

  async disposeSession(sessionId: string): Promise<void> {
    const live = this.runs.get(sessionId);
    if (!live) return;
    this.runs.delete(sessionId);
    try {
      await live.run.dispose();
    } catch {
      /* ignore */
    }
  }

  async disposeAll(): Promise<void> {
    const ids = [...this.runs.keys()];
    await Promise.all(ids.map((id) => this.disposeSession(id)));
  }
}

type LiveRun = {
  run: AdapterRun;
  busy: boolean;
  harnessId: string;
};
