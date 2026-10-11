"""One-time migration only; the installed Node CLI never needs YAML at runtime."""
import json
import sys

try:
    import yaml
except ImportError:
    sys.exit("Migration requires Python/PyYAML; run this once inside the Altivec image, then use the JSON config on the host.")

with open(sys.argv[1], encoding="utf-8") as source:
    config = yaml.safe_load(source)
if not isinstance(config, dict):
    sys.exit("YAML configuration must be a mapping")
config["schema_version"] = 1
config.setdefault("stage_dir", "dist")
for target in config.get("targets", []):
    commands = target.get("build", [])
    if isinstance(commands, str):
        commands = [commands]
    target["build"] = [{"shell": command} if isinstance(command, str) else command for command in commands]
print(json.dumps(config, indent=2))
