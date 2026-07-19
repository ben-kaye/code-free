import { z } from "zod";
import { PROTOCOL_VERSION } from "./version.js";

/** Known semantic event types (server → client event frames). */
export const KnownEventTypeSchema = z.enum([
  "session.started",
  "session.ended",
  "session.error",
  "message.user",
  "message.delta",
  "message.done",
  "thinking.delta",
  "thinking.done",
  "tool.started",
  "tool.progress",
  "tool.done",
  "tool.error",
  "file.diff",
  "file.write",
  "artifact.created",
  "artifact.updated",
  "approval.requested",
  "approval.resolved",
  "plan.updated",
  "agent.started",
  "agent.progress",
  "agent.ended",
  "status",
  "status.turn_start",
  "status.turn_end",
  "log",
  "raw",
]);

export type KnownEventType = z.infer<typeof KnownEventTypeSchema>;

/**
 * Event type on the wire: known names or future/unknown strings.
 * Clients may ignore unknown types; orch still persists them.
 */
export const EventTypeSchema = z.string().min(1);

export const EventFrameSchema = z.object({
  protocolVersion: z.literal(PROTOCOL_VERSION),
  kind: z.literal("event"),
  sessionId: z.string().min(1),
  seq: z.number().int().positive(),
  ts: z.string().datetime({ offset: true }),
  type: EventTypeSchema,
  payload: z.record(z.unknown()).default({}),
});

export type EventFrame = z.infer<typeof EventFrameSchema>;

/** Adapter / internal emit before orch stamps seq/ts. */
export const EventDraftSchema = z.object({
  type: EventTypeSchema,
  payload: z.record(z.unknown()).default({}),
});

export type EventDraft = z.infer<typeof EventDraftSchema>;
