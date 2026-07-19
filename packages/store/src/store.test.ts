import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { EventStore } from "./store.js";

const temps: string[] = [];

function tempRoot(): string {
  const dir = mkdtempSync(join(tmpdir(), "code-free-store-"));
  temps.push(dir);
  return dir;
}

afterEach(() => {
  while (temps.length) {
    const d = temps.pop();
    if (d) rmSync(d, { recursive: true, force: true });
  }
});

describe("EventStore", () => {
  it("creates sessions and lists them", () => {
    const store = new EventStore({ dataRoot: tempRoot() });
    const s = store.createSession({ cwd: "/proj", title: "Demo" });
    expect(s.id).toBeTruthy();
    expect(store.getSession(s.id)?.title).toBe("Demo");
    expect(store.listSessions()).toHaveLength(1);
    store.close();
  });

  it("appends monotonic seq and queries afterSeq", () => {
    const store = new EventStore({ dataRoot: tempRoot() });
    const s = store.createSession({ cwd: "/proj" });
    const e1 = store.appendEvent(s.id, { type: "session.started", payload: {} });
    const e2 = store.appendEvent(s.id, {
      type: "message.user",
      payload: { text: "hi" },
    });
    expect(e1.seq).toBe(1);
    expect(e2.seq).toBe(2);
    expect(store.lastSeq(s.id)).toBe(2);

    const gap = store.listEventsAfter(s.id, 1);
    expect(gap).toHaveLength(1);
    expect(gap[0]?.seq).toBe(2);
    expect(gap[0]?.payload).toEqual({ text: "hi" });
    store.close();
  });

  it("survives reopen (durable)", () => {
    const root = tempRoot();
    const store1 = new EventStore({ dataRoot: root });
    const s = store1.createSession({ cwd: "/proj", id: "fixed-session" });
    store1.appendEvent(s.id, { type: "message.user", payload: { text: "a" } });
    store1.appendEvent(s.id, { type: "message.user", payload: { text: "b" } });
    store1.close();

    const store2 = new EventStore({ dataRoot: root });
    expect(store2.lastSeq("fixed-session")).toBe(2);
    const all = store2.listEventsAfter("fixed-session", 0);
    expect(all.map((e) => e.payload)).toEqual([{ text: "a" }, { text: "b" }]);
    const next = store2.appendEvent("fixed-session", {
      type: "message.user",
      payload: { text: "c" },
    });
    expect(next.seq).toBe(3);
    store2.close();
  });

  it("isolates seq per session", () => {
    const store = new EventStore({ dataRoot: tempRoot() });
    const a = store.createSession({ cwd: "/a" });
    const b = store.createSession({ cwd: "/b" });
    store.appendEvent(a.id, { type: "log", payload: { n: 1 } });
    store.appendEvent(b.id, { type: "log", payload: { n: 1 } });
    store.appendEvent(a.id, { type: "log", payload: { n: 2 } });
    expect(store.lastSeq(a.id)).toBe(2);
    expect(store.lastSeq(b.id)).toBe(1);
    store.close();
  });

  it("throws on missing session", () => {
    const store = new EventStore({ dataRoot: tempRoot() });
    expect(() => store.appendEvent("nope", { type: "log", payload: {} })).toThrow(
      /not found/i,
    );
    store.close();
  });
});
