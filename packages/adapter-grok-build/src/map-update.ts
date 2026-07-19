import type { EventDraft } from "@code-free/protocol";

/**
 * Map one ACP session/update payload (the `update` object, or full params) to EventDrafts.
 * Lossy by design — unknown shapes become `log` / `raw`.
 */
export function mapAcpUpdate(
  update: unknown,
  ctx: { messageId: string; thinkingId: string },
): EventDraft[] {
  if (!update || typeof update !== "object") {
    return [{ type: "raw", payload: { value: update } }];
  }

  const u = update as Record<string, unknown>;
  // Support both { sessionUpdate, ... } and nested { update: { sessionUpdate } }
  const body =
    typeof u.sessionUpdate === "string"
      ? u
      : u.update && typeof u.update === "object"
        ? (u.update as Record<string, unknown>)
        : u;

  const kind = body.sessionUpdate;
  if (typeof kind !== "string") {
    return [{ type: "raw", payload: { value: update } }];
  }

  switch (kind) {
    case "agent_message_chunk": {
      const text = extractText(body.content);
      if (text === null) return [{ type: "log", payload: { message: "empty agent_message_chunk" } }];
      return [{ type: "message.delta", payload: { id: ctx.messageId, text } }];
    }
    case "agent_thought_chunk": {
      const text = extractText(body.content);
      if (text === null) return [{ type: "log", payload: { message: "empty agent_thought_chunk" } }];
      return [{ type: "thinking.delta", payload: { id: ctx.thinkingId, text } }];
    }
    case "tool_call": {
      const toolCallId = stringField(body, "toolCallId") ?? cryptoRandomId();
      return [
        {
          type: "tool.started",
          payload: {
            id: toolCallId,
            title: stringField(body, "title") ?? "tool",
            kind: stringField(body, "kind") ?? "other",
            status: stringField(body, "status") ?? "pending",
            rawInput: body.rawInput ?? null,
          },
        },
      ];
    }
    case "tool_call_update": {
      const toolCallId = stringField(body, "toolCallId") ?? "unknown";
      const status = stringField(body, "status");
      if (status === "failed") {
        return [
          {
            type: "tool.error",
            payload: {
              id: toolCallId,
              status,
              content: body.content ?? null,
              rawOutput: body.rawOutput ?? null,
            },
          },
        ];
      }
      if (status === "completed") {
        return [
          {
            type: "tool.done",
            payload: {
              id: toolCallId,
              status,
              content: body.content ?? null,
              rawOutput: body.rawOutput ?? null,
            },
          },
        ];
      }
      return [
        {
          type: "tool.progress",
          payload: {
            id: toolCallId,
            status: status ?? "in_progress",
            content: body.content ?? null,
            rawOutput: body.rawOutput ?? null,
          },
        },
      ];
    }
    case "plan": {
      return [
        {
          type: "plan.updated",
          payload: {
            entries: body.entries ?? body.content ?? body,
          },
        },
      ];
    }
    default:
      return [{ type: "log", payload: { sessionUpdate: kind, detail: body } }];
  }
}

/** Extract plain text from ACP content block shapes. */
export function extractText(content: unknown): string | null {
  if (content == null) return null;
  if (typeof content === "string") return content;
  if (typeof content === "object") {
    const c = content as Record<string, unknown>;
    if (typeof c.text === "string") return c.text;
    // { type: "text", text: "..." }
    if (c.type === "text" && typeof c.text === "string") return c.text;
  }
  return null;
}

function stringField(obj: Record<string, unknown>, key: string): string | undefined {
  const v = obj[key];
  return typeof v === "string" ? v : undefined;
}

function cryptoRandomId(): string {
  return globalThis.crypto.randomUUID();
}
