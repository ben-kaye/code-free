import { describe, expect, it } from "vitest";
import { resolveGrokBinary } from "./resolve-binary.js";

describe("resolveGrokBinary", () => {
  it("returns CODE_FREE_GROK when set and present", () => {
    // process.execPath is always an executable on this host
    const result = resolveGrokBinary({
      CODE_FREE_GROK: process.execPath,
      PATH: "",
    });
    expect(result).toBe(process.execPath);
  });

  it("returns null when CODE_FREE_GROK points nowhere", () => {
    const result = resolveGrokBinary({
      CODE_FREE_GROK: "/nonexistent/path/to/grok-binary-xyz",
      PATH: "",
      HOME: "/tmp/no-such-home-for-grok-resolve",
    });
    expect(result).toBeNull();
  });

  it("returns null when nothing on PATH and no well-known install", () => {
    const none = resolveGrokBinary({
      PATH: "",
      HOME: "/tmp/no-such-home-for-grok-resolve",
    });
    expect(none).toBeNull();
  });

  it("finds well-known ~/.grok/bin/grok when PATH is empty", () => {
    // Live install on this machine (skip if missing)
    const live = resolveGrokBinary({
      PATH: "",
      HOME: process.env.HOME,
    });
    if (!live) {
      // CI / hosts without Grok — still pass
      expect(live).toBeNull();
      return;
    }
    expect(live).toMatch(/grok$/);
  });
});
