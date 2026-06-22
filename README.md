[![AltiveIntelligence Fun 90's Header Image](docs/README.thumb.png)](docs/README.png)

# 🤖 Altivec Intelligence

**Altivec Intelligence** is a containerized cross-compile environment that 
is built for retro tech-enthusiasts that want to build software for their retro
Mac and iOS device. It builds Mac apps that run on all Macs with 10.4 Tiger and 
up including PowerPC, Intel, and Apple Silicon Macs. The iPhone toolchain can 
build apps that run on iPhone 3GS with iOS 4.3 and later.

Why include AI? Building apps that target these old platforms requires using
old Objective-C that does not have the syntactic sugar provided by Objective-C
2.0 or Swift. So the AI will help with that by ensuring you are only using old
APIs, helping you solve warnings, and typing out the very verbose Objective-C
with no Properties, Automatic Reference Counting, or Block Syntax.

In the end, I think everyone that is a fan of retro Macs has an app idea or two
that would make their old Mac more useful to them. But because of lack of time
or lack of desire to program old-school Objective-C, they have never gotten
around to building it. I hope that **Altivec Intelligence** will empower this
niche community to make our favorite retro-tech more useful in the modern world.

Below is a Quick Start Guide. For more detailed information about the project's
origins, technical matrix, and safety considerations, please see the
[**FAQ**](docs/FAQ.md).

## 📦 Quick Start Guide

**Altivec Intelligence** ships as a **prebuilt container image on GHCR**. You
consume it by referencing the image in a `compose.yml` at the root of your own
app repository — no submodule, no clone, no local toolchain build. This keeps
your app code fully separate from the engine, and you update the engine by
simply pulling a newer image.

### Set Up Your Project

See [templates/compose.yml](templates/compose.yml) for the full template and
notes on first-time AI assistant setup. The GHCR image ships the entire
`/altivec/` toolchain (cross-compilers, SDKs, AltivecCore/AltivecCocoa libs,
sample apps, and AI CLIs), so your repo only needs the `compose.yml` plus your
source.

```bash
# 0. If you do not already have a repository for your app idea,
#    create one with git init
git init MyCoolRepo && cd MyCoolRepo

# 1. Drop the template compose.yml into your project root:
curl -fsSL https://raw.githubusercontent.com/jeffreybergier/AltivecIntelligence/main/templates/compose.yml \
     -o compose.yml

# 2. Pull the prebuilt image (one time, multi-GB — saves 5+ hours of osxcross build):
docker compose pull

# 3. Build your app (Makefile at the root of your project):
docker compose run --rm altivec "make"

# 4. Use with AI assistant (interactive chooser picks
#    Claude / Codex / Antigravity / Pi / OpenCode):
docker compose run --rm altivec-intelligence
```

The template mounts a named Docker volume at `/cache`. The image points common
runtime caches there for npm, Yarn, pnpm, Go, Bundler, Ruby gem metadata, and
XDG-compatible tools, so disposable build/tool caches do not accumulate under
`~/.altivec`. Remove them with `docker compose down -v` when you want a clean
cache.

The image also configures Git to trust bind-mounted project directories and
points generic native build variables (`CC`, `CXX`, `LD`, `AR`) at Ubuntu's
toolchain. That keeps npm and gem native extensions from accidentally invoking
the Apple cross-linker that is also available on `PATH`.

### Introduce the AI to Your Project

#### Introduction Prompt

```
Hello, you are inside of a docker container that has a cross-compile 
environment for building retro Mac and iPhone Apps. My app code is in /repo/user. The Altivec engine and examples are in /altivec. The cross-compiler 
toolchain is in /osxcross. Please start by reading the README.md and AGENTS.md 
files in /altivec. Please always create makefiles for my app using 
the altivec_common_[mac|phone].mk files in /altivec so I can ensure my 
makefiles are small and make apps compatible with many retro Apple devices. 
Make sure you treat my repo (/repo/user) as the base location for your work on 
my app as changes made outside of volumes mounted in the compose.yml file will be lost when we finish this session.
```

#### Make a New App Prompt

``` 
I want to make my own app. My app will be called MyNewApp and I want you to use
the SingleWindow app in the /altivec/apps folder as a starting point to work
from. Please store the new app in ./source along with its new Makefile. 
After that please compile the app and ensure there are no warnings. I will
run it to make sure it works. 
```

**Note:** you can change the example app as the source depending on if you want
an iPhone app or Mac app. Also, if you want to do networking, you may consider
using the CURLmac or CURLphone app as starting place because those have
AltivecCore linked.

## Deploying to Hardware

Use the `altivec-deploy` script to quickly push and debug your apps on 
actual hardware.

**1. Run on a remote Mac (via SSH)**:
```bash
docker compose run --rm altivec "altivec-deploy /altivec/apps/SingleWindow -d <mac_ip_or_hostname>"
```

**2. Run on a jailbroken iPhone (via SSH)**:
```bash
docker compose run --rm altivec "altivec-deploy /altivec/apps/SingleScreen -d <iphone_ip_or_hostname>
```

**Note on Deploying to iPhone**
This requires common jailbreak tools like:
- AppSync (Unified)
- appinst (App Installer)
- OpenSSH
- Core Utilities

Jailbreaking and using a jailbroken iPhone is beyond the scope of this tutorial,
but I highly recommend checking out 
[Legacy-iOS-Kit](https://github.com/LukeZGD/Legacy-iOS-Kit) for help. Its an
excellent utility that is THE EASIEST way to downgrade / jailbreak your retro
iPhone. It can also be used to deploy the apps built with Altivec Intelligence
to the iPhone via the USB cable.

**Note on SSH Authentication:**
The deployment script is designed for automated use and **requires SSH key 
authentication**. If you do not have keys set up, the script will repeatedly 
prompt for your password and likely fail. 

To connect to vintage hardware from a modern Mac, you often need to explicitly 
allow older algorithms in your `~/.ssh/config` file. Here is a recommended 
configuration:

```text
Host iphone5-ios6
    HostName 192.168.0.93
    User root
    IdentityFile ~/.ssh/id_rsa
    PubkeyAcceptedAlgorithms +ssh-rsa
    HostKeyAlgorithms +ssh-rsa

Host imacg4-tiger
    HostName my-imac.local 
    User myuser
    IdentityFile ~/.ssh/id_rsa
    PubkeyAcceptedAlgorithms +ssh-rsa
    HostKeyAlgorithms +ssh-rsa
```

## 🏃 Running a Sample App

The sample apps come **prebuilt** inside the image, so you can try one without
compiling anything. The steps below copy the release build of **CURLmac** out
of the container and into your own repo, where you can unzip it and open the
`.app` on your Mac.

```bash
# 1. Copy CURLmac's release zip from the image into your project.
#    Your repo is mounted at /repo/user, so the file lands in your
#    current directory on the host:
docker compose run --rm altivec "cp /altivec/apps/CURLmac/build-release/CURLmac.zip /repo/user/"

# 2. On your Mac, unzip and launch the app:
unzip CURLmac.zip
open CURLmac.app
```

`CURLmac.app` is a Quad-Fat universal binary, so the same bundle runs on
PowerPC, 32-bit Intel, 64-bit Intel, and Apple Silicon Macs (10.4 Tiger and
newer). CURLmac links AltivecCore, so this app has modern TLS 1.2
networking, SQLite, and cJSON even on Mac OS X Tiger.

> **Note:** To copy a freshly compiled build instead of the prebuilt one, run
> `docker compose run --rm altivec "cd /altivec/apps/CURLmac && make"` first,
> then repeat step 1. Swap `CURLmac` for `SingleWindow` to grab the simpler,
> non-networking sample.

## 📂 Project Structure
- [`apps`](./apps/): Sample projects and Makefiles
- [`altivec_common_mac.mk`](./altivec_common_mac.mk): A "parent" Makefile with the general rules for compiling Mac apps
- [`altivec_common_phone.mk`](./altivec_common_phone.mk): A "parent" Makefile with the general rules for compiling Phone apps
- [`templates`](./templates/): Reusable templates for end users (compose + thin Makefiles for new app projects)
- [`templates/compose.yml`](./templates/compose.yml): The compose file end users drop into their own app repo (prebuilt GHCR image, app mounted at `/repo/user`). **This is the file most people want.**
- [`templates/altivec-release.yml`](./templates/altivec-release.yml): Optional release config for version bumps, tags, and staged release assets.
- [`templates/github-release.yml`](./templates/github-release.yml): Optional GitHub Actions workflow that builds and uploads configured release assets.
- [`compose.yml`](./compose.yml): The **engine-development** compose — clone-and-build the image locally and mount your live checkout at `/repo/altivec`. Only needed if you are customizing the engine itself.
- [`bin`](./bin/): Runtime scripts on `PATH` inside the image — `altivec-deploy` (push/run apps on hardware), `altivec-release` (version/tag helper), `altivec-chooser` (AI CLI picker)
- `AGENTS.md`: AI mandates and technical constraints (also surfaced as CLAUDE.md / GEMINI.md via symlink).

## 🧩 Makefile Templates
Use these thin templates in your app repo:
- [`templates/Makefile.mac`](./templates/Makefile.mac)
- [`templates/Makefile.phone`](./templates/Makefile.phone)

Optional AltivecCore knobs:
- `ALTIVECCORE_REQUIRED=1`: enforce required Core artifacts at validate time.
- `ALTIVECCORE_LINKAGE=dynamic|static`: choose framework or static archives on
  macOS. Phone apps support `static` only.
- `ALTIVECCORE_DIR=/path/to/altivec/libs/core/build-mac|build-phone`: override autodetect.

For iPhone apps, AltivecCore is static-only because embedded frameworks require
iOS 8+ at runtime and break the iOS 4.3-7 compatibility target.

Optional AltivecCocoa knobs:
- `ALTIVECCOCOA_REQUIRED=1`: enforce required Cocoa artifacts at validate time.
- `ALTIVECCOCOA_LINKAGE=dynamic|static`: choose `AltivecCocoa.framework` or
  `libAltivecCocoa.a` on macOS. Phone apps support `static` only.
- `ALTIVECCOCOA_DIR=/path/to/altivec/libs/cocoa/build-mac|build-phone`:
  override autodetect.

AltivecCocoa contains reusable nibless AppKit controller classes such as
`AIViewController`, `AICookieCutterWindowController`, and `AIWebViewController`,
plus the cross-platform `AIFontAwesome` icon helper. Static AltivecCocoa apps
stage Font Awesome OTFs into the app bundle; macOS dynamic apps use the fonts
inside `AltivecCocoa.framework`.
The bundled Font Awesome Free OTFs are licensed under SIL OFL 1.1; their
notice is copied with the font files.

Bundle resource knobs:
- `RES_DIR=Resources`: blind-copy ordinary resources into the bundle resource
  root. For iPhone this includes icon and launch image PNGs referenced by
  `Info.plist`.
- `INFO_PLIST=$(RES_DIR)/Info.plist`: copied to the real bundle plist location.
  `Info.plist` is required to live under `RES_DIR` by default, and is skipped
  by the blind resource copy.
- `MAC_ICON=AppIcon.icns`: copy a Mac `.icns` file into
  `Contents/Resources`.
- `BUNDLE_FONT_DIRS=../shared/Resources/Fonts`: copy font directory contents
  into the bundle's `Fonts/` directory.
- `BUNDLE_LOCALIZATION_DIRS=../shared/Resources`: copy `*.lproj` directories.
  Mac builds transcode `.strings` files to UTF-16 LE with BOM for Tiger and
  Leopard; iPhone builds copy UTF-8 `.strings` files verbatim.
- `EXTRA_BUNDLE_STEPS=...`: run app-specific bundle staging after common
  resource processing. Phone builds also support `PHONE_EXTRA_BUNDLE_STEPS`.
- `PHONE_LDID_SIGN=1` or `PHONE_LDID_ENTITLEMENTS=Entitlements.plist`: opt in
  to `ldid` pseudo-signing before IPA packaging.

## Release Helper

`altivec-release` is an optional YAML-driven helper for app repositories that
want one command to keep `Info.plist` versions, git commits, tags, and staged
release assets aligned.

Copy [`templates/altivec-release.yml`](./templates/altivec-release.yml) to
`.altivec-release.yml` in your app repo and edit the app name, plist paths,
and target artifact paths. Then run commands from the app repo root:

```bash
altivec-release current
altivec-release check 1.2.3
altivec-release bump patch --no-push
altivec-release bump --set 1.3.0 --dry-run
altivec-release build
altivec-release stage 1.3.0 --dist dist
```

For GitHub Actions, a tagged release can validate the tag against the configured
plist versions and publish environment variables with:

```bash
altivec-release ci-env "$GITHUB_REF_NAME" --github-env "$GITHUB_ENV"
```

The helper supports Mac-only, iPhone-only, and paired Mac/iPhone app layouts.
It only knows what is in `.altivec-release.yml`; build commands and artifact
names stay project-specific.

To publish releases from GitHub, copy
[`templates/github-release.yml`](./templates/github-release.yml) into
`.github/workflows/release.yml`. That workflow runs `altivec-release` inside
the Altivec container, builds the configured targets, stages `dist/*`, and
uploads those files to the tag's GitHub release.

## 🔧 Customizing the Container

Everything above uses the **prebuilt GHCR image** and never requires a clone.
You only need this section if you want to **modify the engine itself** — change
build rules in `altivec_common_*.mk`, edit the `bin/` scripts, add a new
library, or rebuild `AltivecCore` and its dependencies from source.

### 1. Prerequisites
- [**Git**](https://git-scm.com/install/) (to clone the engine repo)
- [**Docker Desktop**](https://www.docker.com/get-started/) or an alternative

### 2. Docker Resources
The from-source build compiles Apple GCC 4.2.1, so give Docker some headroom in
its Settings → Resources tab:
- 6–8 GB RAM
- As many CPU cores as you can spare

### 3. Clone and Build
This compiles the toolchain from source and can take **5–30 minutes** the first
time (cached afterward). Tune the `JOBS=` line of the
[`Containerfile`](Containerfile#L53) to match your allotted cores.

```bash
git clone https://github.com/jeffreybergier/AltivecIntelligence.git
cd AltivecIntelligence
docker compose build
```

The root [`compose.yml`](./compose.yml) is wired for this workflow: it mounts
your live checkout at `/repo/altivec` (the working directory) while the baked
toolchain stays at `/altivec`.

### 4. Applying Engine Edits
⚠️ **Important:** `/altivec` is baked into the image at build time; your live
checkout is mounted separately at `/repo/altivec`. A build that includes
`/altivec/altivec_common_mac.mk` therefore uses the **baked** copy, *not* your
edits. To make engine changes take effect you must either:

- **Rebuild the image** with `docker compose build`, or
- **Overlay your checkout** by adding `- .:/altivec` to the service's `volumes`
  so your live files shadow the baked toolchain.

## 🚧 To-Do List
1. [ ] Enable on-device debugging for iOS
1. [X] Add macOS libraries as dynamic frameworks (e.g. `AltivecCore.framework`)
1. [ ] Add `libgit` as a dependency for file syncing
1. [ ] Setup Github Actions
   1. [ ] Build release apps and save in artifact storage
   1. [ ] Execute tests on Mac runners
1. [X] Build `libcurl` for modern networking on old platforms
1. [X] Improve Deploy Script
1.    [X] Enable AI to debug apps directly on the host Mac
1. [X] Remove Custom-Built 10.5/10.6 Hybrid SDK 
   1. [X] Change x64 Build to use Clang-14 and macOS 11.3 SDK
   1. [X] Change PPC and x86 Build to use Apple GCC 4.2.1 and Mac OS X 10.5 SDK
 

## 😍 Contributing
This was a small project for me so I could work on my own hobby apps for my 
iPhone 5 and my iMac G4. I am not a compiler, cmake, SDK, or build-system 
engineer. I would not have been able to do this without AI. That said,
I also know AI has probably not produced the most efficient build files
and scripts. So I am totally open to new ideas. How can we improve them, how
can I learn more. If you know, I want to know. So please file an issue and let's
talk about it ❤️

## ⚖️ License & Credit
This project is built on top of [OSXCross](https://github.com/tpoechtrager/osxcross). 
You should check out this project because it could make it much easier and
cheaper for you to automatically build and release your apps because it allows
building in Linux containers instead of on expensive Mac runners.

This project is licensed under the **MIT License**. This is a permissive license
that allows for free use, modification, and distribution. Note that it downloads
various open-source and closed-source components (like OSXCross and Apple's
SDKs) which carry their own licenses.
