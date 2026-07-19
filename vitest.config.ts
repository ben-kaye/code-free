import { defineConfig } from "vitest/config";
import { resolve } from "node:path";

export default defineConfig({
  resolve: {
    alias: {
      "@code-free/protocol": resolve(__dirname, "packages/protocol/src/index.ts"),
      "@code-free/store": resolve(__dirname, "packages/store/src/index.ts"),
    },
  },
  test: {
    include: ["**/src/**/*.test.ts", "**/tests/**/*.test.ts"],
    testTimeout: 20_000,
  },
});
