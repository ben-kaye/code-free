import { appendFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";

export type LogLevel = "debug" | "info" | "warn" | "error";

export class Logger {
  private readonly logPath: string;

  constructor(logDir: string) {
    mkdirSync(logDir, { recursive: true });
    this.logPath = join(logDir, "orch.log");
  }

  info(msg: string, fields?: Record<string, unknown>): void {
    this.write("info", msg, fields);
  }

  warn(msg: string, fields?: Record<string, unknown>): void {
    this.write("warn", msg, fields);
  }

  error(msg: string, fields?: Record<string, unknown>): void {
    this.write("error", msg, fields);
  }

  debug(msg: string, fields?: Record<string, unknown>): void {
    this.write("debug", msg, fields);
  }

  private write(level: LogLevel, msg: string, fields?: Record<string, unknown>): void {
    const redacted = fields ? redact(fields) : undefined;
    const line = JSON.stringify({
      ts: new Date().toISOString(),
      level,
      msg,
      ...redacted,
    });
    appendFileSync(this.logPath, line + "\n", { encoding: "utf8" });
    if (level === "error" || level === "warn") {
      console.error(line);
    } else {
      console.log(line);
    }
  }
}

const SECRET_KEYS = new Set(["token", "authorization", "password", "secret"]);

function redact(fields: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(fields)) {
    if (SECRET_KEYS.has(k.toLowerCase())) {
      out[k] = "[redacted]";
    } else {
      out[k] = v;
    }
  }
  return out;
}
