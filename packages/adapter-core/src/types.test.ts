import { describe, expect, it } from "vitest";
import type { Cap, EventDraft } from "@code-free/protocol";
import {
  AdapterError,
  type AdapterErrorCode,
  type EventSink,
  type HarnessAdapter,
  type TaskSpec,
} from "./index.js";

const ALL_CODES: AdapterErrorCode[] = [
  "binary_not_found",
  "spawn_failed",
  "turn_in_progress",
  "not_running",
  "harness_error",
  "protocol_error",
];

describe("adapter-core contract", () => {
  it("AdapterError carries code, name, and is instanceof Error", () => {
    const err = new AdapterError("binary_not_found", "grok not on PATH");
    expect(err).toBeInstanceOf(AdapterError);
    expect(err).toBeInstanceOf(Error);
    expect(err.name).toBe("AdapterError");
    expect(err.code).toBe("binary_not_found");
    expect(err.message).toContain("PATH");
  });

  it("AdapterError accepts every AdapterErrorCode", () => {
    for (const code of ALL_CODES) {
      const err = new AdapterError(code, code);
      expect(err).toBeInstanceOf(AdapterError);
      expect(err.code).toBe(code);
      expect(err.name).toBe("AdapterError");
    }
  });

  it("mock adapter satisfies HarnessAdapter shape", async () => {
    const drafts: EventDraft[] = [];
    const sink: EventSink = {
      emit: (d) => {
        drafts.push(d);
      },
    };

    const adapter: HarnessAdapter = {
      id: "mock",
      name: "Mock",
      caps: ["streaming_text"] satisfies Cap[],
      async start(_spec: TaskSpec, s: EventSink) {
        return {
          async send(text: string) {
            s.emit({ type: "message.delta", payload: { text, id: "m1" } });
            s.emit({ type: "message.done", payload: { id: "m1" } });
          },
          async cancel() {},
          async dispose() {},
        };
      },
    };

    const run = await adapter.start({ sessionId: "s1", cwd: "/tmp" }, sink);
    await run.send("hi");
    expect(drafts.map((d) => d.type)).toEqual(["message.delta", "message.done"]);
    await run.dispose();
  });
});
