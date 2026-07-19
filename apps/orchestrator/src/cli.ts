#!/usr/bin/env node
import { ConfigError, parseConfig } from "./config.js";
import { Logger } from "./logger.js";
import { startOrchestrator } from "./server.js";

async function main(): Promise<void> {
  let config;
  try {
    config = parseConfig();
  } catch (err) {
    if (err instanceof ConfigError) {
      console.error(err.message);
      process.exit(2);
    }
    throw err;
  }

  const log = new Logger(config.logDir);
  const orch = await startOrchestrator(config, log);

  const shutdown = async (signal: string) => {
    log.info("shutdown", { signal });
    try {
      await orch.close();
      process.exit(0);
    } catch (err) {
      log.error("shutdown failed", {
        err: err instanceof Error ? err.message : String(err),
      });
      process.exit(1);
    }
  };

  process.on("SIGTERM", () => void shutdown("SIGTERM"));
  process.on("SIGINT", () => void shutdown("SIGINT"));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
