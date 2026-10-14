const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs"),
  path = require("node:path"),
  os = require("node:os");
const { spawnSync } = require("node:child_process");
const root = path.resolve(__dirname, ".."),
  cli = path.join(root, "packages/altivec-app/bin/altivec-app.js");
function run(args, options = {}) {
  return spawnSync(process.execPath, [cli, ...args], {
    encoding: "utf8",
    timeout: 60000,
    ...options,
  });
}
function temp(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "altivec-generator-"));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  return dir;
}
function create(dir, template = "cocoa-shared", more = []) {
  return run([
    "new",
    "--template",
    template,
    "--name",
    "Example",
    "--bundle-id",
    "org.example.demo",
    "--destination",
    dir,
    ...more,
  ]);
}
test("help and discovery work outside a checkout without SDK or Git", (t) => {
  const cwd = temp(t);
  for (const args of [
    [],
    ["--help"],
    ["new", "--help"],
    ["--version"],
    ["doctor", "--json"],
  ])
    assert.equal(run(args, { cwd }).status, 0);
  const r = run(["templates", "--json"], { cwd });
  assert.equal(r.status, 0);
  assert.equal(JSON.parse(r.stdout).templates.length, 6);
});
test("dry run and unsupported combinations have no destination effects", (t) => {
  const dir = path.join(temp(t), "new");
  assert.equal(create(dir, "cocoa-shared", ["--dry-run"]).status, 0);
  assert.ok(!fs.existsSync(dir));
  for (const args of [
    ["--platform", "linux"],
    ["--ios-package", "deb-rootless"],
    ["--mac-archs", "riscv"],
    ["--unknown"],
  ])
    assert.notEqual(create(dir, "cocoa-shared", args).status, 0);
  assert.ok(!fs.existsSync(dir));
});
test("refuses existing directories, files, dangling links and unsafe names", (t) => {
  const parent = temp(t);
  for (const type of ["directory", "file", "link"]) {
    const dest = path.join(parent, type);
    if (type === "directory") fs.mkdirSync(dest);
    else if (type === "file") fs.writeFileSync(dest, "untouched");
    else fs.symlinkSync(path.join(parent, "missing"), dest);
    assert.notEqual(create(dest).status, 0);
    assert.ok(fs.lstatSync(dest));
  }
  for (const name of ["Bad-Name", "../Bad", "$(touch x)", "2Bad"])
    assert.notEqual(
      run([
        "new",
        "--template",
        "ios-basic",
        "--name",
        name,
        "--bundle-id",
        "org.test.example",
        "--destination",
        path.join(parent, "new"),
      ]).status,
      0,
    );
  assert.notEqual(create(path.join(parent, "with spaces")).status, 0);
});
for (const template of [
  "ios-basic",
  "mac-basic",
  "cocoa-shared",
  "cocoa-daemon",
  "daemon",
  "cli-library",
])
  test(`${template}: generated metadata, host tests and release configuration`, (t) => {
    const dir = path.join(temp(t), "app");
    const r = create(dir, template);
    assert.equal(r.status, 0, r.stderr);
    const meta = JSON.parse(
      fs.readFileSync(path.join(dir, ".altivec-template.json")),
    );
    assert.equal(meta.template, template);
    let result = spawnSync(process.execPath, ["tools/test-host.cjs"], {
      cwd: dir,
      encoding: "utf8",
      timeout: 60000,
    });
    assert.equal(result.status, 0, result.stderr);
    result = spawnSync(
      process.execPath,
      [
        path.join(root, "packages/altivec-release/bin/altivec-release.js"),
        "check",
        "1.0.0",
      ],
      { cwd: dir, encoding: "utf8" },
    );
    assert.equal(result.status, 0, result.stderr);
    const before = fs.readFileSync(path.join(dir, "Makefile"));
    assert.notEqual(create(dir, template).status, 0);
    assert.deepEqual(fs.readFileSync(path.join(dir, "Makefile")), before);
  });
test("rootless service selects arm64 without changing GUI-only sandbox policy", (t) => {
  const dir = path.join(temp(t), "app");
  assert.equal(
    create(dir, "cocoa-daemon", ["--ios-package", "deb-rootless"]).status,
    0,
  );
  const make = fs.readFileSync(path.join(dir, "source/iOS/Makefile"), "utf8");
  assert.match(make, /ARCHS \?= arm64/);
  assert.match(make, /PACKAGE_ARCH = iphoneos-arm64/);
  assert.match(make, /SANDBOX = unsandboxed/);
});
test("detects corrupted artwork and leaves source unchanged on failed validation", (t) => {
  const dir = path.join(temp(t), "app");
  assert.equal(create(dir).status, 0);
  const icon = path.join(dir, "source/macOS/Resources/AppIcon.icns");
  fs.writeFileSync(icon, "broken");
  assert.throws(() =>
    require("../packages/altivec-app/lib/assets.cjs").validate(dir),
  );
});
test("package contents include offline templates and executable entry point", (t) => {
  const dir = temp(t),
    pkg = path.join(root, "packages/altivec-app");
  const packed = spawnSync(
    "npm",
    [
      "pack",
      "--offline",
      "--ignore-scripts",
      "--json",
      "--pack-destination",
      dir,
    ],
    { cwd: pkg, encoding: "utf8", timeout: 60000 },
  );
  assert.equal(packed.status, 0, packed.stderr);
  const files = Object.values(JSON.parse(packed.stdout))[0].files.map(
    (f) => f.path,
  );
  for (const f of [
    "bin/altivec-app.js",
    "templates/catalog.json",
    "templates/ios-device/template.conf",
    "templates/ios-device/source/iOS/Resources/Default.png",
    "lib/native.cjs",
  ])
    assert.ok(files.includes(f), f);
  assert.ok(!files.some((f) => f.includes("node_modules")));
});
test("packaged Compose source and device manifest stay in sync", () => {
  assert.deepEqual(
    fs.readFileSync(path.join(root, "templates/compose.yml")),
    fs.readFileSync(
      path.join(root, "packages/altivec-app/templates/compose.yml"),
    ),
  );
  const conf = fs.readFileSync(
    path.join(root, "packages/altivec-app/templates/ios-device/template.conf"),
    "utf8",
  );
  assert.match(conf, /template_version=1.0.0/);
  assert.match(
    fs.readFileSync(path.join(root, "toolchain/iOS/armv7/Makefile"), "utf8"),
    /packages\/altivec-app\/templates\/ios-device/,
  );
});

test("installed npm package generates independently of the checkout", (t) => {
  const dir = temp(t),
    prefix = path.join(dir, "install");
  const packed = spawnSync(
    "npm",
    [
      "pack",
      "--offline",
      "--ignore-scripts",
      "--json",
      "--pack-destination",
      dir,
    ],
    { cwd: path.join(root, "packages/altivec-app"), encoding: "utf8" },
  );
  assert.equal(packed.status, 0, packed.stderr);
  const archive = Object.values(JSON.parse(packed.stdout))[0].filename;
  const installed = spawnSync(
    "npm",
    [
      "install",
      "--global",
      "--prefix",
      prefix,
      "--offline",
      "--ignore-scripts",
      "--no-audit",
      "--no-fund",
      path.join(dir, archive),
    ],
    { encoding: "utf8" },
  );
  assert.equal(installed.status, 0, installed.stderr);
  const result = spawnSync(
    path.join(prefix, "bin/altivec-app"),
    [
      "new",
      "--template",
      "ios-basic",
      "--name",
      "Installed",
      "--bundle-id",
      "org.example.installed",
      "--destination",
      path.join(dir, "project"),
    ],
    { cwd: dir, encoding: "utf8" },
  );
  assert.equal(result.status, 0, result.stderr);
  assert.ok(
    fs.existsSync(path.join(dir, "project/source/iOS/Resources/Default.png")),
  );
});

test("dry-run lists the exact generated files, including artwork", (t) => {
  const dir = path.join(temp(t), "project");
  const preview = create(dir, "cocoa-shared", ["--dry-run"]);
  assert.equal(preview.status, 0, preview.stderr);
  const result = create(dir);
  assert.equal(result.status, 0, result.stderr);
  const actual = fs
    .readdirSync(dir, { recursive: true, withFileTypes: true })
    .filter((e) => e.isFile())
    .map((e) => path.relative(dir, path.join(e.parentPath, e.name)))
    .sort();
  assert.deepEqual(JSON.parse(preview.stdout).files, actual);
});

test("generated release preparation updates the plain version and both plists", (t) => {
  const dir = path.join(temp(t), "project");
  assert.equal(create(dir).status, 0);
  const release = path.join(
    root,
    "packages/altivec-release/bin/altivec-release.js",
  );
  let result = spawnSync(process.execPath, [release, "prepare", "patch"], {
    cwd: dir,
    encoding: "utf8",
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(
    fs.readFileSync(path.join(dir, "VERSION"), "utf8").trim(),
    "1.0.1",
  );
  result = spawnSync(process.execPath, [release, "check", "1.0.1"], {
    cwd: dir,
    encoding: "utf8",
  });
  assert.equal(result.status, 0, result.stderr);
});

test("white artwork covers legacy launch sizes and ENIL's ICNS representations", (t) => {
  const dir = path.join(temp(t), "app");
  assert.equal(create(dir).status, 0);
  const assets = require("../packages/altivec-app/lib/assets.cjs");
  for (const name of Object.keys(assets.launches)) {
    const bytes = fs.readFileSync(path.join(dir, "source/iOS/Resources", name));
    const chunks = [];
    for (let i = 8; i < bytes.length;) {
      const n = bytes.readUInt32BE(i);
      if (bytes.toString("ascii", i + 4, i + 8) === "IDAT")
        chunks.push(bytes.subarray(i + 8, i + 8 + n));
      i += n + 12;
    }
    const raw = require("node:zlib").inflateSync(Buffer.concat(chunks));
    const stride = assets.launches[name][0] * 4 + 1;
    assert.ok(raw.every((v, i) => v === (i % stride ? 255 : 0)), name);
    for (const relative of [
      "packages/altivec-app/templates/ios-device/source/iOS/Resources",
      "apps/SingleScreen/Resources", "apps/CURLphone/Resources",
    ]) assert.deepEqual(fs.readFileSync(path.join(root, relative, name)), bytes);
  }
  const icon = fs.readFileSync(path.join(dir, "source/macOS/Resources/AppIcon.icns"));
  const types = [];
  for (let i = 8; i < icon.length;) {
    const type = icon.toString("ascii", i, i + 4), n = icon.readUInt32BE(i + 4);
    types.push(type);
    if (["ic08", "ic09", "ic10"].includes(type)) {
      const payload = icon.subarray(i + 8, i + n);
      assert.equal(payload.subarray(0, 12).toString("hex"), "0000000c6a5020200d0a870a");
      const header = payload.indexOf(Buffer.from("ihdr"));
      const size = { ic08: 256, ic09: 512, ic10: 1024 }[type];
      assert.equal(payload.readUInt32BE(header + 4), size);
      assert.equal(payload.readUInt32BE(header + 8), size);
    }
    i += n;
  }
  assert.deepEqual(types, ["is32", "s8mk", "il32", "l8mk", "ih32", "h8mk",
    "it32", "t8mk", "ic08", "ic09", "ic10"]);
  // A plausible but wrong point size must fail, even when all PNGs exist.
  const plist = path.join(dir, "source/iOS/Info.plist");
  fs.writeFileSync(plist, fs.readFileSync(plist, "utf8").replace("{375, 667}", "{750, 1334}"));
  assert.throws(() => require("../packages/altivec-app/lib/check-project.cjs").check(dir), /Launch image/);
});

test("sample iPhone plists declare the canonical launch profile", () => {
  const result = spawnSync("python3", ["-c", `
import pathlib, plistlib
root=pathlib.Path(${JSON.stringify(root)})
reference=plistlib.loads((root/'packages/altivec-app/templates/ios-device/source/iOS/Info.plist').read_bytes())
for app in ['SingleScreen', 'CURLphone']:
 p=plistlib.loads((root/'apps'/app/'Resources/Info.plist').read_bytes())
 for key in ['UILaunchImageFile','UILaunchImages','UIDeviceFamily','UISupportedInterfaceOrientations']:
  assert p[key]==reference[key], (app,key)
`], { encoding: "utf8" });
  assert.equal(result.status, 0, result.stderr);
});
