import { z } from "zod";
import {
  ClientCommandSchema,
  ClientHelloSchema,
  ClientMessageSchema,
  ServerMessageSchema,
  type ClientCommand,
  type ClientHello,
  type ClientMessage,
  type ServerMessage,
} from "./messages.js";

const KNOWN_COMMAND_KINDS = new Set(
  ClientCommandSchema.options.map((schema) => {
    const shape = schema.shape as { kind: z.ZodLiteral<string> };
    return shape.kind.value;
  }),
);

export class ProtocolError extends Error {
  readonly code: string;
  readonly details?: unknown;

  constructor(code: string, message: string, details?: unknown) {
    super(message);
    this.name = "ProtocolError";
    this.code = code;
    this.details = details;
  }
}

function formatZod(err: z.ZodError): string {
  return err.issues.map((i) => `${i.path.join(".") || "(root)"}: ${i.message}`).join("; ");
}

export function parseJsonText(raw: string): unknown {
  try {
    return JSON.parse(raw) as unknown;
  } catch {
    throw new ProtocolError("invalid_json", "Message is not valid JSON");
  }
}

export function parseClientMessage(raw: unknown): ClientMessage {
  const result = ClientMessageSchema.safeParse(raw);
  if (!result.success) {
    throw new ProtocolError("invalid_message", formatZod(result.error), result.error.flatten());
  }
  return result.data;
}

export function parseClientHello(raw: unknown): ClientHello {
  const result = ClientHelloSchema.safeParse(raw);
  if (!result.success) {
    throw new ProtocolError("invalid_hello", formatZod(result.error), result.error.flatten());
  }
  return result.data;
}

/**
 * Parse a client command. Unknown `kind` values fail closed (not pass-through).
 */
export function parseClientCommand(raw: unknown): ClientCommand {
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
    throw new ProtocolError("invalid_command", "Command must be a JSON object");
  }
  const kind = (raw as { kind?: unknown }).kind;
  if (typeof kind !== "string") {
    throw new ProtocolError("invalid_command", "Command missing kind");
  }
  if (kind === "hello") {
    throw new ProtocolError("invalid_command", "hello is not a post-auth command");
  }
  if (!KNOWN_COMMAND_KINDS.has(kind)) {
    throw new ProtocolError("unknown_command", `Unknown command kind: ${kind}`);
  }
  const result = ClientCommandSchema.safeParse(raw);
  if (!result.success) {
    throw new ProtocolError("invalid_command", formatZod(result.error), result.error.flatten());
  }
  return result.data;
}

export function parseServerMessage(raw: unknown): ServerMessage {
  const result = ServerMessageSchema.safeParse(raw);
  if (!result.success) {
    throw new ProtocolError("invalid_server_message", formatZod(result.error), result.error.flatten());
  }
  return result.data;
}
