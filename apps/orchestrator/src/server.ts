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
} from "@code-free/protocol";
import { EventStore } from "@code-free/store";
import type { OrchConfig } from "./config.js";
import { Logger } from "./logger.js";
import { SessionManager, SessionError } from "./sessions.js";
import { ensureTokenFile, tokensEqual } from "./token.js";

type ClientState = {
  authed: boolean;
  /** sessionId → true */
  subscriptions: Set<string>;
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
): Promise<RunningOrch> {
  const token = ensureTokenFile(config.tokenFile);
  const store = new EventStore({ dataRoot: config.dataRoot });
  const sessions = new SessionManager(store);

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
      const result = dispatch(cmd, st, socket);
      socket.send(JSON.stringify(result));
    }

    function dispatch(cmd: ClientCommand, st: ClientState, socket: WebSocket): CommandResult {
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
            // if creator already subscribed somehow, still fine
            return ok(cmd.requestId, { session, event: started });
          }
          case "session.list": {
            return ok(cmd.requestId, { sessions: sessions.list() });
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
            const events = sessions.sendUserMessage(cmd.sessionId, cmd.text);
            for (const ev of events) broadcast(cmd.sessionId, ev);
            return ok(cmd.requestId, { events });
          }
          case "session.cancel": {
            const ended = sessions.cancel(cmd.sessionId);
            broadcast(cmd.sessionId, ended);
            return ok(cmd.requestId, { event: ended });
          }
          case "session.rename": {
            const session = sessions.rename(cmd.sessionId, cmd.title);
            return ok(cmd.requestId, { session });
          }
          case "harness.list": {
            // Phase 1: empty list — honest caps
            return ok(cmd.requestId, { harnesses: [] });
          }
          case "models.list": {
            return ok(cmd.requestId, { models: [] });
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
            return fail(
              cmd.requestId,
              "not_implemented",
              "Approvals require an adapter (Phase 2+)",
            );
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
