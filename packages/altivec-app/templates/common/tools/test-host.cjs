#!/usr/bin/env node
// Portable tests never install a package, access a service, or claim native UI coverage.
const fs = require("node:fs"),
  path = require("node:path"),
  os = require("node:os");
const { spawnSync, spawn } = require("node:child_process");
const root = path.resolve(__dirname, "..");
const out = fs.mkdtempSync(path.join(os.tmpdir(), "altivec-host-"));
const cc = process.env.CC || "cc";
const flags = [
  "-std=c99",
  "-D_POSIX_C_SOURCE=200809L",
  "-Wall",
  "-Wextra",
  "-Werror",
  ...(process.env.SANITIZE === "1"
    ? ["-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
    : []),
];
function run(command, args) {
  const r = spawnSync(command, args, {
    cwd: root,
    encoding: "utf8",
    timeout: 60000,
  });
  if (r.error || r.status !== 0)
    throw Error(`${command}: ${r.error || r.stdout + r.stderr}`);
  return r.stdout;
}
function compile(name, sources) {
  run(cc, [
    ...flags,
    "-Isource/shared",
    "-Isource/service",
    ...sources,
    "-o",
    path.join(out, name),
  ]);
}
async function main() {
  compile("model-test", ["tests/model_test.c", "source/shared/model.c"]);
  run(path.join(out, "model-test"), []);
  run(cc, [
    ...flags,
    "-Isource/shared",
    "-c",
    "source/shared/model.c",
    "-o",
    path.join(out, "model.o"),
  ]);
  run("ar", ["rcs", path.join(out, "libmodel.a"), path.join(out, "model.o")]);
  run(cc, [
    ...flags,
    "-Isource/shared",
    "tests/consumer.c",
    path.join(out, "libmodel.a"),
    "-o",
    path.join(out, "consumer"),
  ]);
  run(path.join(out, "consumer"), []);
  if (fs.existsSync(path.join(root, "source/service/daemon.c"))) {
    compile("service", ["source/service/daemon.c"]);
    compile("client", ["source/service/client.c", "source/service/ipc.c"]);
    const socket = path.join(out, "service.sock");
    for (let attempt = 0; attempt < 3; attempt++) {
      const server = spawn(path.join(out, "service"), [socket], {
        stdio: ["ignore", "ignore", "pipe"],
      });
      let log = "";
      server.stderr.on("data", (b) => (log += b));
      const ended = new Promise((resolve) => server.once("exit", resolve));
      try {
        let ready = false;
        for (let i = 0; i < 50; i++) {
          if (server.exitCode !== null) throw Error(`service exited: ${log}`);
          if (fs.existsSync(socket)) {
            ready = true;
            break;
          }
          await new Promise((r) => setTimeout(r, 100));
        }
        if (!ready) throw Error("IPC readiness timeout");
        if (run(path.join(out, "client"), [socket]).trim() !== "PONG")
          throw Error("Invalid IPC response");
      } finally {
        server.kill(attempt === 1 ? "SIGKILL" : "SIGTERM");
        const timer = setTimeout(() => server.kill("SIGKILL"), 4000);
        await ended;
        clearTimeout(timer);
      }
      if (attempt !== 1 && fs.existsSync(socket))
        throw Error("Service left its socket behind");
    }
  }
  console.log(
    "PASS: portable model, external library consumer and applicable IPC/restart tests",
  );
}
main()
  .catch((e) => {
    console.error(e.message);
    process.exitCode = 1;
  })
  .finally(() => fs.rmSync(out, { recursive: true, force: true }));
