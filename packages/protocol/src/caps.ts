import { z } from "zod";

/** Agent surface capabilities — not OS features. */
export const CapSchema = z.enum([
  "streaming_text",
  "tools",
  "approvals",
  "resume",
  "subagents",
  "mcp",
  "artifacts",
  "models_list",
]);

export type Cap = z.infer<typeof CapSchema>;

export const CapsSchema = z.array(CapSchema);
