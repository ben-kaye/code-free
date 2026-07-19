import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import WebSocket from "ws";
import { PROTOCOL_VERSION } from "@code-free/protocol";
import { Logger } from "./logger.js";
import { startOrchestrator, type RunningOrch } from "./server.js";

const temps: string[] = [];
const running: RunningOrch[] = [];

function tempDir(): string {
  const d = mkdtempSync(join(tmpdir(), "code-free-orch-"));
  temps.push(d);
  return d;
}

afterEach(async () => {
  while (running.length) {
    const o = running.pop();
    if (o) await o.close();
  }
  while (temps.length) {
    const d = temps.pop();
    if (d) rmSync(d, { recursive: true, force: true });
  }
}, 30_000);

async function boot(): Promise<RunningOrch> {
  const root = tempDir();
  const orch = await startOrchestrator(
    {
      dataRoot: join(root, "data"),
      bindHost: "127.0.0.1",
      bindPort: 0,
      tokenFile: join(root, "token"),
      logDir: join(root, "logs"),
    },
    new Logger(join(root, "logs")),
  );
  running.push(orch);
  return orch;
}

/** Buffered WS client so responses are never missed between send and await. */
class TestClient {
  private readonly queue: unknown[] = [];
  private waiters: Array<(v: unknown) => void> = [];

  private constructor(readonly ws: WebSocket) {
    ws.on("message", (data) => {
      const msg = JSON.parse(data.toString("utf8")) as unknown;
      const waiter = this.waiters.shift();
      if (waiter) waiter(msg);
      else this.queue.push(msg);
    });
  }

  static async connect(url: string): Promise<TestClient> {
    const ws = await new Promise<WebSocket>((resolve, reject) => {
      const socket = new WebSocket(url);
      socket.once("open", () => resolve(socket));
      socket.once("error", reject);
    });
    return new TestClient(ws);
  }

  next(timeoutMs = 5_000): Promise<unknown> {
    if (this.queue.length > 0) {
      return Promise.resolve(this.queue.shift());
    }
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.waiters = this.waiters.filter((w) => w !== onMsg);
        reject(new Error(`Timed out waiting for WS message after ${timeoutMs}ms`));
      }, timeoutMs);
      const onMsg = (v: unknown) => {
        clearTimeout(timer);
        resolve(v);
      };
      this.waiters.push(onMsg);
    });
  }

  send(obj: unknown): void {
    this.ws.send(JSON.stringify(obj));
  }

  close(): void {
    this.ws.close();
  }
}

async function auth(client: TestClient, token: string): Promise<void> {
  client.send({
    kind: "hello",
    protocolVersion: PROTOCOL_VERSION,
    token,
  });
  const hello = (await client.next()) as { kind: string; protocolVersion: number };
  expect(hello.kind).toBe("hello");
  expect(hello.protocolVersion).toBe(PROTOCOL_VERSION);
}

describe("orchestrator WS", () => {
  it("rejects bad token", async () => {
    const orch = await boot();
    const client = await TestClient.connect(orch.endpoint);
    client.send({
      kind: "hello",
      protocolVersion: PROTOCOL_VERSION,
      token: "wrong",
    });
    const err = (await client.next()) as { kind: string; code: string };
    expect(err.kind).toBe("error");
    expect(err.code).toBe("auth_failed");
    client.close();
  });

  it(
    "creates session, subscribes, sends, and gap-fills after restart",
    async () => {
      const root = tempDir();
      const dataRoot = join(root, "data");
      const tokenFile = join(root, "token");
      const logDir = join(root, "logs");

      let orch = await startOrchestrator(
        { dataRoot, bindHost: "127.0.0.1", bindPort: 0, tokenFile, logDir },
        new Logger(logDir),
      );
      running.push(orch);

      const token = readFileSync(tokenFile, "utf8").trim();
      let client = await TestClient.connect(orch.endpoint);
      await auth(client, token);

      client.send({
        kind: "session.create",
        requestId: "c1",
        cwd: "/tmp/proj",
        title: "t",
      });
      const created = (await client.next()) as {
        kind: string;
        ok: boolean;
        data: { session: { id: string }; event: { seq: number } };
      };
      expect(created.ok).toBe(true);
      const sessionId = created.data.session.id;
      expect(created.data.event.seq).toBe(1);

      client.send({
        kind: "session.subscribe",
        requestId: "s1",
        sessionId,
        afterSeq: 0,
      });
      const snap = (await client.next()) as {
        kind: string;
        events: unknown[];
        lastSeq: number;
      };
      expect(snap.kind).toBe("snapshot");
      expect(snap.events.length).toBe(1);
      const subResult = (await client.next()) as { ok: boolean };
      expect(subResult.ok).toBe(true);

      client.send({
        kind: "session.send",
        requestId: "send1",
        sessionId,
        text: "hello",
      });
      const live1 = (await client.next()) as { type: string; seq: number };
      const live2 = (await client.next()) as { type: string; seq: number };
      expect(live1.type).toBe("message.user");
      expect(live2.type).toBe("session.error");
      const sendResult = (await client.next()) as { ok: boolean };
      expect(sendResult.ok).toBe(true);

      const lastSeqBefore = live2.seq;
      client.close();
      await orch.close();
      running.pop();

      orch = await startOrchestrator(
        { dataRoot, bindHost: "127.0.0.1", bindPort: 0, tokenFile, logDir },
        new Logger(logDir),
      );
      running.push(orch);

      client = await TestClient.connect(orch.endpoint);
      await auth(client, token);

      client.send({
        kind: "session.subscribe",
        requestId: "s2",
        sessionId,
        afterSeq: 1,
      });
      const gapSnap = (await client.next()) as {
        kind: string;
        events: Array<{ seq: number; type: string }>;
        lastSeq: number;
      };
      expect(gapSnap.kind).toBe("snapshot");
      expect(gapSnap.lastSeq).toBe(lastSeqBefore);
      expect(gapSnap.events.map((e) => e.seq)).toEqual([2, 3]);
      expect(gapSnap.events.map((e) => e.type)).toEqual([
        "message.user",
        "session.error",
      ]);
      const sub2 = (await client.next()) as { ok: boolean };
      expect(sub2.ok).toBe(true);
      client.close();
    },
    30_000,
  );

  it("fail-closed on unknown command", async () => {
    const orch = await boot();
    const client = await TestClient.connect(orch.endpoint);
    await auth(client, orch.token);
    client.send({ kind: "session.explode", requestId: "x" });
    const err = (await client.next()) as { kind: string; code: string };
    expect(err.kind).toBe("error");
    expect(err.code).toBe("unknown_command");
    client.close();
  });
});
