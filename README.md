> [!NOTE]
> **AI Disclosure:** Altivec Intelligence has been lovingly crafted for retro
> Apple devices by me. Also the writing in this README and associated 
> [blog post](https://jeffburg.com/unenshittification/2026/04/22/Altivec-Intelligence.html) 
> is 100% written by me. That said, the build system and makefiles are 100% AI
> generated.

[![AltiveIntelligence Fun 90's Header Image](docs/README.thumb.png)](docs/README.png)

# 🤖 Altivec Intelligence

**Altivec Intelligence** is a containerized cross-compile environment that 
is built for retro tech-enthusiasts that want to build software for their retro
Mac and iOS device. It builds Mac apps that run on all Macs with 10.4 Tiger and 
up including PowerPC, Intel, and Apple Silicon Macs. The iPhone toolchain can
build apps that run on iPhone 3GS with iOS 5.0 and later.

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

### BYOSDK

Altivec Intelligence is BYOSDK (Bring Your Own SDK) 
([reference](https://en.wikipedia.org/wiki/Mac_Mini#Form_and_design))
and does not contain or download Apple SDK's. You must provide them yourself.
The provided template compose file provides a way to "install" them via Docker
volumes. Please google for the following files with "Github" as a keyword to
find them:

- `iPhoneOS8.4.sdk.tar.gz`
- `MacOSX10.5.sdk.tar.xz`
- `MacOSX11.3.sdk.tar.xz`

The install script provided verifies the file checksums, so it will fail if
you somehow found a different file with the same name.

### Set Up Your Project

**1. Create a folder for your app project**

`mkdir MyCoolApp && cd MyCoolApp`

or if you want it to be in a git repo

`git init MyCoolApp && cd MyCoolApp`

**2. Use the Docker Compose Template**

1. Download the [templates/compose.yml](templates/compose.yml)
1. Move or copy it into the `MyCoolApp` folder

**3. Prepare the SDK's**

```bash
mkdir .altivec-sdk
touch .gitignore && echo '.altivec-sdk/' >> .gitignore
cp ~/Downloads/iPhoneOS8.4.sdk.tar.gz .altivec-sdk/
cp ~/Downloads/MacOSX10.5.sdk.tar.xz .altivec-sdk/
cp ~/Downloads/MacOSX11.3.sdk.tar.xz .altivec-sdk/
```

**4. Pull the Docker Image and Install the SDK's**

```bash
docker compose pull
docker compose run --rm altivec-sdk install
```

**5. Copy a Sample App and Compile**

There are 4 sample apps you can choose from, but CURLmac will be the best
starting point. After it compiles with `make debug` you can launch the .app
file on your modern Mac or your retro Mac.

```bash
docker compose run --rm altivec "cp -r /altivec/apps/CURLmac/. ./"
docker compose run --rm altivec "make debug"
```

CURLmac is an example application that shows the basics of how you can do 
modern networking even on a retro Mac. It is already linked to AltivecCore which
includes libcurl, cJSON, and SQLite for modern networking and database 
capabilities.

**6. Use AI**

Altivec Intelligence has built in AI tools which keeps them sandboxed. After
running the following command you can choose which AI tool you want to use.
Note if you want to try for free, use your Google account with 
[Antigravity](https://antigravity.google/pricing)

`docker compose run --rm altivec-intelligence`

### Introduce the AI to Your Project

#### Introduction Prompt

``` 
Hello, you are inside of a docker container that has a cross-compile
environment for building retro Mac and iPhone Apps. My app code is in
/repo/user. The Altivec engine and examples are in /altivec. The modern
cross-compiler toolchain is in /osxcross/modern and the Apple GCC/PowerPC
toolchain is in /osxcross/legacy/target. Please start by reading the README.md
and AGENTS.md files in /altivec. Please always create makefiles for my app using
the altivec_common_[mac|phone].mk files in /altivec so I can ensure my makefiles
are small and make apps compatible with many retro Apple devices. Make sure you
treat my repo (/repo/user) as the base location for your work on my app as
changes made outside of volumes mounted in the compose.yml file will be lost
when we finish this session. 
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

Sample source is included in the image, while tagged sample binaries live with
the matching [GitHub Release](https://github.com/jeffreybergier/AltivecIntelligence/releases).
With GitHub CLI installed on the host, download the newest **CURLmac** build
without compiling it:

```bash
# 1. Download the latest matching release asset.
gh release download --repo jeffreybergier/AltivecIntelligence \
  --pattern 'CURLmac-*.zip'

# 2. On your Mac, unzip and launch the app:
unzip CURLmac-*.zip
open CURLmac.app
```

`CURLmac.app` is a Quad-Fat universal binary, so the same bundle runs on
PowerPC, 32-bit Intel, 64-bit Intel, and Apple Silicon Macs (10.4 Tiger and
newer). CURLmac links AltivecCore, so this app has modern TLS 1.2
networking, SQLite, and cJSON even on Mac OS X Tiger.

To make a fresh build instead, compile and copy it during the same disposable
container run:

```bash
docker compose run --rm altivec \
  "cd /altivec/apps/CURLmac && make release && cp build-release/CURLmac.zip /repo/user/"
```

Swap `CURLmac` for `SingleWindow` to build the simpler, non-networking sample.
Each tagged release also carries AltivecCore/AltivecCocoa packages, the optional
iOS armv7 `AltivecToolchain` `.deb`, and `SHA256SUMS`. No arm64 device-toolchain
package is currently built.

## 📂 Project Structure
- [`apps`](./apps/): Sample projects and Makefiles
- [`altivec_common_mac.mk`](./altivec_common_mac.mk): A "parent" Makefile with the general rules for compiling Mac apps
- [`altivec_common_phone.mk`](./altivec_common_phone.mk): A "parent" Makefile with the general rules for compiling Phone apps
- [`templates`](./templates/): Reusable templates for end users (compose + thin Makefiles for new app projects)
- [`templates/compose.yml`](./templates/compose.yml): The compose file end users drop into their own app repo (prebuilt GHCR image, app mounted at `/repo/user`). **This is the file most people want.**
- [`templates/altivec-release.yml`](./templates/altivec-release.yml): Optional release config for version bumps, tags, and staged release assets.
- [`templates/github-release.yml`](./templates/github-release.yml): Optional GitHub Actions workflow that builds and uploads configured release assets.
- [`toolchain`](./toolchain/): Optional toolchain package sources. The current release-extras workflow builds only `iOS/armv7`; shared iOS helpers live in `iOS/common`.
- [`compose.yml`](./compose.yml): The **engine-development** compose — clone-and-build the image locally and mount your live checkout at `/repo/altivec`. Only needed if you are customizing the engine itself.
- [`bin`](./bin/): Runtime scripts on `PATH` inside the image, including `altivec-sdk` for verified SDK archive management.
- [`docs/altivec-deploy.md`](./docs/altivec-deploy.md): Deployment behavior and command-line specification for `altivec-deploy`.
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
iOS 8+ at runtime and break the iOS 5-7 compatibility target.

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
The build downloads checksum-pinned Font Awesome Free OTFs from redundant
sources and verifies cached copies before use. Release outputs bundle those
fonts under SIL OFL 1.1 and copy their notice alongside them. Static-library
clients can also use `+[AIFontAwesome fontAwesomeLicenseText]` to present the
complete license in an About or Licenses screen without loading the notice as
a resource. Run `make -C libs/cocoa fontawesome-fetch` to prefill the ignored
cache without compiling the framework.

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
The from-source build compiles Apple GCC 4.2.1 and current OSXCross, so give Docker some headroom in
its Settings → Resources tab:
- 6–8 GB RAM
- As many CPU cores as you can spare
- At least 50 GB of free Docker disk space (separate from free host disk space)

### 3. Clone and Build
This builds the isolated legacy toolchain first, then the modern toolchain, and
is a heavyweight first-time build. Plan on **5+ hours**, depending on the host
and the resources assigned to Docker; subsequent builds are much faster when
the expensive layers are cached. Build parallelism automatically matches the
CPU cores visible to Docker. To cap it, pass an explicit build argument, for
example `docker compose build --build-arg JOBS=4`.

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
   1. [X] Change x64/arm64 builds to use current OSXCross, Clang 21, and macOS 11.3 SDK
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
that allows for free use, modification, and distribution. The SDK-free image
and repository still use separately downloaded open-source and closed-source
build inputs. Those inputs, including Apple SDKs, carry their own licenses and
remain the user's responsibility.
