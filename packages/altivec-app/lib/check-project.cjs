const fs = require("node:fs"),
  path = require("node:path");
const { spawnSync } = require("node:child_process");
function check(root) {
  const meta = JSON.parse(
    fs.readFileSync(path.join(root, ".altivec-template.json")),
  );
  if (meta.schema_version !== 1 || !meta.template_version)
    throw Error("Unsupported template metadata");
  const release = JSON.parse(
    fs.readFileSync(path.join(root, ".altivec-release.json")),
  );
  if (release.version.source !== "VERSION")
    throw Error("Missing plain version source");
  require("./assets.cjs").validate(root);
  // Python's plist parser validates generated XML without an npm dependency.
  const script = String.raw`import pathlib, plistlib, re, sys
root=pathlib.Path(sys.argv[1])
version=(root/'VERSION').read_text().strip()
for file in root.rglob('*.plist'):
 if 'build' in file.relative_to(root).parts: continue
 p=plistlib.loads(file.read_bytes())
 if file.name == 'Info.plist':
  assert p['CFBundleShortVersionString']==version and p['CFBundleVersion']==version, file
  assert re.fullmatch(r'[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)*',p['CFBundleIdentifier']), file
  for icon in p.get('CFBundleIconFiles',[]): assert (file.parent/'Resources'/icon).is_file(), icon
  if 'CFBundleIconFile' in p: assert (file.parent/'Resources'/p['CFBundleIconFile']).is_file(), file
  if file.parent.name == 'iOS':
   assert p['UIDeviceFamily'] == [1], file
   assert p['UISupportedInterfaceOrientations'] == ['UIInterfaceOrientationPortrait'], file
   assert p['UILaunchImageFile'] == 'Default', file
   expected = [('7.0','Default','{320, 480}'), ('7.0','Default','{320, 568}'),
    ('8.0','Default-iOS8-667h','{375, 667}'), ('8.0','Default-iOS8-736h','{414, 736}'),
    ('11.0','Default-iOS11-812h','{375, 812}'), ('12.0','Default-iOS12-896h','{414, 896}')]
   actual = [(v['UILaunchImageMinimumOSVersion'],v['UILaunchImageName'],v['UILaunchImageSize']) for v in p['UILaunchImages']]
   assert actual == expected, 'Launch image point sizes/names do not match the phone portrait profile'
   assert all(v['UILaunchImageOrientation']=='Portrait' for v in p['UILaunchImages']), file
for file in (root/'source').rglob('*.strings'):
 text=file.read_text(encoding='utf-8'); assert re.search(r'".+"\s*=\s*".*"\s*;',text), file
`;
  const r = spawnSync("python3", ["-c", script, root], { encoding: "utf8" });
  if (r.error || r.status !== 0)
    throw Error(`Project metadata validation failed: ${r.error || r.stderr}`);
  return meta;
}
module.exports = { check };
if (require.main === module) {
  try {
    check(path.resolve(__dirname, ".."));
    console.log(
      "PASS: metadata, plist declarations, localization and legacy artwork",
    );
  } catch (e) {
    console.error(e.message);
    process.exitCode = 1;
  }
}
