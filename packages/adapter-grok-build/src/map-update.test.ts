import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { mapAcpUpdate } from "./map-update.js";

const fixturesDir = join(
  dirname(fileURLToPath(import.meta.url)),
  "../../../fixtures/adapters/grok-build",
);

function loadJsonl(name: string): unknown[] {
  const text = readFileSync(join(fixturesDir, name), "utf8");
  return text
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean)
    .map((l) => JSON.parse(l) as unknown);
}

const ctx = { messageId: "m1", thinkingId: "t1" };

describe("mapAcpUpdate fixtures", () => {
  it("maps agent_message_chunk stream", () => {
    const lines = loadJsonl("message-stream.jsonl");
    const drafts = lines.flatMap((u) => mapAcpUpdate(u, ctx));
    expect(drafts.map((d) => d.type)).toEqual(["message.delta", "message.delta"]);
    expect(drafts[0]?.payload).toMatchObject({ id: "m1", text: "Hello" });
    expect(drafts[1]?.payload).toMatchObject({ text: " world" });
  });

  it("maps thought chunks", () => {
    const lines = loadJsonl("thinking.jsonl");
    const drafts = lines.flatMap((u) => mapAcpUpdate(u, ctx));
    expect(drafts.map((d) => d.type)).toEqual(["thinking.delta", "thinking.delta"]);
    expect(drafts[0]?.payload).toMatchObject({ id: "t1" });
  });

  it("maps tool_call lifecycle", () => {
    const lines = loadJsonl("tools.jsonl");
    const drafts = lines.flatMap((u) => mapAcpUpdate(u, ctx));
    expect(drafts.map((d) => d.type)).toEqual([
      "tool.started",
      "tool.progress",
      "tool.done",
      "tool.started",
      "tool.error",
    ]);
    expect(drafts[0]?.payload).toMatchObject({ id: "call_1", title: "Read file" });
    expect(drafts[4]?.payload).toMatchObject({ id: "call_2" });
  });

  it("maps plan updates", () => {
    const lines = loadJsonl("plan.jsonl");
    const drafts = lines.flatMap((u) => mapAcpUpdate(u, ctx));
    expect(drafts).toHaveLength(1);
    expect(drafts[0]?.type).toBe("plan.updated");
  });

  it("maps nested session/update params shape", () => {
    const drafts = mapAcpUpdate(
      {
        sessionId: "s",
        update: { sessionUpdate: "agent_message_chunk", content: { text: "x" } },
      },
      ctx,
    );
    expect(drafts[0]).toMatchObject({
      type: "message.delta",
      payload: { text: "x", id: "m1" },
    });
  });

  it("unknown sessionUpdate becomes log", () => {
    const drafts = mapAcpUpdate({ sessionUpdate: "available_commands_update" }, ctx);
    expect(drafts[0]?.type).toBe("log");
  });
});
