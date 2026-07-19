import { z } from "zod";
import { CapsSchema } from "./caps.js";
import { EventFrameSchema } from "./events.js";
import { PROTOCOL_VERSION } from "./version.js";

// ── Server → client ──────────────────────────────────────────────────────────

export const ServerHelloSchema = z.object({
  kind: z.literal("hello"),
  protocolVersion: z.literal(PROTOCOL_VERSION),
  server: z
    .object({
      name: z.string().default("code-free-orch"),
      version: z.string().optional(),
    })
    .default({ name: "code-free-orch" }),
});

export type ServerHello = z.infer<typeof ServerHelloSchema>;

export const SnapshotSchema = z.object({
  kind: z.literal("snapshot"),
  sessionId: z.string().min(1),
  /** Inclusive last seq included in this snapshot's events (0 if empty). */
  lastSeq: z.number().int().nonnegative(),
  events: z.array(EventFrameSchema),
});

export type Snapshot = z.infer<typeof SnapshotSchema>;

export const ErrorFrameSchema = z.object({
  kind: z.literal("error"),
  code: z.string().min(1),
  message: z.string(),
  sessionId: z.string().optional(),
  details: z.record(z.unknown()).optional(),
});

export type ErrorFrame = z.infer<typeof ErrorFrameSchema>;

export const ServerMessageSchema = z.discriminatedUnion("kind", [
  ServerHelloSchema,
  SnapshotSchema,
  EventFrameSchema,
  ErrorFrameSchema,
]);

export type ServerMessage = z.infer<typeof ServerMessageSchema>;

// ── Client → server ──────────────────────────────────────────────────────────

export const ClientHelloSchema = z.object({
  kind: z.literal("hello"),
  protocolVersion: z.literal(PROTOCOL_VERSION),
  /** Required on every connection. */
  token: z.string().min(1),
  client: z
    .object({
      name: z.string().optional(),
      version: z.string().optional(),
    })
    .optional(),
});

export type ClientHello = z.infer<typeof ClientHelloSchema>;

export const SessionCreateSchema = z.object({
  kind: z.literal("session.create"),
  requestId: z.string().min(1),
  cwd: z.string().min(1),
  title: z.string().optional(),
  harnessId: z.string().optional(),
  model: z.string().optional(),
  seed: z.string().optional(),
});

export const SessionListSchema = z.object({
  kind: z.literal("session.list"),
  requestId: z.string().min(1),
});

export const SessionSubscribeSchema = z.object({
  kind: z.literal("session.subscribe"),
  requestId: z.string().min(1),
  sessionId: z.string().min(1),
  /** Resume after this seq (gap fill). Omit or 0 = full snapshot from start. */
  afterSeq: z.number().int().nonnegative().optional(),
});

export const SessionUnsubscribeSchema = z.object({
  kind: z.literal("session.unsubscribe"),
  requestId: z.string().min(1),
  sessionId: z.string().min(1),
});

export const SessionSendSchema = z.object({
  kind: z.literal("session.send"),
  requestId: z.string().min(1),
  sessionId: z.string().min(1),
  text: z.string(),
  attachments: z.array(z.record(z.unknown())).optional(),
});

export const SessionCancelSchema = z.object({
  kind: z.literal("session.cancel"),
  requestId: z.string().min(1),
  sessionId: z.string().min(1),
});

export const SessionRenameSchema = z.object({
  kind: z.literal("session.rename"),
  requestId: z.string().min(1),
  sessionId: z.string().min(1),
  title: z.string().min(1),
});

export const ApprovalRespondSchema = z.object({
  kind: z.literal("approval.respond"),
  requestId: z.string().min(1),
  sessionId: z.string().min(1),
  approvalId: z.string().min(1),
  decision: z.enum(["allow", "deny"]),
});

export const HarnessListSchema = z.object({
  kind: z.literal("harness.list"),
  requestId: z.string().min(1),
});

export const ModelsListSchema = z.object({
  kind: z.literal("models.list"),
  requestId: z.string().min(1),
  harnessId: z.string().optional(),
});

export const ProjectCreateSchema = z.object({
  kind: z.literal("project.create"),
  requestId: z.string().min(1),
  path: z.string().min(1),
  name: z.string().optional(),
  defaultHarnessId: z.string().optional(),
});

export const ProjectListSchema = z.object({
  kind: z.literal("project.list"),
  requestId: z.string().min(1),
});

/**
 * Known client commands. Invalid / unknown kinds fail closed at the boundary.
 * Client hello is separate (auth handshake).
 */
export const ClientCommandSchema = z.discriminatedUnion("kind", [
  SessionCreateSchema,
  SessionListSchema,
  SessionSubscribeSchema,
  SessionUnsubscribeSchema,
  SessionSendSchema,
  SessionCancelSchema,
  SessionRenameSchema,
  ApprovalRespondSchema,
  HarnessListSchema,
  ModelsListSchema,
  ProjectCreateSchema,
  ProjectListSchema,
]);

export type ClientCommand = z.infer<typeof ClientCommandSchema>;

export const ClientMessageSchema = z.union([ClientHelloSchema, ClientCommandSchema]);

export type ClientMessage = z.infer<typeof ClientMessageSchema>;

/** Response envelope for request/response commands (server → client). */
export const CommandResultSchema = z.object({
  kind: z.literal("result"),
  requestId: z.string().min(1),
  ok: z.boolean(),
  data: z.unknown().optional(),
  error: z
    .object({
      code: z.string(),
      message: z.string(),
    })
    .optional(),
});

export type CommandResult = z.infer<typeof CommandResultSchema>;

export const HarnessInfoSchema = z.object({
  id: z.string(),
  name: z.string(),
  caps: CapsSchema,
});

export type HarnessInfo = z.infer<typeof HarnessInfoSchema>;
