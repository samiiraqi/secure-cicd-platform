const test = require("node:test");
const assert = require("node:assert");
const http = require("node:http");
const { execPath } = require("node:process");
const { spawn } = require("node:child_process");
const path = require("node:path");

function waitForServer(port, attempts = 20) {
  return new Promise((resolve, reject) => {
    const tryOnce = (remaining) => {
      http
        .get(`http://127.0.0.1:${port}/health`, (res) => {
          resolve(res.statusCode);
        })
        .on("error", () => {
          if (remaining <= 0) return reject(new Error("server did not start"));
          setTimeout(() => tryOnce(remaining - 1), 250);
        });
    };
    tryOnce(attempts);
  });
}

test("GET /health returns 200", async () => {
  const port = 8099;
  const server = spawn(execPath, [path.join(__dirname, "..", "src", "server.js")], {
    env: { ...process.env, PORT: String(port) },
  });

  try {
    const statusCode = await waitForServer(port);
    assert.strictEqual(statusCode, 200);
  } finally {
    server.kill();
  }
});
