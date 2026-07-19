import { createServer, type Server as HttpServer } from "node:http";
import { WebSocketServer, WebSocket } from "ws";
import {
  PROTOCOL_VERSION,
  ProtocolError,
  parseJsonText,
  parseClientHello,
  parseClientCommand,
  type ClientCommand,
  type CommandResult,
  type ServerHello,
  type Snapshot,
  type EventFrame,
  type ErrorFrame,
  type EventDraft,
} from "@code-free/protocol";
import type { HarnessAdapter } from "@code-free/adapter-core";
import { createGrokBuildAdapter } from "@code-free/adapter-grok-build";
import { EventStore } from "@code-free/store";
import type { OrchConfig } from "./config.js";
import { Logger } from "./logger.js";
import { SessionManager, SessionError } from "./sessions.js";
import { AdapterHost } from "./adapter-host.js";
import { ensureTokenFile, tokensEqual } from "./token.js";

type ClientState = {
  authed: boolean;
  /** sessionId → true */
  subscriptions: Set<string>;
};

export type StartOrchestratorOptions = {
  /**
   * Adapters to register. Default: Grok Build.
   * Pass `[]` to keep honest empty harness list (tests / no-adapter mode).
   */
  adapters?: HarnessAdapter[];
};

export type RunningOrch = {
  config: OrchConfig;
  token: string;
  host: string;
  port: number;
  endpoint: string;
  close: () => Promise<void>;
};

export async function startOrchestrator(
  config: OrchConfig,
  log: Logger,
  options: StartOrchestratorOptions = {},
): Promise<RunningOrch> {
  const token = ensureTokenFile(config.tokenFile);
  const store = new EventStore({ dataRoot: config.dataRoot });

  const broadcastRef: { fn: (sessionId: string, frame: EventFrame) => void } = {
    fn: () => {},
  };

  const adapterHost = new AdapterHost((sessionId, draft: EventDraft) => {
    try {
      const frame = store.appendEvent(sessionId, draft);
      broadcastRef.fn(sessionId, frame);
    } catch (err) {
      log.error("adapter emit failed", {
        sessionId,
        err: err instanceof Error ? err.message : String(err),
      });
      throw err;
    }
  });

  const adapters =
    options.adapters !== undefined ? options.adapters : [createGrokBuildAdapter()];
  for (const a of adapters) {
    adapterHost.register(a);
  }

  const sessions = new SessionManager(store, adapterHost);
  const purged = sessions.purgeExpiredArchives();
  if (purged > 0) {
    log.info(`purged ${purged} archived session(s) older than 7 days`);
  }

  const httpServer: HttpServer = createServer((_req, res) => {
    res.writeHead(426, { "Content-Type": "text/plain" });
    res.end("WebSocket only\n");
  });

  const wss = new WebSocketServer({ server: httpServer });

  /** sessionId → set of sockets subscribed */
  const subscribers = new Map<string, Set<WebSocket>>();

  const broadcast = (sessionId: string, frame: EventFrame) => {
    const set = subscribers.get(sessionId);
    if (!set) return;
    const raw = JSON.stringify(frame);
    for (const ws of set) {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(raw);
      }
    }
  };
  broadcastRef.fn = broadcast;

  const trackSub = (ws: WebSocket, sessionId: string, on: boolean) => {
    let set = subscribers.get(sessionId);
    if (on) {
      if (!set) {
        set = new Set();
        subscribers.set(sessionId, set);
      }
      set.add(ws);
    } else if (set) {
      set.delete(ws);
      if (set.size === 0) subscribers.delete(sessionId);
    }
  };

  wss.on("connection", (ws) => {
    const state: ClientState = { authed: false, subscriptions: new Set() };

    ws.on("message", (data, isBinary) => {
      if (isBinary) {
        sendError(ws, { kind: "error", code: "invalid_frame", message: "Binary frames not supported" });
        return;
      }
      const text = data.toString("utf8");
      try {
        handleMessage(ws, state, text);
      } catch (err) {
        if (err instanceof ProtocolError) {
          sendError(ws, {
            kind: "error",
            code: err.code,
            message: err.message,
          });
          if (err.code === "auth_failed" || err.code === "invalid_hello") {
            ws.close(4001, err.code);
          }
          return;
        }
        log.error("unhandled message error", {
          err: err instanceof Error ? err.message : String(err),
        });
        sendError(ws, {
          kind: "error",
          code: "internal",
          message: "Internal error",
        });
      }
    });

    ws.on("close", () => {
      for (const sessionId of state.subscriptions) {
        trackSub(ws, sessionId, false);
      }
      state.subscriptions.clear();
    });

    function handleMessage(socket: WebSocket, st: ClientState, text: string): void {
      const raw = parseJsonText(text);

      if (!st.authed) {
        const hello = parseClientHello(raw);
        if (!tokensEqual(hello.token, token)) {
          throw new ProtocolError("auth_failed", "Invalid token");
        }
        st.authed = true;
        const serverHello: ServerHello = {
          kind: "hello",
          protocolVersion: PROTOCOL_VERSION,
          server: { name: "code-free-orch", version: "0.1.0" },
        };
        socket.send(JSON.stringify(serverHello));
        log.info("client authenticated");
        return;
      }

      const cmd = parseClientCommand(raw);
      void dispatch(cmd, st, socket).then((result) => {
        if (socket.readyState === WebSocket.OPEN) {
          socket.send(JSON.stringify(result));
        }
      });
    }

    async function dispatch(
      cmd: ClientCommand,
      st: ClientState,
      socket: WebSocket,
    ): Promise<CommandResult> {
      try {
        switch (cmd.kind) {
          case "session.create": {
            const { session, started } = sessions.create({
              cwd: cmd.cwd,
              title: cmd.title,
              harnessId: cmd.harnessId,
              model: cmd.model,
              seed: cmd.seed,
            });
            broadcast(session.id, started);
            return ok(cmd.requestId, { session, event: started });
          }
          case "session.list": {
            const filter = cmd.filter ?? "active";
            return ok(cmd.requestId, { sessions: sessions.list(filter), filter });
          }
          case "session.archive": {
            const session = sessions.archive(cmd.sessionId);
            subscribers.delete(cmd.sessionId);
            st.subscriptions.delete(cmd.sessionId);
            sessions.purgeExpiredArchives();
            return ok(cmd.requestId, { session });
          }
          case "session.subscribe": {
            const summary = sessions.get(cmd.sessionId);
            if (!summary) {
              return fail(cmd.requestId, "session_not_found", "Session not found");
            }
            const afterSeq = cmd.afterSeq ?? 0;
            const events = sessions.eventsAfter(cmd.sessionId, afterSeq);
            const lastSeq = sessions.lastSeq(cmd.sessionId);
            const snapshot: Snapshot = {
              kind: "snapshot",
              sessionId: cmd.sessionId,
              lastSeq,
              events,
            };
            socket.send(JSON.stringify(snapshot));
            st.subscriptions.add(cmd.sessionId);
            trackSub(socket, cmd.sessionId, true);
            return ok(cmd.requestId, { sessionId: cmd.sessionId, lastSeq, afterSeq });
          }
          case "session.unsubscribe": {
            st.subscriptions.delete(cmd.sessionId);
            trackSub(socket, cmd.sessionId, false);
            return ok(cmd.requestId, { sessionId: cmd.sessionId });
          }
          case "session.send": {
            const { events, driveTurn } = sessions.beginUserMessage(cmd.sessionId, cmd.text);
            for (const ev of events) broadcast(cmd.sessionId, ev);
            // Kick async turn after RPC returns events (stream continues via broadcast)
            if (driveTurn) {
              void driveTurn().catch((err) => {
                log.error("turn failed", {
                  sessionId: cmd.sessionId,
                  err: err instanceof Error ? err.message : String(err),
                });
              });
            }
            return ok(cmd.requestId, { events });
          }
          case "session.cancel": {
            const ended = await sessions.cancel(cmd.sessionId);
            broadcast(cmd.sessionId, ended);
            return ok(cmd.requestId, { event: ended });
          }
          case "session.rename": {
            const session = sessions.rename(cmd.sessionId, cmd.title);
            return ok(cmd.requestId, { session });
          }
          case "harness.list": {
            return ok(cmd.requestId, { harnesses: adapterHost.listHarnesses() });
          }
          case "models.list": {
            const models = await adapterHost.listModels(cmd.harnessId);
            return ok(cmd.requestId, { models });
          }
          case "project.create":
          case "project.list": {
            return fail(
              cmd.requestId,
              "not_implemented",
              "Projects are shell-owned metadata in v0; orch stores session cwd only",
            );
          }
          case "approval.respond": {
            try {
              await sessions.approve(cmd.sessionId, cmd.approvalId, cmd.decision);
              return ok(cmd.requestId, { sessionId: cmd.sessionId, approvalId: cmd.approvalId });
            } catch (err) {
              if (err instanceof SessionError) {
                return fail(cmd.requestId, err.code, err.message);
              }
              throw err;
            }
          }
          default: {
            const _exhaustive: never = cmd;
            return fail("unknown", "unknown_command", `Unhandled: ${JSON.stringify(_exhaustive)}`);
          }
        }
      } catch (err) {
        if (err instanceof SessionError) {
          return fail(cmd.requestId, err.code, err.message);
        }
        throw err;
      }
    }
  });

  await new Promise<void>((resolve, reject) => {
    httpServer.once("error", reject);
    httpServer.listen(config.bindPort, config.bindHost, () => resolve());
  });

  const addr = httpServer.address();
  if (!addr || typeof addr === "string") {
    throw new Error("Failed to bind HTTP server");
  }
  const host = addr.address === "::1" ? "127.0.0.1" : addr.address;
  const port = addr.port;
  const endpoint = `ws://${host}:${port}`;

  // Endpoint line for shell/host (stdout once) — token is only in token-file
  console.log(JSON.stringify({ endpoint, tokenFile: config.tokenFile }));
  log.info("orchestrator listening", { endpoint, dataRoot: config.dataRoot });

  let closed = false;
  const close = async () => {
    if (closed) return;
    closed = true;
    await adapterHost.disposeAll();
    await new Promise<void>((resolve) => {
      wss.close(() => resolve());
    });
    await new Promise<void>((resolve, reject) => {
      httpServer.close((err) => (err ? reject(err) : resolve()));
    });
    store.close();
    log.info("orchestrator stopped");
  };

  return { config, token, host, port, endpoint, close };
}

function ok(requestId: string, data: unknown): CommandResult {
  return { kind: "result", requestId, ok: true, data };
}

function fail(requestId: string, code: string, message: string): CommandResult {
  return { kind: "result", requestId, ok: false, error: { code, message } };
}

function sendError(ws: WebSocket, frame: ErrorFrame): void {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(frame));
  }
}
