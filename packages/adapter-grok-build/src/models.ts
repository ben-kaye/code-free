import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ModelInfo, ReasoningEffortInfo } from "@code-free/adapter-core";

/** Separator between model id and reasoning effort in a stored model ref. */
export const MODEL_EFFORT_SEP = "#";

const DEFAULT_EFFORTS: ReasoningEffortInfo[] = [
  { id: "low", label: "Low" },
  { id: "medium", label: "Medium" },
  { id: "high", label: "High", default: true },
];

/** Static fallback when cache is missing or unreadable. */
export const STATIC_GROK_MODELS: ModelInfo[] = [
  {
    id: "grok-4.5",
    name: "Grok 4.5",
    reasoningEfforts: DEFAULT_EFFORTS,
    defaultReasoningEffort: "high",
  },
  {
    id: "grok-build",
    name: "Grok Build",
    reasoningEfforts: DEFAULT_EFFORTS,
    defaultReasoningEffort: "high",
  },
];

/**
 * Encode a matrix selection for durable session.model / TaskSpec.model.
 * Effort is omitted when unset or the model has no thinking levels.
 */
export function encodeModelRef(modelId: string, effortId?: string | null): string {
  const id = modelId.trim();
  if (!id) return id;
  const effort = effortId?.trim();
  if (!effort) return id;
  return `${id}${MODEL_EFFORT_SEP}${effort}`;
}

/**
 * Split a stored model ref into base id + optional reasoning effort.
 * Only the last `#` segment is treated as effort (model ids do not use `#`).
 */
export function parseModelRef(model: string | undefined | null): {
  modelId: string | undefined;
  reasoningEffort: string | undefined;
} {
  if (!model) return { modelId: undefined, reasoningEffort: undefined };
  const raw = model.trim();
  if (!raw) return { modelId: undefined, reasoningEffort: undefined };
  const idx = raw.lastIndexOf(MODEL_EFFORT_SEP);
  if (idx <= 0 || idx === raw.length - 1) {
    return { modelId: raw, reasoningEffort: undefined };
  }
  return {
    modelId: raw.slice(0, idx),
    reasoningEffort: raw.slice(idx + 1),
  };
}

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

  // Shapes: array root | { models: [...] } | { data: [...] } | { models: { id: entry } }
  let items: unknown[] | null = null;
  if (Array.isArray(raw)) {
    items = raw;
  } else if (Array.isArray(obj.models)) {
    items = obj.models;
  } else if (Array.isArray(obj.data)) {
    items = obj.data;
  } else if (obj.models && typeof obj.models === "object" && !Array.isArray(obj.models)) {
    items = Object.entries(obj.models as Record<string, unknown>).map(([key, value]) => {
      if (value && typeof value === "object") {
        const entry = value as Record<string, unknown>;
        // Cache shape: { info: { id, name, ... }, api_key, ... }
        if (entry.info && typeof entry.info === "object") {
          return { ...(entry.info as object), id: (entry.info as { id?: string }).id ?? key };
        }
        return { ...entry, id: (entry.id as string | undefined) ?? key };
      }
      return { id: key };
    });
  }
  if (!items) return [];

  const out: ModelInfo[] = [];
  for (const item of items) {
    const model = coerceModel(item);
    if (model) out.push(model);
  }
  return out;
}

function coerceModel(item: unknown): ModelInfo | null {
  if (!item || typeof item !== "object") return null;
  const m = item as Record<string, unknown>;

  if (m.hidden === true) return null;

  const id =
    typeof m.id === "string"
      ? m.id
      : typeof m.modelId === "string"
        ? m.modelId
        : typeof m.model === "string"
          ? m.model
          : typeof m.name === "string"
            ? m.name
            : null;
  if (!id) return null;

  const name =
    typeof m.displayName === "string"
      ? m.displayName
      : typeof m.name === "string" && m.name !== id
        ? m.name
        : undefined;

  const efforts = extractEfforts(m);
  const defaultEffort =
    typeof m.reasoning_effort === "string"
      ? m.reasoning_effort
      : typeof m.defaultReasoningEffort === "string"
        ? m.defaultReasoningEffort
        : efforts.find((e) => e.default)?.id;

  const info: ModelInfo = { id };
  if (name) info.name = name;
  if (efforts.length > 0) {
    info.reasoningEfforts = efforts;
    if (defaultEffort) info.defaultReasoningEffort = defaultEffort;
  } else if (m.supports_reasoning_effort === true) {
    // Supports effort but list missing — offer defaults so the matrix still works.
    info.reasoningEfforts = DEFAULT_EFFORTS;
    info.defaultReasoningEffort = "high";
  }
  return info;
}

function extractEfforts(m: Record<string, unknown>): ReasoningEffortInfo[] {
  const raw = m.reasoning_efforts ?? m.reasoningEfforts;
  if (!Array.isArray(raw)) return [];
  const out: ReasoningEffortInfo[] = [];
  for (const item of raw) {
    if (!item || typeof item !== "object") continue;
    const e = item as Record<string, unknown>;
    const id =
      typeof e.id === "string"
        ? e.id
        : typeof e.value === "string"
          ? e.value
          : null;
    if (!id) continue;
    const label =
      typeof e.label === "string"
        ? shortenEffortLabel(e.label)
        : undefined;
    const effort: ReasoningEffortInfo = { id };
    if (label) effort.label = label;
    if (e.default === true) effort.default = true;
    out.push(effort);
  }
  return out;
}

/** "High Effort" → "High" for compact matrix headers. */
function shortenEffortLabel(label: string): string {
  return label.replace(/\s*effort\s*$/i, "").trim() || label;
}
