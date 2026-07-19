import { PassThrough } from "node:stream";
import { describe, expect, it } from "vitest";
import { AcpClient } from "./acp-client.js";

/** Minimal fake child: duplex streams for stdin/stdout. */
function fakeChild() {
  const stdin = new PassThrough();
  const stdout = new PassThrough();
  const stderr = new PassThrough();
  const listeners: Record<string, Array<(...args: unknown[]) => void>> = {};
  const child = {
    stdin,
    stdout,
    stderr,
    killed: false,
    pid: 12345,
    kill() {
      this.killed = true;
      for (const fn of listeners.close ?? []) fn(0, null);
    },
    on(event: string, fn: (...args: unknown[]) => void) {
      (listeners[event] ??= []).push(fn);
      return this;
    },
  };
  return { child: child as unknown as import("node:child_process").ChildProcessWithoutNullStreams, stdin, stdout, stderr };
}

describe("AcpClient", () => {
  it("demultiplexes request/response by id", async () => {
    const { child, stdin, stdout } = fakeChild();
    const client = new AcpClient(child);

    const written: string[] = [];
    stdin.on("data", (buf: Buffer) => {
      written.push(buf.toString("utf8"));
      const msg = JSON.parse(buf.toString("utf8").trim()) as { id: number; method: string };
      // Respond after a tick
      queueMicrotask(() => {
        stdout.write(
          JSON.stringify({ jsonrpc: "2.0", id: msg.id, result: { ok: true, method: msg.method } }) +
            "\n",
        );
      });
    });

    const result = (await client.request("initialize", { protocolVersion: 1 })) as {
      ok: boolean;
      method: string;
    };
    expect(result.ok).toBe(true);
    expect(result.method).toBe("initialize");
    expect(written[0]).toContain("initialize");
    client.dispose();
  });

  it("routes session/update notifications", async () => {
    const { child, stdout } = fakeChild();
    const notes: Array<{ method: string; params: unknown }> = [];
    const client = new AcpClient(child, {
      onNotification(method, params) {
        notes.push({ method, params });
      },
    });

    stdout.write(
      JSON.stringify({
        jsonrpc: "2.0",
        method: "session/update",
        params: {
          sessionId: "s1",
          update: { sessionUpdate: "agent_message_chunk", content: { text: "hi" } },
        },
      }) + "\n",
    );

    await new Promise((r) => setTimeout(r, 20));
    expect(notes).toHaveLength(1);
    expect(notes[0]?.method).toBe("session/update");
    client.dispose();
  });

  it("handles agent requests via onRequest", async () => {
    const { child, stdin, stdout } = fakeChild();
    const responses: unknown[] = [];
    stdin.on("data", (buf: Buffer) => {
      responses.push(JSON.parse(buf.toString("utf8").trim()));
    });

    const client = new AcpClient(child, {
      async onRequest(method) {
        if (method === "session/request_permission") {
          return { outcome: { outcome: "selected", optionId: "allow-once" } };
        }
        throw new Error("nope");
      },
    });

    stdout.write(
      JSON.stringify({
        jsonrpc: "2.0",
        id: 42,
        method: "session/request_permission",
        params: { sessionId: "s", options: [] },
      }) + "\n",
    );

    await new Promise((r) => setTimeout(r, 30));
    expect(responses).toHaveLength(1);
    expect(responses[0]).toMatchObject({
      id: 42,
      result: { outcome: { outcome: "selected", optionId: "allow-once" } },
    });
    client.dispose();
  });
});
