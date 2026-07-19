import { describe, expect, it } from "vitest";
import { PROTOCOL_VERSION } from "./version.js";
import {
  ProtocolError,
  parseClientCommand,
  parseClientHello,
  parseJsonText,
  parseServerMessage,
} from "./parse.js";
import { EventFrameSchema } from "./events.js";

describe("parseJsonText", () => {
  it("parses objects", () => {
    expect(parseJsonText('{"a":1}')).toEqual({ a: 1 });
  });

  it("rejects invalid JSON", () => {
    expect(() => parseJsonText("not-json")).toThrow(ProtocolError);
  });
});

describe("parseClientHello", () => {
  it("accepts valid hello with token", () => {
    const hello = parseClientHello({
      kind: "hello",
      protocolVersion: PROTOCOL_VERSION,
      token: "secret",
    });
    expect(hello.token).toBe("secret");
  });

  it("rejects missing token", () => {
    expect(() =>
      parseClientHello({ kind: "hello", protocolVersion: PROTOCOL_VERSION }),
    ).toThrow(ProtocolError);
  });

  it("rejects wrong protocol version", () => {
    expect(() =>
      parseClientHello({ kind: "hello", protocolVersion: 99, token: "x" }),
    ).toThrow(ProtocolError);
  });
});

describe("parseClientCommand", () => {
  it("accepts session.create", () => {
    const cmd = parseClientCommand({
      kind: "session.create",
      requestId: "r1",
      cwd: "/tmp/proj",
    });
    expect(cmd.kind).toBe("session.create");
  });

  it("accepts session.archive", () => {
    const cmd = parseClientCommand({
      kind: "session.archive",
      requestId: "r1",
      sessionId: "s1",
    });
    expect(cmd.kind).toBe("session.archive");
  });

  it("accepts session.list with archived filter", () => {
    const cmd = parseClientCommand({
      kind: "session.list",
      requestId: "r1",
      filter: "archived",
    });
    expect(cmd.kind).toBe("session.list");
    if (cmd.kind === "session.list") {
      expect(cmd.filter).toBe("archived");
    }
  });

  it("fail-closed on unknown command kind", () => {
    try {
      parseClientCommand({ kind: "session.explode", requestId: "r1" });
      expect.unreachable();
    } catch (e) {
      expect(e).toBeInstanceOf(ProtocolError);
      expect((e as ProtocolError).code).toBe("unknown_command");
    }
  });

  it("rejects hello as post-auth command", () => {
    try {
      parseClientCommand({
        kind: "hello",
        protocolVersion: PROTOCOL_VERSION,
        token: "x",
      });
      expect.unreachable();
    } catch (e) {
      expect(e).toBeInstanceOf(ProtocolError);
      expect((e as ProtocolError).code).toBe("invalid_command");
    }
  });

  it("rejects malformed known command", () => {
    expect(() =>
      parseClientCommand({ kind: "session.create", requestId: "r1" }),
    ).toThrow(ProtocolError);
  });
});

describe("event frames", () => {
  it("accepts known event type", () => {
    const frame = EventFrameSchema.parse({
      protocolVersion: PROTOCOL_VERSION,
      kind: "event",
      sessionId: "s1",
      seq: 1,
      ts: "2026-01-01T00:00:00.000Z",
      type: "message.user",
      payload: { text: "hi" },
    });
    expect(frame.seq).toBe(1);
  });

  it("accepts unknown event type string (forward compatible)", () => {
    const frame = EventFrameSchema.parse({
      protocolVersion: PROTOCOL_VERSION,
      kind: "event",
      sessionId: "s1",
      seq: 2,
      ts: "2026-01-01T00:00:00.000Z",
      type: "x.custom.future",
      payload: {},
    });
    expect(frame.type).toBe("x.custom.future");
  });
});

describe("parseServerMessage", () => {
  it("parses error frame", () => {
    const msg = parseServerMessage({
      kind: "error",
      code: "auth_failed",
      message: "bad token",
    });
    expect(msg.kind).toBe("error");
  });
});
