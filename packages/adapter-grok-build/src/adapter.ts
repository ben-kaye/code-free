import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import {
  AdapterError,
  type AdapterRun,
  type EventSink,
  type HarnessAdapter,
  type TaskSpec,
} from "@code-free/adapter-core";
import type { Cap } from "@code-free/protocol";
import { AcpClient } from "./acp-client.js";
import { mapAcpUpdate } from "./map-update.js";
import { listGrokModels } from "./models.js";
import { resolveGrokBinary } from "./resolve-binary.js";

export const GROK_BUILD_ID = "grok-build";
export const GROK_BUILD_NAME = "Grok Build";

export const GROK_BUILD_CAPS: Cap[] = [
  "streaming_text",
  "tools",
  "approvals",
  "resume",
  "models_list",
];

export type GrokBuildAdapterOptions = {
  /** Override binary resolution (tests). */
  resolveBinary?: () => string | null;
  /** Extra spawn args after `agent` (before `stdio`). */
  agentArgs?: string[];
  /** Env for child (defaults to process.env). */
  env?: NodeJS.ProcessEnv;
};

/**
 * Harness adapter for Grok Build via `grok agent stdio` (ACP).
 */
export function createGrokBuildAdapter(
  options: GrokBuildAdapterOptions = {},
): HarnessAdapter {
  return {
    id: GROK_BUILD_ID,
    name: GROK_BUILD_NAME,
    caps: [...GROK_BUILD_CAPS],
    async listModels() {
      return listGrokModels();
    },
    async start(spec: TaskSpec, sink: EventSink): Promise<AdapterRun> {
      return startGrokRun(spec, sink, options);
    },
  };
}

async function startGrokRun(
  spec: TaskSpec,
  sink: EventSink,
  options: GrokBuildAdapterOptions,
): Promise<AdapterRun> {
  const resolve = options.resolveBinary ?? (() => resolveGrokBinary(options.env));
  const binary = resolve();
  if (!binary) {
    throw new AdapterError(
      "binary_not_found",
      "Grok binary not found. Set CODE_FREE_GROK or install `grok` on PATH.",
    );
  }

  const agentArgs = options.agentArgs ?? [];
  const args = ["agent", ...agentArgs, "stdio"];
  if (spec.model) {
    // `grok agent --model X stdio`
    args.splice(1, 0, "--model", spec.model);
  }

  let child: ChildProcessWithoutNullStreams;
  try {
    child = spawn(binary, args, {
      cwd: spec.cwd,
      env: options.env ?? process.env,
      stdio: ["pipe", "pipe", "pipe"],
    }) as ChildProcessWithoutNullStreams;
  } catch (err) {
    throw new AdapterError(
      "spawn_failed",
      `Failed to spawn grok: ${err instanceof Error ? err.message : String(err)}`,
    );
  }

  if (!child.pid) {
    throw new AdapterError("spawn_failed", "Failed to spawn grok (no pid)");
  }

  const pendingApprovals = new Map<
    string,
    { resolve: (optionId: string | "cancelled") => void }
  >();

  let turnBusy = false;
  let messageId = cryptoRandomId();
  let thinkingId = cryptoRandomId();
  let disposed = false;
  let childExitError: string | null = null;

  const client = new AcpClient(child, {
    onNotification(method, params) {
      if (method === "session/update") {
        const drafts = mapAcpUpdate(params, { messageId, thinkingId });
        for (const d of drafts) {
          try {
            sink.emit(d);
          } catch {
            /* host durability failure — do not swallow permanently; rethrow path is host's */
          }
        }
        return;
      }
      if (method === "raw") {
        sink.emitRaw?.(String((params as { line?: string })?.line ?? params));
        return;
      }
      // Unknown notification — log without secrets
      try {
        sink.emit({ type: "log", payload: { method, note: "acp notification" } });
      } catch {
        /* ignore */
      }
    },
    async onRequest(method, params) {
      if (method === "session/request_permission") {
        return handlePermissionRequest(params, sink, pendingApprovals);
      }
      // Optional client methods we don't implement yet — cancel outcome for tools
      if (method.startsWith("fs/") || method.startsWith("terminal/")) {
        throw new Error(`Client method not implemented: ${method}`);
      }
      throw new Error(`Unhandled agent request: ${method}`);
    },
    onClose(code, signal) {
      if (disposed) return;
      if (code !== 0 && code !== null) {
        childExitError = `Harness process exited (code=${code})`;
        try {
          sink.emit({
            type: "session.error",
            payload: {
              code: "harness_error",
              message: childExitError,
            },
          });
        } catch {
          /* ignore */
        }
      } else if (signal) {
        childExitError = `Harness process killed (${signal})`;
      }
    },
    onStderrLine(line) {
      // Never log secrets; stderr may contain paths — keep short
      sink.emitRaw?.(line.slice(0, 500));
    },
  });

  try {
    await client.request("initialize", {
      protocolVersion: 1,
      clientInfo: { name: "code-free", version: "0.1.0" },
      clientCapabilities: {
        fs: { readTextFile: false, writeTextFile: false },
      },
    });
  } catch (err) {
    client.dispose();
    throw new AdapterError(
      "protocol_error",
      `ACP initialize failed: ${err instanceof Error ? err.message : String(err)}`,
    );
  }

  let resumeToken: string | undefined = spec.resumeToken;

  try {
    if (spec.resumeToken) {
      await client.request("session/load", {
        sessionId: spec.resumeToken,
        cwd: spec.cwd,
        mcpServers: [],
      });
      resumeToken = spec.resumeToken;
    } else {
      const result = (await client.request("session/new", {
        cwd: spec.cwd,
        mcpServers: [],
      })) as { sessionId?: string };
      if (!result?.sessionId) {
        throw new Error("session/new returned no sessionId");
      }
      resumeToken = result.sessionId;
    }
  } catch (err) {
    // Resume failed → try new session (honest cold harness context)
    if (spec.resumeToken) {
      try {
        const result = (await client.request("session/new", {
          cwd: spec.cwd,
          mcpServers: [],
        })) as { sessionId?: string };
        if (!result?.sessionId) throw new Error("session/new returned no sessionId");
        resumeToken = result.sessionId;
      } catch (err2) {
        client.dispose();
        throw new AdapterError(
          "protocol_error",
          `ACP session setup failed: ${err2 instanceof Error ? err2.message : String(err2)}`,
        );
      }
    } else {
      client.dispose();
      throw new AdapterError(
        "protocol_error",
        `ACP session/new failed: ${err instanceof Error ? err.message : String(err)}`,
      );
    }
  }

  const run: AdapterRun = {
    get resumeToken() {
      return resumeToken;
    },

    async send(text: string): Promise<void> {
      if (disposed || client.isClosed) {
        throw new AdapterError("not_running", "Harness run is not active");
      }
      if (turnBusy) {
        throw new AdapterError("turn_in_progress", "A turn is already in progress");
      }
      turnBusy = true;
      messageId = cryptoRandomId();
      thinkingId = cryptoRandomId();
      try {
        await client.request("session/prompt", {
          sessionId: resumeToken,
          prompt: [{ type: "text", text }],
        });
        // Prompt completed — close open streams
        try {
          sink.emit({ type: "thinking.done", payload: { id: thinkingId } });
        } catch {
          /* ignore */
        }
        try {
          sink.emit({ type: "message.done", payload: { id: messageId } });
        } catch {
          /* ignore */
        }
      } catch (err) {
        if (childExitError) {
          throw new AdapterError("harness_error", childExitError);
        }
        throw new AdapterError(
          "harness_error",
          err instanceof Error ? err.message : String(err),
        );
      } finally {
        turnBusy = false;
      }
    },

    async cancel(): Promise<void> {
      // Resolve pending approvals as cancelled
      for (const [id, p] of pendingApprovals) {
        p.resolve("cancelled");
        pendingApprovals.delete(id);
      }
      try {
        await client.notify("session/cancel", { sessionId: resumeToken });
      } catch {
        /* best effort */
      }
      // If still busy after a short grace, SIGTERM via dispose path on host
    },

    async approve(approvalId: string, decision: "allow" | "deny"): Promise<void> {
      const pending = pendingApprovals.get(approvalId);
      if (!pending) {
        throw new AdapterError("not_running", `No pending approval: ${approvalId}`);
      }
      pendingApprovals.delete(approvalId);
      // Map allow/deny to ACP option kinds
      pending.resolve(decision === "allow" ? "allow-once" : "reject-once");
      try {
        sink.emit({
          type: "approval.resolved",
          payload: { id: approvalId, decision },
        });
      } catch {
        /* ignore */
      }
    },

    async dispose(): Promise<void> {
      if (disposed) return;
      disposed = true;
      for (const [, p] of pendingApprovals) p.resolve("cancelled");
      pendingApprovals.clear();
      client.dispose();
    },
  };

  return run;
}

async function handlePermissionRequest(
  params: unknown,
  sink: EventSink,
  pendingApprovals: Map<string, { resolve: (optionId: string | "cancelled") => void }>,
): Promise<unknown> {
  const p = (params ?? {}) as {
    toolCall?: { toolCallId?: string; title?: string };
    options?: Array<{ optionId: string; name?: string; kind?: string }>;
  };
  const approvalId = p.toolCall?.toolCallId ?? cryptoRandomId();
  const options = p.options ?? [];

  sink.emit({
    type: "approval.requested",
    payload: {
      id: approvalId,
      title: p.toolCall?.title ?? "Permission required",
      toolCallId: p.toolCall?.toolCallId ?? null,
      options,
    },
  });

  const selected = await new Promise<string | "cancelled">((resolve) => {
    pendingApprovals.set(approvalId, { resolve });
  });

  if (selected === "cancelled") {
    return { outcome: { outcome: "cancelled" } };
  }

  // Prefer exact optionId match; fall back to first allow/reject kind
  const match = options.find((o) => o.optionId === selected);
  if (match) {
    return { outcome: { outcome: "selected", optionId: match.optionId } };
  }
  const byKind =
    selected === "allow-once"
      ? options.find((o) => o.kind === "allow_once" || o.kind === "allow_always")
      : options.find((o) => o.kind === "reject_once" || o.kind === "reject_always");
  if (byKind) {
    return { outcome: { outcome: "selected", optionId: byKind.optionId } };
  }
  if (options[0]) {
    return { outcome: { outcome: "selected", optionId: options[0].optionId } };
  }
  return { outcome: { outcome: "cancelled" } };
}

function cryptoRandomId(): string {
  return globalThis.crypto.randomUUID();
}
