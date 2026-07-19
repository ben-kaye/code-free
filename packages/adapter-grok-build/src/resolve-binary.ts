import { accessSync, constants } from "node:fs";
import { homedir } from "node:os";
import { delimiter, isAbsolute, join } from "node:path";

/**
 * Resolve `grok` binary. Order: CODE_FREE_GROK env → PATH → well-known install dirs.
 * Well-known paths cover GUI apps (Xcode/Dock) whose PATH omits shell profile dirs.
 * Does not log the path beyond returning it (caller may surface in errors).
 */
export function resolveGrokBinary(env: NodeJS.ProcessEnv = process.env): string | null {
  const fromEnv = env.CODE_FREE_GROK?.trim();
  if (fromEnv) {
    if (isExecutable(fromEnv)) return fromEnv;
    return null;
  }
  return findOnPath("grok", env.PATH ?? "") ?? findWellKnown(env);
}

function findOnPath(name: string, pathEnv: string): string | null {
  for (const dir of pathEnv.split(delimiter)) {
    if (!dir) continue;
    const candidate = join(dir, name);
    if (isExecutable(candidate)) return candidate;
  }
  return null;
}

/** Default install locations when PATH is the minimal GUI set. */
function findWellKnown(env: NodeJS.ProcessEnv): string | null {
  const home = env.HOME?.trim() || tryHomedir();
  if (!home) return null;
  const candidates = [
    join(home, ".grok", "bin", "grok"),
    join(home, ".local", "bin", "grok"),
  ];
  for (const candidate of candidates) {
    if (isExecutable(candidate)) return candidate;
  }
  return null;
}

function tryHomedir(): string | null {
  try {
    return homedir();
  } catch {
    return null;
  }
}

function isExecutable(path: string): boolean {
  if (!isAbsolute(path) && path !== "grok" && !path.includes("/") && !path.includes("\\")) {
    // bare name without path — only accept via PATH walk
  }
  try {
    accessSync(path, constants.X_OK);
    return true;
  } catch {
    try {
      accessSync(path, constants.F_OK);
      return true;
    } catch {
      return false;
    }
  }
}
