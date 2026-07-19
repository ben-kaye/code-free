import { createInterface, type Interface } from "node:readline";
import type { ChildProcessWithoutNullStreams } from "node:child_process";

export type JsonRpcId = string | number;

export type JsonRpcMessage = {
  jsonrpc?: string;
  id?: JsonRpcId;
  method?: string;
  params?: unknown;
  result?: unknown;
  error?: { code: number; message: string; data?: unknown };
};

export type AcpClientHandlers = {
  /** Agent → client notification (e.g. session/update). */
  onNotification?: (method: string, params: unknown) => void;
  /**
   * Agent → client request that needs a response (e.g. session/request_permission).
   * Must resolve to the JSON-RPC result object.
   */
  onRequest?: (method: string, params: unknown, id: JsonRpcId) => Promise<unknown>;
  onClose?: (code: number | null, signal: NodeJS.Signals | null) => void;
  onStderrLine?: (line: string) => void;
};

/**
 * Thin newline-delimited JSON-RPC 2.0 client over a child process stdio.
 * One reader; concurrent request/response demux by id.
 */
export class AcpClient {
  private readonly rl: Interface;
  private readonly pending = new Map<
    string,
    { resolve: (v: unknown) => void; reject: (e: Error) => void }
  >();
  private nextId = 1;
  private closed = false;
  private writeQueue: Promise<void> = Promise.resolve();

  constructor(
    private readonly child: ChildProcessWithoutNullStreams,
    private readonly handlers: AcpClientHandlers = {},
  ) {
    this.rl = createInterface({ input: child.stdout, crlfDelay: Infinity });
    this.rl.on("line", (line) => this.onLine(line));
    this.rl.on("close", () => {
      /* process exit handled below */
    });

    if (child.stderr) {
      const errRl = createInterface({ input: child.stderr, crlfDelay: Infinity });
      errRl.on("line", (line) => {
        this.handlers.onStderrLine?.(line);
      });
    }

    child.on("close", (code, signal) => {
      this.closed = true;
      const err = new Error(
        `ACP child exited (code=${code ?? "null"} signal=${signal ?? "null"})`,
      );
      for (const [, p] of this.pending) p.reject(err);
      this.pending.clear();
      this.handlers.onClose?.(code, signal);
    });
  }

  get isClosed(): boolean {
    return this.closed;
  }

  async request(method: string, params?: unknown): Promise<unknown> {
    if (this.closed) throw new Error("ACP client closed");
    const id = this.nextId++;
    const key = String(id);
    const msg: JsonRpcMessage = {
      jsonrpc: "2.0",
      id,
      method,
      params: params ?? {},
    };
    const result = new Promise<unknown>((resolve, reject) => {
      this.pending.set(key, { resolve, reject });
    });
    await this.write(msg);
    return result;
  }

  /** Fire-and-forget notification (e.g. session/cancel). */
  async notify(method: string, params?: unknown): Promise<void> {
    if (this.closed) return;
    await this.write({
      jsonrpc: "2.0",
      method,
      params: params ?? {},
    });
  }

  async respond(id: JsonRpcId, result: unknown): Promise<void> {
    await this.write({ jsonrpc: "2.0", id, result });
  }

  async respondError(id: JsonRpcId, code: number, message: string): Promise<void> {
    await this.write({
      jsonrpc: "2.0",
      id,
      error: { code, message },
    });
  }

  dispose(): void {
    this.closed = true;
    try {
      this.rl.close();
    } catch {
      /* ignore */
    }
    if (!this.child.killed) {
      this.child.kill("SIGTERM");
      const killer = setTimeout(() => {
        if (!this.child.killed) this.child.kill("SIGKILL");
      }, 3_000);
      killer.unref?.();
    }
  }

  private write(msg: JsonRpcMessage): Promise<void> {
    this.writeQueue = this.writeQueue.then(
      () =>
        new Promise<void>((resolve, reject) => {
          if (this.closed || !this.child.stdin.writable) {
            reject(new Error("ACP stdin not writable"));
            return;
          }
          this.child.stdin.write(`${JSON.stringify(msg)}\n`, (err) => {
            if (err) reject(err);
            else resolve();
          });
        }),
    );
    return this.writeQueue;
  }

  private onLine(line: string): void {
    const trimmed = line.trim();
    if (!trimmed) return;
    let msg: JsonRpcMessage;
    try {
      msg = JSON.parse(trimmed) as JsonRpcMessage;
    } catch {
      this.handlers.onNotification?.("raw", { line: trimmed });
      return;
    }

    // Response to our request
    if (msg.id !== undefined && msg.method === undefined) {
      const key = String(msg.id);
      const pending = this.pending.get(key);
      if (pending) {
        this.pending.delete(key);
        if (msg.error) {
          pending.reject(
            new Error(`JSON-RPC error ${msg.error.code}: ${msg.error.message}`),
          );
        } else {
          pending.resolve(msg.result);
        }
      }
      return;
    }

    // Request from agent (has id + method)
    if (msg.method && msg.id !== undefined) {
      const id = msg.id;
      const method = msg.method;
      const params = msg.params;
      void (async () => {
        try {
          if (!this.handlers.onRequest) {
            await this.respondError(id, -32601, `Unhandled method: ${method}`);
            return;
          }
          const result = await this.handlers.onRequest(method, params, id);
          await this.respond(id, result);
        } catch (err) {
          await this.respondError(
            id,
            -32000,
            err instanceof Error ? err.message : String(err),
          );
        }
      })();
      return;
    }

    // Notification (method, no id)
    if (msg.method) {
      this.handlers.onNotification?.(msg.method, msg.params);
    }
  }
}
