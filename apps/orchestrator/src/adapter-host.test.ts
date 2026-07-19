import { describe, expect, it } from "vitest";
import type { Cap, EventDraft } from "@code-free/protocol";
import type { EventSink, HarnessAdapter, TaskSpec } from "@code-free/adapter-core";
import { AdapterError } from "@code-free/adapter-core";
import { AdapterHost } from "./adapter-host.js";

function mockAdapter(opts?: {
  onSend?: (text: string, sink: EventSink) => Promise<void>;
  failStart?: boolean;
}): HarnessAdapter {
  return {
    id: "mock",
    name: "Mock",
    caps: ["streaming_text"] satisfies Cap[],
    async start(_spec: TaskSpec, sink: EventSink) {
      if (opts?.failStart) {
        throw new AdapterError("spawn_failed", "mock spawn failed");
      }
      return {
        async send(text: string) {
          if (opts?.onSend) {
            await opts.onSend(text, sink);
            return;
          }
          sink.emit({ type: "message.delta", payload: { id: "m1", text: `echo:${text}` } });
          sink.emit({ type: "message.done", payload: { id: "m1" } });
        },
        async cancel() {},
        async dispose() {},
      };
    },
    async listModels() {
      return [{ id: "mock-model", name: "Mock" }];
    },
  };
}

describe("AdapterHost", () => {
  it("lists registered harnesses and models", async () => {
    const drafts: EventDraft[] = [];
    const host = new AdapterHost((_sid, d) => {
      drafts.push(d);
    });
    host.register(mockAdapter());
    expect(host.listHarnesses()).toEqual([
      { id: "mock", name: "Mock", caps: ["streaming_text"] },
    ]);
    expect(await host.listModels()).toEqual([{ id: "mock-model", name: "Mock" }]);
    expect(host.defaultHarnessId()).toBe("mock");
  });

  it("runs a turn and emits adapter drafts + turn_end", async () => {
    const drafts: Array<{ type: string }> = [];
    const host = new AdapterHost((_sid, d) => {
      drafts.push({ type: d.type });
    });
    host.register(mockAdapter());
    await host.getOrStart({ sessionId: "s1", harnessId: "mock", cwd: "/tmp" });
    await host.sendTurn("s1", "hi");
    expect(drafts.map((d) => d.type)).toEqual([
      "message.delta",
      "message.done",
      "status.turn_end",
    ]);
  });

  it("surfaces spawn failure as AdapterError", async () => {
    const host = new AdapterHost(() => {});
    host.register(mockAdapter({ failStart: true }));
    await expect(
      host.getOrStart({ sessionId: "s1", harnessId: "mock", cwd: "/tmp" }),
    ).rejects.toMatchObject({ code: "spawn_failed" });
  });

  it("rejects second concurrent turn", async () => {
    let release!: () => void;
    const gate = new Promise<void>((r) => {
      release = r;
    });
    const host = new AdapterHost(() => {});
    host.register(
      mockAdapter({
        onSend: async () => {
          await gate;
        },
      }),
    );
    await host.getOrStart({ sessionId: "s1", harnessId: "mock", cwd: "/tmp" });
    const first = host.sendTurn("s1", "a");
    await expect(host.sendTurn("s1", "b")).rejects.toMatchObject({
      code: "turn_in_progress",
    });
    // isTurnBusy should be true while first is in flight
    expect(host.isTurnBusy("s1")).toBe(true);
    release();
    await first;
    expect(host.isTurnBusy("s1")).toBe(false);
  });

  it("disposeAll clears runs", async () => {
    const host = new AdapterHost(() => {});
    host.register(mockAdapter());
    await host.getOrStart({ sessionId: "s1", harnessId: "mock", cwd: "/tmp" });
    expect(host.hasRun("s1")).toBe(true);
    await host.disposeAll();
    expect(host.hasRun("s1")).toBe(false);
  });
});
