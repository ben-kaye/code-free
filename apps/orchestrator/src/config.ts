import { parseArgs } from "node:util";

export type OrchConfig = {
  dataRoot: string;
  bindHost: string;
  bindPort: number;
  tokenFile: string;
  logDir: string;
};

export function parseConfig(argv: string[] = process.argv.slice(2)): OrchConfig {
  const { values } = parseArgs({
    args: argv,
    options: {
      "data-root": { type: "string" },
      bind: { type: "string", default: "127.0.0.1:0" },
      "token-file": { type: "string" },
      "log-dir": { type: "string" },
      help: { type: "boolean", short: "h", default: false },
    },
    allowPositionals: false,
  });

  if (values.help) {
    printHelp();
    process.exit(0);
  }

  if (!values["data-root"]) {
    throw new ConfigError("Missing required --data-root");
  }
  if (!values["token-file"]) {
    throw new ConfigError("Missing required --token-file");
  }
  if (!values["log-dir"]) {
    throw new ConfigError("Missing required --log-dir");
  }

  const bind = values.bind ?? "127.0.0.1:0";
  const { host, port } = parseBind(bind);

  if (!isLoopback(host)) {
    throw new ConfigError(
      `Bind host must be loopback in v0 (got ${host}). Refusing non-loopback bind.`,
    );
  }

  return {
    dataRoot: values["data-root"],
    bindHost: host,
    bindPort: port,
    tokenFile: values["token-file"],
    logDir: values["log-dir"],
  };
}

function parseBind(bind: string): { host: string; port: number } {
  // host:port — host may be IPv4 only in v0
  const lastColon = bind.lastIndexOf(":");
  if (lastColon <= 0) {
    throw new ConfigError(`Invalid --bind (expected host:port): ${bind}`);
  }
  const host = bind.slice(0, lastColon);
  const portStr = bind.slice(lastColon + 1);
  const port = Number(portStr);
  if (!Number.isInteger(port) || port < 0 || port > 65535) {
    throw new ConfigError(`Invalid port in --bind: ${bind}`);
  }
  return { host, port };
}

function isLoopback(host: string): boolean {
  return host === "127.0.0.1" || host === "localhost" || host === "::1";
}

export class ConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ConfigError";
  }
}

function printHelp(): void {
  console.log(`code-free-orch — Code Free orchestrator

Usage:
  code-free-orch --data-root <path> --token-file <path> --log-dir <path> [--bind 127.0.0.1:0]

Options:
  --data-root   Durable data directory (SQLite, artifacts)
  --token-file  Path to write/read WS auth token (mode 0600)
  --log-dir     Structured log directory
  --bind        Loopback host:port (default 127.0.0.1:0)
  -h, --help    Show help
`);
}
