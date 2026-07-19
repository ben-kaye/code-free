import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ModelInfo } from "@code-free/adapter-core";

/** Static fallback when cache is missing or unreadable. */
export const STATIC_GROK_MODELS: ModelInfo[] = [
  { id: "grok-4.5", name: "Grok 4.5" },
  { id: "grok-build", name: "Grok Build" },
];

/**
 * listModels: try ~/.grok/models_cache.json, else static fallback.
 * Never throws — missing cache is not an error.
 */
export function listGrokModels(cachePath?: string): ModelInfo[] {
  const path = cachePath ?? join(homedir(), ".grok", "models_cache.json");
  try {
    const raw = JSON.parse(readFileSync(path, "utf8")) as unknown;
    const parsed = extractModels(raw);
    if (parsed.length > 0) return parsed;
  } catch {
    /* fall through */
  }
  return [...STATIC_GROK_MODELS];
}

function extractModels(raw: unknown): ModelInfo[] {
  if (!raw || typeof raw !== "object") return [];
  const obj = raw as Record<string, unknown>;

  // Common shapes: { models: [...] } or array root or { data: [...] }
  const list = Array.isArray(raw)
    ? raw
    : Array.isArray(obj.models)
      ? obj.models
      : Array.isArray(obj.data)
        ? obj.data
        : null;
  if (!list) return [];

  const out: ModelInfo[] = [];
  for (const item of list) {
    if (!item || typeof item !== "object") continue;
    const m = item as Record<string, unknown>;
    const id =
      typeof m.id === "string"
        ? m.id
        : typeof m.modelId === "string"
          ? m.modelId
          : typeof m.name === "string"
            ? m.name
            : null;
    if (!id) continue;
    const name =
      typeof m.displayName === "string"
        ? m.displayName
        : typeof m.name === "string" && m.name !== id
          ? m.name
          : undefined;
    out.push(name ? { id, name } : { id });
  }
  return out;
}
