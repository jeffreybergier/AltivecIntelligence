#!/usr/bin/env node
// Editable project-owned SSH recipe. Installation requires NATIVE_MODE=installed.
const fs = require("node:fs"),
  path = require("node:path");
const { spawnSync } = require("node:child_process");
function main() {
  const root = path.resolve(__dirname, ".."),
    meta = JSON.parse(
      fs.readFileSync(path.join(root, ".altivec-template.json")),
    );
  const host = process.env.NATIVE_HOST,
    stage = process.env.NATIVE_STAGE,
    platform = process.env.NATIVE_PLATFORM;
  if (!host || !stage || !["macOS", "iOS"].includes(platform))
    throw Error(
      "Set NATIVE_HOST, NATIVE_STAGE and NATIVE_PLATFORM=macOS|iOS explicitly",
    );
  if (
    !/^[A-Za-z0-9_][A-Za-z0-9_.@-]*$/.test(host) ||
    !/^\/[A-Za-z0-9_./-]+$/.test(stage) ||
    stage.split("/").includes("..")
  )
    throw Error("Unsafe host or stage");
  if (
    !(
      platform === "macOS"
        ? /^\/Users\/[^/]+\/Desktop\/.+/
        : /^\/(?:var\/mobile|var\/root|private\/var\/mobile|private\/var\/root)\/tmp_altivec\/.+/
    ).test(stage)
  )
    throw Error(
      "Stage must be below ~/Desktop on Mac or ~/tmp_altivec on iPhone",
    );
  const out = path.join(root, "build/tests/native");
  fs.mkdirSync(out, { recursive: true });
  let log = "";
  function run(cmd, args) {
    const r = spawnSync(cmd, args, { encoding: "utf8", timeout: 45000 });
    log += `$ ${cmd}\n${r.stdout || ""}${r.stderr || ""}`;
    fs.writeFileSync(path.join(out, "smoke.log"), log);
    if (r.error || r.status !== 0)
      throw Error(`${cmd} failed: ${r.error || r.stdout + r.stderr}`);
    return r.stdout;
  }
  const ssh = ["-oBatchMode=yes", "-oConnectTimeout=10", host];
  const name = meta.name,
    service = meta.template.includes("daemon");
  const mode = process.env.NATIVE_MODE || "executable";
  if (!["executable", "ui", "installed"].includes(mode))
    throw Error("Unknown NATIVE_MODE");
  if (
    !/^[A-Za-z][A-Za-z0-9_]*$/.test(name) ||
    !/^[A-Za-z0-9.-]+$/.test(meta.bundle_id)
  )
    throw Error("Unsafe project identity");
  if (mode === "installed") {
    if (platform !== "iOS" || !service || meta.ios_package !== "deb-rootful")
      throw Error(
        "Installed lifecycle recipe supports rootful iOS services only",
      );
    const product = meta.template === "daemon" ? name + "Service" : name;
    const archive = path.join(
      root,
      `build/iOS/release/${product}/${product}-rootful.deb`,
    );
    if (!fs.existsSync(archive)) throw Error("Build the rootful package first");
    run("ssh", [...ssh, `umask 077; mkdir '${stage}'`]);
    try {
      run("scp", ["-oBatchMode=yes", archive, `${host}:${stage}/project.deb`]);
      run("scp", [
        "-oBatchMode=yes",
        path.join(root, "tools/test-installed.sh"),
        `${host}:${stage}/test-installed.sh`,
      ]);
      run("ssh", [
        ...ssh,
        `cd '${stage}' && sh ./test-installed.sh '${name}' '${meta.bundle_id}' '${stage}/project.deb' '${stage}'`,
      ]);
    } finally {
      run("ssh", [
        ...ssh,
        `rm -f '${stage}/project.deb' '${stage}/test-installed.sh'; rmdir '${stage}'`,
      ]);
    }
    console.log(
      "PASS: installed rootful lifecycle; logs in build/tests/native/smoke.log",
    );
    return;
  }
  if (mode === "ui") {
    if (
      platform !== "macOS" ||
      ["daemon", "cli-library"].includes(meta.template)
    )
      throw Error(
        "UI recipe supports Mac app templates; iOS launch/rendering requires the documented device UI checks",
      );
    const app = path.join(root, `build/macOS/release/${name}/${name}.app`);
    if (!fs.existsSync(app)) throw Error("Build the Mac app first");
    const existing = run("ssh", [
      ...ssh,
      `osascript -e 'tell application "System Events" to exists process "${name}"'`,
    ]);
    if (existing.trim() === "true")
      throw Error("Close the existing app before the isolated UI test");
    const script = `tell application "System Events"\n tell process "${name}"\n set frontmost to true\n if (count of windows) is not 1 then error "Expected one window"\n click button 1 of window 1\n end tell\nend tell`;
    run("ssh", [...ssh, `umask 077; mkdir '${stage}'`]);
    try {
      run("scp", ["-r", "-oBatchMode=yes", app, `${host}:${stage}/`]);
      run("ssh", [
        ...ssh,
        `set -e; open '${stage}/${name}.app'; sleep 2; osascript -e '${script}'; open '${stage}/${name}.app'; sleep 2; osascript -e 'tell application "System Events" to tell process "${name}" to if (count of windows) is not 1 then error "Window did not reopen"'; screencapture -x '${stage}/screen.png'`,
      ]);
      run("scp", [
        "-oBatchMode=yes",
        `${host}:${stage}/screen.png`,
        path.join(out, "screen.png"),
      ]);
    } finally {
      run("ssh", [
        ...ssh,
        `osascript -e 'tell application "${name}" to quit'; rm -rf '${stage}/${name}.app'; rm -f '${stage}/screen.png'; rmdir '${stage}'`,
      ]);
    }
    console.log(
      "PASS: Mac window launch/close/reopen; inspect build/tests/native/screen.png for rendering",
    );
    return;
  }

  if (!service && meta.template !== "cli-library")
    throw Error(
      "This template requires GUI smoke checks; follow README and the deployment guide. No UI claim is made by this executable recipe.",
    );
  const binaries = service ? [name + "Service", name + "Client"] : [name];
  for (const binary of binaries) {
    if (
      !fs.existsSync(
        path.join(
          root,
          `build/${platform}/release/${binary}/Intermediates/signed/${binary}`,
        ),
      )
    )
      throw Error("Build release products first (including the test client)");
  }
  run("ssh", [...ssh, `umask 077; mkdir '${stage}'`]);
  try {
    for (const binary of binaries)
      run("scp", [
        "-oBatchMode=yes",
        "-oConnectTimeout=10",
        path.join(
          root,
          `build/${platform}/release/${binary}/Intermediates/signed/${binary}`,
        ),
        `${host}:${stage}/${binary}`,
      ]);
    const command = service
      ? `cd '${stage}' && chmod +x '${name}Service' '${name}Client' && (./'${name}Service' '${stage}/ipc.sock' >service.log 2>&1 & pid=$!; trap 'kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true' EXIT HUP INT TERM; n=0; until [ -S '${stage}/ipc.sock' ]; do n=$((n+1)); [ "$n" -lt 30 ] || exit 1; sleep 1; done; ./'${name}Client' '${stage}/ipc.sock')`
      : `cd '${stage}' && chmod +x '${name}' && ./'${name}'`;
    for (let i = 0; i < (service ? 2 : 1); i++) run("ssh", [...ssh, command]);
  } finally {
    if (service) {
      try {
        run("scp", [
          "-oBatchMode=yes",
          `${host}:${stage}/service.log`,
          path.join(out, "service.log"),
        ]);
      } catch (error) {
        console.error("Could not collect service log: " + error.message);
      }
    }
    run("ssh", [
      ...ssh,
      `rm -f ${binaries.map((b) => `'${stage}/${b}'`).join(" ")} '${stage}/service.log'; rmdir '${stage}'`,
    ]);
  }
  console.log(
    `PASS: ${platform} native executable${service ? " IPC and restart" : ""}; no UI or installed lifecycle claim`,
  );
}
try {
  main();
} catch (e) {
  console.error(e.message);
  process.exitCode = 1;
}
