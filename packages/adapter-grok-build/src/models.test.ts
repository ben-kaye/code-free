import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import {
  encodeModelRef,
  listGrokModels,
  parseModelRef,
  STATIC_GROK_MODELS,
} from "./models.js";

describe("encodeModelRef / parseModelRef", () => {
  it("round-trips id and effort", () => {
    expect(encodeModelRef("grok-4.5", "high")).toBe("grok-4.5#high");
    expect(parseModelRef("grok-4.5#high")).toEqual({
      modelId: "grok-4.5",
      reasoningEffort: "high",
    });
  });

  it("omits effort when empty", () => {
    expect(encodeModelRef("grok-4.5")).toBe("grok-4.5");
    expect(encodeModelRef("grok-4.5", null)).toBe("grok-4.5");
    expect(parseModelRef("grok-4.5")).toEqual({
      modelId: "grok-4.5",
      reasoningEffort: undefined,
    });
  });

  it("handles empty / missing", () => {
    expect(parseModelRef(undefined)).toEqual({
      modelId: undefined,
      reasoningEffort: undefined,
    });
    expect(parseModelRef("")).toEqual({
      modelId: undefined,
      reasoningEffort: undefined,
    });
  });
});

describe("listGrokModels", () => {
  it("falls back to static when cache missing", () => {
    const models = listGrokModels(join(tmpdir(), "no-such-grok-models.json"));
    expect(models.map((m) => m.id)).toEqual(STATIC_GROK_MODELS.map((m) => m.id));
    expect(models[0]?.reasoningEfforts?.map((e) => e.id)).toEqual(["low", "medium", "high"]);
  });

  it("parses object-map cache with reasoning efforts", () => {
    const dir = mkdtempSync(join(tmpdir(), "cf-models-"));
    const path = join(dir, "models_cache.json");
    writeFileSync(
      path,
      JSON.stringify({
        models: {
          "grok-4.5": {
            info: {
              id: "grok-4.5",
              name: "Grok 4.5",
              hidden: false,
              reasoning_effort: "high",
              supports_reasoning_effort: true,
              reasoning_efforts: [
                { id: "high", value: "high", label: "High Effort", default: true },
                { id: "medium", value: "medium", label: "Medium Effort" },
                { id: "low", value: "low", label: "Low Effort" },
              ],
            },
          },
          "grok-4.4": {
            info: {
              id: "grok-4.4",
              name: "Grok 4.4",
              hidden: false,
              supports_reasoning_effort: true,
              reasoning_efforts: [
                { id: "high", label: "High Effort", default: true },
                { id: "low", label: "Low Effort" },
              ],
            },
          },
          hidden: {
            info: { id: "hidden", name: "Hidden", hidden: true },
          },
        },
      }),
    );

    const models = listGrokModels(path);
    expect(models.map((m) => m.id)).toEqual(["grok-4.5", "grok-4.4"]);
    expect(models[0]?.name).toBe("Grok 4.5");
    expect(models[0]?.defaultReasoningEffort).toBe("high");
    expect(models[0]?.reasoningEfforts?.map((e) => e.id)).toEqual([
      "high",
      "medium",
      "low",
    ]);
    expect(models[0]?.reasoningEfforts?.[0]?.label).toBe("High");
    expect(models[1]?.reasoningEfforts?.map((e) => e.id)).toEqual(["high", "low"]);
  });
});
