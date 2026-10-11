# Manual deployment recipes

Run these commands from a host or container with access to the built artifacts.
Edit the device names and artifact paths before running them. SSH authentication
and a verified host key must already work. The image retains SSH/SCP and rsync;
rsync requires rsync on the receiving device too. With a current OpenSSH client,
use `scp -O` instead of `scp` if an old device lacks SFTP.

Use a fresh staging directory for each run: below `~/Desktop` on a Mac or
`~/tmp_altivec` on an iPhone. Commands below assume simple directory names with
no spaces. The person running a recipe owns its staging cleanup; keep logs until
they have been retrieved. Package installers own installed files outside staging.
Do not manually copy or delete files in system application directories.

The checked-in SingleWindow/CURLmac samples produce ZIPs containing Mac `.app`
bundles under `build/<platform>/<configuration>/<product>/`. SingleScreen and
CURLphone produce IPAs there. Declarative product builds instead use
`build/<platform>/<release|debug>/`; use the actual output reported by Make.
DEBs require an explicitly configured package product, as described in
[the product API](make-products.md). Match the CPU architecture, minimum OS,
signing policy, and jailbreak package layout to the destination.

## Transfer and launch a Mac bundle

Prerequisites: Remote Login enabled, `unzip`, and a logged-in graphical session
for GUI applications. Use the desktop user's SSH account. Package: the sample
ZIP containing `SingleWindow.app` (substitute `CURLmac` for that sample).

```sh
mac=user@mac-host
stage=Desktop/Altivec-SingleWindow-run1
ssh "$mac" "mkdir -p Desktop && mkdir '$stage'"
scp apps/SingleWindow/build/macOS/release/SingleWindow/SingleWindow.zip "$mac:$stage/"
ssh "$mac" "cd '$stage' && unzip -q SingleWindow.zip && open SingleWindow.app"
```

For stdout/stderr, quit the GUI instance first, then run its executable in the
foreground. This needs a usable graphical session too; it is not a headless UI
runner. Supply any application environment variables explicitly here.

```sh
ssh "$mac" "cd '$stage' && ./SingleWindow.app/Contents/MacOS/SingleWindow >app.log 2>&1"
```

Quit the app normally before cleanup. Retrieve logs first using the recipe below,
then remove only this run's staging directory:

```sh
ssh "$mac" "rm -rf '$stage'"
```

For an unpacked bundle, `rsync -a path/to/SingleWindow.app "$mac:$stage/"`
is an alternative to transferring and extracting the ZIP. Keep matching dSYMs
locally for crash analysis; symbol generation does not require a debugger.

## Install an IPA on a jailbroken iPhone

Prerequisites: SSH, a compatible jailbreak/signing setup (such as the appropriate
AppSync version), and `appinst` or `ipainstaller` installed on the device. Use an
account with permission to run that installer. An IPA is not a DEB; this recipe
is not an installation method for an ordinary non-jailbroken iPhone.

```sh
phone=root@iphone-host
stage=tmp_altivec/SingleScreen-run1
ssh "$phone" "mkdir -p tmp_altivec && mkdir '$stage'"
scp apps/SingleScreen/build/iOS/release/SingleScreen/SingleScreen.ipa "$phone:$stage/"
ssh "$phone" "cd '$stage' && appinst SingleScreen.ipa"
# If this device uses ipainstaller instead, replace the previous command with:
# ssh "$phone" "cd '$stage' && ipainstaller SingleScreen.ipa"
```

Launch SingleScreen from the Home Screen; use CURLphone's IPA/name for that
sample. App launching and icon registration depend on the device's installer and
jailbreak. Follow their instructions if the icon does not appear. Collect logs
and crash reports as below, then remove staging:

```sh
ssh "$phone" "rm -rf '$stage'"
```

The installed app remains. Remove it using the device's supported app uninstall
method when finished; deleting the transferred IPA does not uninstall it.

## Install rootful or rootless DEBs

Prerequisites: a matching jailbreak bootstrap, its `dpkg`, required dependencies,
and package-install privileges. Select a package built for that bootstrap's
architecture and layout. Rootful packages normally target `/`; rootless packages
normally target `/var/jb`. Renaming a rootful DEB does not convert it to rootless.
Do not force architecture checks or change package paths during installation.

Run this recipe once for the appropriate package variant, never both as a test:

```sh
phone=root@iphone-host
stage=tmp_altivec/package-run1
deb=path/to/MyApp-rootless.deb  # Or the matching rootful DEB.
ssh "$phone" "mkdir -p tmp_altivec && mkdir '$stage'"
scp "$deb" "$phone:$stage/package.deb"
ssh "$phone" "cd '$stage' && dpkg --info package.deb && dpkg --contents package.deb"
# Review package identity, dependencies, architecture, paths, and lifecycle scripts.
ssh "$phone" "cd '$stage' && dpkg -i package.deb"
```

If `dpkg` is not on the SSH PATH, use the bootstrap's documented absolute path.
Resolve dependencies through that bootstrap's package manager; a failed install
is not a successful deployment. Launch the installed UI from the Home Screen.
Package lifecycle scripts may register icons or start a daemon; use the project's
service instructions rather than starting a second copy manually.

After collecting diagnostics, remove staging with
`ssh "$phone" "rm -rf '$stage'"`. This does not uninstall the package. To uninstall,
use the package manager or `dpkg -r PACKAGE_ID` with the exact installed package
ID and appropriate privileges. The package's lifecycle scripts own stopping its
services and removing installed files; retained user data is a separate decision.

## Retrieve logs and crash reports

Prerequisites: permission to read the selected log/report. Collect into a local
run directory. These commands are read-only on the device; they do not clear
system logs or delete crash reports.

```sh
mkdir -p device-logs/run1
scp "$mac:$stage/app.log" device-logs/run1/mac-app.log
```

Here `mac` and `stage` must still refer to the Mac run. For a daemon use its
`daemon.log` instead. For system logs, select a path that actually exists:

```sh
ssh "$mac" 'tail -n 200 /var/log/system.log' >device-logs/run1/mac-system.log
ssh "$phone" 'tail -n 200 /var/log/syslog' >device-logs/run1/phone-system.log
```

Those files are not available on every OS. On a Mac with unified logging:

```sh
ssh "$mac" "log show --last 10m --predicate 'process == \"SingleWindow\"'" >device-logs/run1/mac-unified.log
```

For live file logs use `tail -f`; Ctrl-C ends collection, not the application.

Look for Mac reports in `~/Library/Logs/CrashReporter`,
`~/Library/Logs/DiagnosticReports`, or the corresponding `/Library/Logs`
directory. iPhone reports commonly live in
`/var/mobile/Library/Logs/CrashReporter`; availability and access vary by OS.
List the appropriate directory, select the report for this app/run, then copy
that exact path, for example:

```sh
ssh "$phone" 'ls -lt /var/mobile/Library/Logs/CrashReporter'
scp "$phone:/var/mobile/Library/Logs/CrashReporter/SELECTED_REPORT" device-logs/run1/
```

Keep the binary and matching dSYMs from the same build alongside diagnostics.
Debuggers and symbolication tools can be installed separately when needed.

## Start and stop a standalone test daemon

Prerequisites: an executable built and signed for this device, its runtime
resources, and a documented foreground mode. This recipe uses no package or
launchd service. Do not use it for a daemon already managed by an installed DEB.
Use the least-privileged account the test supports.

```sh
device=user@mac-host
stage=Desktop/Altivec-daemon-run1
# For an iPhone, use its SSH account and stage=tmp_altivec/daemon-run1.
ssh "$device" "mkdir -p '${stage%/*}' && mkdir '$stage'"
scp path/to/test-daemon "$device:$stage/test-daemon"
ssh "$device" "cd '$stage' && chmod +x test-daemon"
```

In terminal A, run the daemon in the foreground with a PID file and explicit
stdout/stderr capture. Add its documented foreground flag if needed; the process
must not fork away from this PID. Add required resources/configuration to staging.

```sh
ssh "$device" "cd '$stage' && echo \$\$ >daemon.pid && exec ./test-daemon >daemon.log 2>&1"
```

In terminal B, with the same `device` and `stage` values, inspect the recorded PID
and process command before signaling it. If the daemon exited, do not signal a
stale PID that might now belong to another process.

```sh
ssh "$device" "cd '$stage' && ps -p \$(cat daemon.pid) -o pid=,command="
# After verifying that this is still this run's test daemon:
ssh "$device" "cd '$stage' && kill -TERM \$(cat daemon.pid)"
```

Wait for terminal A to exit, retrieve the log, then remove this run's staging:

```sh
mkdir -p device-logs/daemon-run1
scp "$device:$stage/daemon.log" device-logs/daemon-run1/
ssh "$device" "rm -rf '$stage'"
```

The operator owns stopping this process even if SSH disconnects.
For launchd-managed daemons, use the project's OS-specific service commands and
cleanup rather than this foreground recipe.

## Automated tests and optional debugging

Keep each project's native test runner as the authority for deployment,
assertions, exit status, timeouts, and cleanup. For example, Retro-Cloud-Sync's
`source/tests/macOS/native-stores/run-remote.py` and
`source/tests/iOS/native-stores/run-remote.py` remain project-owned runners.
These manual recipes do not replace automated integration or UI tests.

Normal builds, `make debug`, static analysis, and automated tests do not need
GDB or LLDB. The image retains Clang, LLVM development components, the LLD linker,
and `dsymutil`; it does not explicitly install LLDB. If interactive debugging is
needed, install a debugger compatible with the target separately. Build symbols
and debugger installation are independent choices.
