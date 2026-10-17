const fs = require("node:fs"),
  path = require("node:path"),
  crypto = require("node:crypto");
const assets = require("./assets.cjs");
const templates = path.join(__dirname, "../templates");
const catalog = require("../templates/catalog.json");
const deviceContract = Object.fromEntries(
  fs
    .readFileSync(path.join(templates, "ios-device/template.conf"), "utf8")
    .trim()
    .split("\n")
    .map((line) => line.split("=")),
);
if (
  deviceContract.template_version !== catalog.template_version ||
  deviceContract.schema_version !== String(catalog.schema_version)
)
  throw Error("Device/container template contract versions differ");
const xml = (value) =>
  String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
function plist(values) {
  function encode(v) {
    if (typeof v === "boolean") return `<${v ? "true" : "false"}/>`;
    if (typeof v === "number") return `<integer>${v}</integer>`;
    if (Array.isArray(v)) return `<array>${v.map(encode).join("")}</array>`;
    if (typeof v === "object")
      return `<dict>${Object.entries(v)
        .map(([k, val]) => `<key>${xml(k)}</key>${encode(val)}`)
        .join("")}</dict>`;
    return `<string>${xml(v)}</string>`;
  }
  return `<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">${encode(values)}</plist>\n`;
}
function options(o) {
  const t = catalog.templates.find((t) => t.id === o.template);
  if (!t)
    throw Error("Choose a supported --template (see altivec-app templates)");
  if (!/^[A-Za-z][A-Za-z0-9_]*$/.test(o.name || ""))
    throw Error(
      "name must start with a letter and contain only letters, digits or underscores",
    );
  if (
    !/^[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*(?:\.[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*)+$/.test(
      o["bundle-id"] || "",
    )
  )
    throw Error("bundle-id must be a dot-separated identifier");
  const platforms = o.platform ? o.platform.split(",") : t.platforms;
  if (
    !platforms.length ||
    new Set(platforms).size !== platforms.length ||
    platforms.some((p) => !t.platforms.includes(p))
  )
    throw Error(`Supported platforms: ${t.platforms.join(",")}`);
  const arch = o["mac-archs"] || "full";
  if (!["full", "legacy", "arm64", "x86_64"].includes(arch))
    throw Error("mac-archs must be full, legacy, arm64 or x86_64");
  const pkg = o["ios-package"] || t.packages.iOS[0];
  if (!t.packages.iOS.includes(pkg))
    throw Error(`Supported iOS packages: ${t.packages.iOS.join(",")}`);
  const destination = path.resolve(o.destination || o.name);
  if (/\s/.test(destination))
    throw Error(
      "Destination paths with whitespace are not supported by the Make backend",
    );
  if (
    destination === path.parse(destination).root ||
    destination === process.cwd() ||
    destination.startsWith(templates + path.sep)
  )
    throw Error("Unsafe destination");
  if (
    fs.existsSync(destination) ||
    (() => {
      try {
        fs.lstatSync(destination);
        return true;
      } catch (e) {
        if (e.code !== "ENOENT") throw e;
        return false;
      }
    })()
  )
    throw Error(`Destination already exists: ${destination}`);
  return {
    t,
    name: o.name,
    id: o["bundle-id"],
    platforms,
    arch,
    pkg,
    destination,
  };
}
function buildFiles(o) {
  const { t, name, id, platforms, arch, pkg } = o,
    files = new Map();
  function put(file, data) {
    files.set(file, Buffer.isBuffer(data) ? data : Buffer.from(data));
  }
  function overlay(dir, filter = () => true) {
    for (const entry of fs.readdirSync(path.join(templates, dir), {
      recursive: true,
      withFileTypes: true,
    })) {
      if (!entry.isFile()) continue;
      const full = path.join(entry.parentPath, entry.name),
        rel = path.relative(path.join(templates, dir), full);
      if (filter(rel)) put(rel, fs.readFileSync(full));
    }
  }
  overlay("common");
  put("LICENSE", fs.readFileSync(path.join(__dirname, "../LICENSE")));
  put("compose.yml", fs.readFileSync(path.join(templates, "compose.yml")));
  const service = t.id.includes("daemon"),
    gui = t.id !== "daemon" && t.id !== "cli-library";
  if (gui) {
    overlay("cocoa");
    if (platforms.includes("macOS")) overlay("mac");
    if (platforms.includes("iOS"))
      overlay(
        "ios-device",
        (f) =>
          f.startsWith("source/iOS/") &&
          !f.endsWith("Makefile") &&
          !f.endsWith("Info.plist") &&
          !f.includes("/Resources/"),
      );
  }
  if (service) overlay("service");
  if (t.id === "cli-library") overlay("cli");
  put("tools/assets.cjs", fs.readFileSync(path.join(__dirname, "assets.cjs")));
  put(
    "tools/check-project.cjs",
    fs.readFileSync(path.join(__dirname, "check-project.cjs")),
  );
  put(
    "tools/test-native.cjs",
    fs.readFileSync(path.join(__dirname, "native.cjs")),
  );
  const prefix =
    "ALTIVEC_ROOT ?= /altivec\ninclude $(ALTIVEC_ROOT)/make/entry.mk\nifeq ($(_altivec_relocated),)\n";
  put(
    "Makefile",
    prefix +
      `PROJECT_ROOT := $(abspath $(dir $(firstword $(MAKEFILE_LIST))))\nPLATFORMS = ${platforms.join(" ")}\n${platforms.map((p) => `PROJECT_${p}_DIR = source/${p}`).join("\n")}\nTEST_HOST_COMMAND = node $(PROJECT_ROOT)/tools/test-host.cjs\nTEST_NATIVE_COMMAND = node $(PROJECT_ROOT)/tools/test-native.cjs\ninclude $(ALTIVEC_ROOT)/make/projects.mk\n.PHONY: check-project\ncheck-project:\n\tnode tools/check-project.cjs\nendif\n`,
  );
  const releaseTargets = [],
    plists = [];
  for (const platform of platforms) {
    const ios = platform === "iOS",
      mac = platform === "macOS",
      base = `source/${platform}`,
      suffix = mac ? "mac" : ios ? "phone" : "host";
    let decl =
      prefix +
      `PROJECT_ROOT := $(abspath $(dir $(firstword $(MAKEFILE_LIST)))/../..)\n`;
    if (mac)
      decl += `ARCHS ?= ${arch === "legacy" ? "ppc i386" : arch === "full" ? "ppc i386 x86_64 arm64" : arch}\n`;
    const primary = gui ? name : service ? `${name}Service` : name;
    const products = gui
      ? [name, "model"]
      : service
        ? [`${name}Service`, `${name}Client`]
        : [name, "model"];
    if (gui && service) products.push(`${name}Service`, `${name}Client`);
    decl += `PRODUCTS = ${products.join(" ")}\nPACKAGE_PRODUCTS = ${primary}${t.id === "cli-library" ? " model" : ""}\n`;
    if (gui || !service)
      decl += "model_TYPE = static\nmodel_SOURCES = ../shared/model.c\n";
    if (gui) {
      decl += `${name}_TYPE = app\n${name}_DEPS = model\n${name}_PLIST = Info.plist\n${name}_RESOURCES = $(wildcard Resources/*) ../../LICENSE\n${name}_LOCALIZATIONS = ../shared/Resources\n${name}_SOURCES = ../shared/XPFoundation.m${service ? " ../service/ipc.c" : ""}\n${name}_FLAGS = -I../shared -I../service\n`;
      if (ios) {
        decl += `${name}_GROUPS = ui\nGROUP_ui_SOURCES = main.m AppDelegate.m UI/MainViewController.m\nGROUP_ui_MEMORY = arc\n${name}_LDFLAGS = -framework UIKit -framework Foundation -framework CoreGraphics\n${name}_ENTITLEMENTS = AppEntitlements.plist\n${name}_SANDBOX = ${service ? "unsandboxed" : "container"}\n`;
        put(
          `${base}/AppEntitlements.plist`,
          plist({
            "application-identifier": id,
            ...(service
              ? {
                  "platform-application": true,
                  "com.apple.private.security.no-container": true,
                  "com.apple.private.security.no-sandbox": true,
                }
              : {}),
          }),
        );
        let info = fs
          .readFileSync(
            path.join(templates, "ios-device/source/iOS/Info.plist"),
            "utf8",
          )
          .replace(/PUBLIC ("[^"]+")\s+("[^"]+")/, "PUBLIC $1 $2")
          .replace("<string>1.0</string>", "<string>1.0.0</string>")
          .replace("<string>1</string>", "<string>1.0.0</string>");
        put(`${base}/Info.plist`, info);
        put(
          `${base}/UI/XPUIKit.h`,
          "#import <UIKit/UIKit.h>\n#define XPTextAlignmentCenter ((NSInteger)1)\n",
        );
        let view = files
          .get(`${base}/UI/MainViewController.m`)
          .toString()
          .replace(
            "#define XPTextAlignmentCenter ((NSInteger)1)",
            '#import "XPUIKit.h"\n#import "../../shared/XPFoundation.h"',
          )
          .replace('NSLocalizedString(@"Welcome", nil)', "[XPModel welcome]")
          .replace("- (void)viewDidLoad {", "- (void)viewDidLoad;\n{");
        put(`${base}/UI/MainViewController.m`, view);
        let delegate = files
          .get(`${base}/AppDelegate.m`)
          .toString()
          .replace(
            "didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {",
            "didFinishLaunchingWithOptions:(NSDictionary *)launchOptions;\n{",
          );
        put(`${base}/AppDelegate.m`, delegate);
      } else {
        decl += `${name}_SOURCES += main.m\n${name}_LDFLAGS = -framework AppKit -framework Foundation -lobjc\n`;
        put(
          `${base}/Info.plist`,
          plist({
            CFBundleExecutable: name,
            CFBundleIdentifier: id,
            CFBundleName: name,
            CFBundlePackageType: "APPL",
            CFBundleShortVersionString: "1.0.0",
            CFBundleVersion: "1.0.0",
            CFBundleIconFile: "AppIcon.icns",
            LSMinimumSystemVersion:
              arch === "arm64" ? "11.0" : arch === "x86_64" ? "10.9" : "10.4",
            NSHighResolutionCapable: true,
          }),
        );
      }
      plists.push(`${base}/Info.plist`);
    } else if (!service) {
      decl += `${name}_TYPE = executable\n${name}_SOURCES = ../cli/main.c\n${name}_FLAGS = -I../shared\n${name}_DEPS = model\n${name}_PACKAGE_MAIN_PATH = bin/${name}\nmodel_PACKAGE_MAIN_PATH = lib/libmodel.a\nmodel_PACKAGE_RESOURCES = ../shared/model.h=include/model.h ../../LICENSE=LICENSE\n${name}_PACKAGE_RESOURCES = ../../LICENSE=LICENSE\n`;
      if (ios) decl += `${name}_SIGN = 1\n`;
    }
    if (service) {
      decl += `${name}Service_TYPE = daemon\n${name}Service_SOURCES = ../service/daemon.c\n${name}Client_TYPE = executable\n${name}Client_SOURCES = ../service/client.c ../service/ipc.c\n`;
      if (ios) {
        put(
          `${base}/ServiceEntitlements.plist`,
          plist({
            "platform-application": true,
            "com.apple.private.security.no-container": true,
            "com.apple.private.security.no-sandbox": true,
          }),
        );
        decl += `${name}Service_ENTITLEMENTS = ServiceEntitlements.plist\n${name}Client_ENTITLEMENTS = ServiceEntitlements.plist\n${primary}_PACKAGES = ${pkg}\n${primary}_PACKAGE_ID = ${id}\n${primary}_PACKAGE_ARCH = ${pkg === "deb-rootless" ? "iphoneos-arm64" : "iphoneos-arm"}\n${primary}_VERSION = $(shell cat ../../VERSION)\n${primary}_INSTALL = ${gui ? name + "Service " : ""}${name}Client\n${primary}_LAUNCHD = ${id}.plist\n${primary}_PACKAGE_SCRIPTS = postinst prerm\n`;
        if (pkg === "deb-rootless") decl += "ARCHS ?= arm64\nMIN_arm64 = 7.0\n";
        put(
          `${base}/${id}.plist`,
          plist({
            Label: id,
            ProgramArguments: [
              `@PREFIX@/usr/libexec/${name}Service`,
              `/tmp/${id}.sock`,
            ],
            RunAtLoad: true,
            KeepAlive: true,
            UserName: "mobile",
          }),
        );
        put(
          `${base}/postinst`,
          `#!/bin/sh\nset -eu\nif [ "$1" = configure ]; then\n  launchctl unload '@PREFIX@/Library/LaunchDaemons/${id}.plist' 2>/dev/null || true\nif [ -S '/tmp/${id}.sock' ] && [ ! -L '/tmp/${id}.sock' ]; then rm -f '/tmp/${id}.sock'; fi\n  launchctl load '@PREFIX@/Library/LaunchDaemons/${id}.plist'\nfi\n`,
        );
        put(
          `${base}/prerm`,
          `#!/bin/sh\nset -eu\nlaunchctl unload '@PREFIX@/Library/LaunchDaemons/${id}.plist' 2>/dev/null || true\nif [ -S '/tmp/${id}.sock' ] && [ ! -L '/tmp/${id}.sock' ]; then rm -f '/tmp/${id}.sock'; fi\n`,
        );
      } else {
        decl += `${primary}_PACKAGE_RESOURCES = ../../LICENSE=LICENSE ${id}.plist=${id}.plist\n`;
        if (gui) decl += `${name}_EMBED = ${name}Service ${name}Client\n`;
        else
          decl += `${name}Service_PACKAGE_RESOURCES += $(OUTPUT_DIR)/${name}Client/Intermediates/signed/${name}Client=${name}Client\n${name}Service_INPUTS = $(OUTPUT_DIR)/${name}Client/Intermediates/signed/${name}Client\n`;
        put(
          `${base}/${id}.plist`,
          plist({
            Label: id,
            ProgramArguments: [
              `/usr/local/libexec/${name}Service`,
              `/tmp/${id}.sock`,
            ],
            RunAtLoad: true,
            KeepAlive: true,
          }),
        );
      }
    }
    decl += `include $(ALTIVEC_ROOT)/altivec_common_${suffix}.mk\nendif\n`;
    put(`${base}/Makefile`, decl);
    const format = ios ? (service ? pkg : gui ? "ipa" : "zip") : "zip";
    const ext = format.startsWith("deb-")
      ? `-${format.slice(4)}.deb`
      : "." + format;
    const artifacts = [
      {
        path: `build/${platform}/release/${primary}/${primary}${ext}`,
        asset_name: `${name}-{version}-${platform}${ext}`,
      },
    ];
    if (t.id === "cli-library")
      artifacts.push({
        path: `build/${platform}/release/libmodel/model.zip`,
        asset_name: `${name}-{version}-${platform}-library.zip`,
      });
    releaseTargets.push({
      name: platform,
      workdir: ".",
      build: [{ exec: "make", args: [`${platform}-release`] }],
      artifacts,
    });
  }
  if (service && gui)
    put(
      "source/shared/XPFoundation.m",
      `#import "XPFoundation.h"\n#include "../service/ipc.h"\n#include <signal.h>\n@implementation XPModel\n+ (NSString *)welcome;\n{\n  signal(SIGPIPE, SIG_IGN);\n  return ipc_request("/tmp/${id}.sock") == 0 ? @"Service ready (PONG)" : @"Service is not running";\n}\n@end\n`,
    );
  put("VERSION", "1.0.0\n");
  put(".gitignore", "build/\n.*.altivec-locks/\n.altivec-sdk/\n.DS_Store\n");
  put(
    ".altivec-release.json",
    JSON.stringify(
      {
        schema_version: 1,
        app_name: name,
        version: {
          source: "VERSION",
          format: "text",
          ...(plists.length
            ? {
                plists,
                keys: ["CFBundleShortVersionString", "CFBundleVersion"],
              }
            : {}),
        },
        targets: releaseTargets,
      },
      null,
      2,
    ) + "\n",
  );
  put(".altivec-project", crypto.randomUUID() + "\n");
  put(
    ".altivec-template.json",
    JSON.stringify(
      {
        schema_version: 1,
        template_version: catalog.template_version,
        template: t.id,
        name,
        bundle_id: id,
        platforms,
        mac_archs: arch,
        ios_package: pkg,
        backend: "container",
        support_profile: "legacy-phone",
      },
      null,
      2,
    ) + "\n",
  );
  put(
    "AGENTS.md",
    `# ${name}\n\nRead /altivec/templates/AGENTS.md for app-development defaults inside the image;\nthese project-specific instructions take precedence.\nUse root Make targets and declarative products; build mechanics belong in Altivec.\nKeep C logic in source/shared, Objective-C facades narrow, Mac UI MRC and iOS UI ARC.\nPrefix compatibility helpers XP. Use bracket syntax and explicit retain/release in MRC.\nRun make test-host and make check-project first, then selected platform builds,\nanalyze and validate-package. Device tests are explicit and use caller-supplied\nNATIVE_HOST, NATIVE_STAGE and NATIVE_PLATFORM; never infer device validation from a cross-build.\nDo not change application code automatically when updating a template.\n`,
  );
  put(
    "README.md",
    `# ${name}\n\nGenerated by altivec-app ${catalog.template_version} (${t.id}). ${t.description}.\n\n## Develop\n\nStart the checked-in Compose environment (see compose.yml). Inside it:\n\n\`\`\`sh\nmake test-host\nmake check-project\nmake print-config\nmake ${platforms[0]}-release\nmake ${platforms[0]}-analyze\nmake ${platforms[0]}-validate-package\n\`\`\`\n\nGeneration and portable tests need no Apple SDK. Cross-builds need SDK archives;\nCompose searches host ~/.altivec/.altivec-sdk, then project .altivec-sdk,\nthen an optional container-visible ALTIVEC_SDK_ARCHIVE_DIR fallback. Builds are under\nbuild/<platform>/<configuration>. Select ARCHS for a development slice.\nMac defaults: PPC/i386 10.4, x86_64 10.9, arm64 11.0. iOS: armv7 5.0, arm64 7.0.\nThese are compiler floors, not a claim of testing on every OS.\nThe iOS artwork profile is phone-only, portrait; tablet support is not advertised.\n${service ? "Services use a local PING/PONG socket with a 0600 mode and a mobile/user identity.\niOS packages require a jailbreak and root installation; the UI is explicitly unsandboxed.\nRootless changes paths, not privilege policy. Mac launchd plists are editable examples:\ninstall the service at the declared path and load as a user LaunchAgent.\nDEB lifecycle hooks unload/reload the service and never delete application data.\n" : "iOS app templates retain the application container and use IPA packaging.\n"}\n## Tests\n\n\`make test-host\` runs C model boundary tests, an external library consumer, and\napplicable local IPC readiness/restart tests. \`SANITIZE=1 make test-host\` adds\nAddressSanitizer/UBSan. No live-service test runs by default.\n\`make validate-package\` inspects package slices, metadata, resources and signing.\nFor a native executable smoke test, explicitly set NATIVE_HOST, NATIVE_STAGE,\nNATIVE_PLATFORM (macOS/iOS) and run \`make test-native\`. Staging must be inside\n~/Desktop on Mac or ~/tmp_altivec on iPhone. Logs remain in build/tests/native.\nSelect NATIVE_MODE=ui for Mac launch/close/reopen plus a screenshot, or\nNATIVE_MODE=installed for guarded rootful iOS service install/restart/reinstall/removal.\nThe default executable mode never installs packages. iOS UI rendering, sandbox\nbehavior and rootless installed lifecycle still require separate device checks.\nAfter both debug/release builds, run python3 tools/check-artifacts.py for archive\ndeployment floors, dynamic dependencies, resources and public-library symbols.\n\n## Artwork and release\n\nOpaque white placeholder resources are checked in and are not regenerated during builds.\n\`altivec-app assets --project .\` regenerates placeholders; add \`--source icon.png\`\nfor your own icon (requires ImageMagick magick with JPEG 2000 support).\nMac ICNS: 16/32/48/128px RGB with masks, 256/512/1024px JPEG 2000.\nKeep the portrait phone launch PNGs and matching plist point sizes together.\nLegacy ICNS sizes are bounded\nto 300,000 bytes per element and 1,000,000 total. Verify on the oldest target OS.\n\`altivec-release prepare patch\` updates VERSION/plists; build/stage are separate\nfrom explicit host commit and publication. The library package contains its header\nand LICENSE. Template metadata records the original version; upgrades are reviewed\nby generating into a new directory and diffing, never overwriting application code.\n`,
  );
  for (const [file, buffer] of files) {
    if (buffer.includes(Buffer.from("@ALTIVEC_"))) {
      let text = buffer
        .toString()
        .replaceAll("@ALTIVEC_APP_NAME@", name)
        .replaceAll("@ALTIVEC_DISPLAY_NAME@", name)
        .replaceAll("@ALTIVEC_BUNDLE_ID@", id);
      if (/@ALTIVEC_/.test(text))
        throw Error(`Unresolved placeholder: ${file}`);
      put(file, text);
    }
  }
  return files;
}
function generate(raw) {
  const o = options(raw),
    files = buildFiles(o);
  if (raw["dry-run"])
    return {
      destination: o.destination,
      files: [
        ...files.keys(),
        ...(!["daemon", "cli-library"].includes(o.t.id)
          ? [
              ...(o.platforms.includes("iOS")
                ? Object.keys({ ...assets.icons, ...assets.launches }).map(
                    (name) => `source/iOS/Resources/${name}`,
                  )
                : []),
              ...(o.platforms.includes("macOS")
                ? ["source/macOS/Resources/AppIcon.icns"]
                : []),
            ]
          : []),
      ].sort(),
      artwork:
        "legacy phone PNGs and Mac ICNS resources generated at finalization",
    };
  const parent = path.dirname(o.destination);
  fs.mkdirSync(parent, { recursive: true });
  const realParent = fs.realpathSync(parent);
  if (/\s/.test(realParent))
    throw Error("Resolved destination contains whitespace unsupported by Make");
  if (realParent === templates || realParent.startsWith(templates + path.sep))
    throw Error("Destination resolves inside templates");
  const temp = fs.mkdtempSync(path.join(realParent, ".altivec-app-"));
  let reserved = false;
  try {
    for (const [file, data] of files) {
      const target = path.join(temp, file);
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.writeFileSync(target, data);
    }
    for (const platform of o.platforms)
      if (!["daemon", "cli-library"].includes(o.t.id))
        fs.mkdirSync(path.join(temp, `source/${platform}/Resources`), {
          recursive: true,
        });
    assets.generate(temp);
    assets.validate(temp);
    require("./check-project.cjs").check(temp);
    // Reserve exclusively: rename alone can replace an existing empty directory.
    fs.mkdirSync(o.destination);
    reserved = true;
    for (const file of fs.readdirSync(temp))
      fs.renameSync(path.join(temp, file), path.join(o.destination, file));
    return { destination: o.destination, template: o.t.id };
  } catch (e) {
    if (reserved) fs.rmSync(o.destination, { recursive: true, force: true });
    throw e;
  } finally {
    fs.rmSync(temp, { recursive: true, force: true });
  }
}
module.exports = { catalog, generate, options, buildFiles };
