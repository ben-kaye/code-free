import { describe, expect, it } from "vitest";
import { ConfigError, parseConfig } from "./config.js";

describe("parseConfig", () => {
  const base = [
    "--data-root",
    "/tmp/data",
    "--token-file",
    "/tmp/token",
    "--log-dir",
    "/tmp/logs",
  ];

  it("parses defaults", () => {
    const c = parseConfig(base);
    expect(c.bindHost).toBe("127.0.0.1");
    expect(c.bindPort).toBe(0);
  });

  it("rejects non-loopback bind", () => {
    expect(() => parseConfig([...base, "--bind", "0.0.0.0:8080"])).toThrow(ConfigError);
  });

  it("requires data-root", () => {
    expect(() =>
      parseConfig(["--token-file", "/t", "--log-dir", "/l"]),
    ).toThrow(ConfigError);
  });
});
