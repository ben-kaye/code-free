import { randomBytes } from "node:crypto";
import { chmodSync, mkdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname } from "node:path";
import { timingSafeEqual } from "node:crypto";

/**
 * Ensure a token file exists (create if missing) with mode 0600.
 * Returns the token string.
 */
export function ensureTokenFile(tokenFile: string): string {
  mkdirSync(dirname(tokenFile), { recursive: true });
  if (existsSync(tokenFile)) {
    const existing = readFileSync(tokenFile, "utf8").trim();
    if (existing.length > 0) {
      try {
        chmodSync(tokenFile, 0o600);
      } catch {
        // best-effort on platforms that ignore mode
      }
      return existing;
    }
  }
  const token = randomBytes(32).toString("base64url");
  writeFileSync(tokenFile, token + "\n", { encoding: "utf8", mode: 0o600 });
  try {
    chmodSync(tokenFile, 0o600);
  } catch {
    // ignore
  }
  return token;
}

/** Constant-time token compare. */
export function tokensEqual(a: string, b: string): boolean {
  const ba = Buffer.from(a);
  const bb = Buffer.from(b);
  if (ba.length !== bb.length) {
    // compare against self to keep timing roughly steady
    timingSafeEqual(ba, ba);
    return false;
  }
  return timingSafeEqual(ba, bb);
}
