/// <reference types="vitest/config" />
import { defineConfig, loadEnv, type Connect } from "vite";
import vue from "@vitejs/plugin-vue";
import tailwindcss from "@tailwindcss/vite";
import net from "node:net";
import path from "node:path";
import authHandler from "./api/auth";

net.setDefaultAutoSelectFamilyAttemptTimeout(2000);

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), "VITE_");
  const mountAuthBff = (middlewares: Connect.Server) => {
    process.env.VITE_SUPABASE_URL ??= env.VITE_SUPABASE_URL;
    middlewares.use("/api/auth", (req, res) => {
      authHandler(req, res).catch((err) => {
        console.error(err);
        res.statusCode = 502;
        res.end();
      });
    });
  };
  return {
    server: {
      host: "::",
      port: 8080,
      proxy: {
        "/supabase-api": {
          target: env.VITE_SUPABASE_URL,
          changeOrigin: true,
          rewrite: (p) => p.replace(/^\/supabase-api/, ""),
        },
      },
    },
    plugins: [
      vue(),
      tailwindcss(),
      {
        name: "auth-bff",
        configureServer: (server) => mountAuthBff(server.middlewares),
        configurePreviewServer: (server) => mountAuthBff(server.middlewares),
      },
    ],
    resolve: {
      alias: {
        "@": path.resolve(__dirname, "./src"),
        "@shared": path.resolve(__dirname, "./supabase/functions/_shared"),
      },
    },
    test: {
      environment: "node",
      include: ["src/**/__tests__/**/*.test.ts"],
      setupFiles: ["./src/test-setup.ts"],
    },
    build: {
      outDir: "dist",
      rollupOptions: {
        output: {
          manualChunks(id) {
            if (!id.includes("node_modules")) return;
            if (id.includes("@supabase")) return "supabase";
            if (id.includes("reka-ui")) return "reka";
            if (id.includes("vue-i18n") || id.includes("@intlify")) return "i18n";
            if (/\/(vue|@vue|vue-router|pinia)\//.test(id)) return "vue";
          },
        },
      },
    },
  };
});
