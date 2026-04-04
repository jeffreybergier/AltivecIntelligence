[![AltiveIntelligence Fun 90's Header Image](README.thumb.png)](README.png)

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
[**FAQ**](README.FAQ.md).

## 📦 Installation & Quick Start

### 1. Prerequisites

- [**Git**](https://git-scm.com/install/)
- [**Docker Desktop**](https://www.docker.com/get-started/) or alternative solution.

### 2. Pre-setup

To optimize performance of the initial build, open Docker Desktop and configure
the Resources tab in the Settings window. 

- Ensure Docker has 6-8GB RAM.
- Ensure Docker is allowed to use as many CPU cores as you like.

### 3. Build the Container

This project compiles Apple GCC 4.2.1 from source, so this initial build step
can take 5-30 minutes depending on how fast your computer is. But this only
needs to be done once. After that, it is quick to load.

Before running `docker compose build` you can configure the number of cores 
the build is allowed to use by changing the `JOBS=` line of the 
[`Containerfile`](Containerfile#L53). Note that it should be set to be equal to
or less than the number of cores you configured in the Docker settings.

```bash
git clone https://github.com/your-username/AltivecIntelligence.git
cd AltivecIntelligence
docker compose build
```

### 4. Build Example Projects

#### Mac Apps

Verify the Mac toolchain by building the `SingleWindow` app:
```bash
docker compose run --rm altivec "cd apps/SingleWindow && make"
```
Outputs in `apps/SingleWindow/build-release/`:
- `SingleWindow.app`: Universal Mac App compatible with all Macs running Mac OS X 10.4 Tiger and newer (PowerPC, Intel 32-bit, Intel 64-bit, Apple Silicon)
- `SingleWindow.zip`: App Package as a Zip
- `SingleWindow.[x64|arm].dSYM`: Debug Symbols for X64 and ARM Macs

Verify the iPhone toolchain by building the `SingleScreen` app:
```bash
docker compose run --rm altivec "cd apps/SingleScreen && make"
```
Outputs in `apps/SingleScreen/build-release/`:
- `SingleScreen.ipa`: Universal iPhone App Compatible with:
  - iPhone 3GS+
  - iOS 4.3+
- `SingleScreen.app`: The iPhone App in its original .app form
- `SingleScreen.dSYM`: Debug Symbols

Note you can also run `make debug` to build a debug version of the sample apps

#### CURL Networking Apps (Modern TLS for Legacy Devices)

These apps use the **`AICURLConnection`** library (built on `libcurl` and 
`OpenSSL`) to allow legacy devices to connect to modern HTTPS websites.

**Note:** Building the full `libcurl` suite for all architectures is a heavy 
task and may take between **5 to 60 minutes** depending on your computer's 
performance.

##### Mac Build (CURLmac)
```bash
# 1. Build libcurl suite for Mac (PPC, i386, x64, arm64)
docker compose run --rm altivec "cd libs/libcurl && make mac"

# 2. Build the CURLmac app
docker compose run --rm altivec "cd apps/CURLmac && make"
```

##### iPhone Build (CURLphone)
```bash
# 1. Build libcurl suite for iPhone (armv7, arm64)
docker compose run --rm altivec "cd libs/libcurl && make phone"

# 2. Build the CURLphone app
docker compose run --rm altivec "cd apps/CURLphone && make"
```

#### Deploying to Hardware

Use the `altivec_deploy.sh` script to quickly push and debug your apps on 
actual hardware.

**1. Run on your local Mac**:
```bash
./altivec_deploy.sh apps/SingleWindow
```

**2. Run on a remote Mac (via SSH)**:
```bash
./altivec_deploy.sh apps/SingleWindow -d <mac_ip_or_hostname>
```

**3. Run on a jailbroken iPhone (via SSH)**:
```bash
./altivec_deploy.sh apps/SingleScreen -d <iphone_ip_or_hostname>
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

### 5. Use Gemini AI to Build Your Own Apps

Launch Gemini CLI and login with your Google Account. Even the free account 
should allow plenty of retro-app creation time. Please see 
[Gemini documentation](https://geminicli.com/docs/get-started/examples/)
for more info on how to use Gemini CLI.

```bash
docker compose run --rm altivec-intelligence
```

#### Using as a Submodule
If you want to use Altivec Intelligence as an engine for your own app 
repository, we recommend adding this project as a git submodule. Please see 
[altivec_compose.yml](altivec_compose.yml) for exact instructions and a template 
`compose.yml` for your parent repository.

#### Example Prompt
Try starting your session by explaining the environment to the AI:
```
Hello, you are inside of a docker container that has a cross-compile 
environment for building retro Mac and iPhone Apps. My app code is in /repo/user. 
The Altivec engine and examples are in /repo/altivec. The cross-compiler 
toolchain is in /osxcross. Please start by reading the README.md and GEMINI.md 
files in the engine folder. Please always try create makefiles for my app using 
the altive_common[mac|phone].mk files in the `/repo/altivec` folder so I can 
ensure my makefiles are small and make apps compatible with many retro Apple 
devices. Make sure you treat my repo (/repo/user) as the base location for your 
work on my app.
```

### 6. Make Your Own App with Gemini
Decide whether you want to make an iPhone App or a Mac App, and then ask Gemini
to make you a new app.

``` 
I want to make my own app, can you start with the SingleWindow app and make
me a new app called MyCoolApp? Then we can get started creating the exact retro
app for my favorite retro device. 
```

## 📂 Project Structure
- [`apps`](./apps/): Sample projects and Makefiles
- [`altivec_common_mac.mk`](./altivec_common_mac.mk): A "parent" Makefile with the general rules for compiling Mac apps
- [`altivec_common_phone.mk`](./altivec_common_phone.mk): A "parent" Makefile with the general rules for compiling Phone apps
- `altivec_deploy.sh`: Automated SSH deployment script.
- `GEMINI.md`: AI mandates and technical constraints.

## 🚧 To-Do List
1. [ ] Enable on-device debugging for iOS
1. [ ] Learn how to add libraries as dynamic frameworks (not static libs)
1. [ ] Add `libgit` as a dependency for file syncing
1. [ ] Setup Github Actions
   1. [ ] Build release apps and save in artifact storage
   1. [ ] Execute tests on Mac runners
1. [X] Build `libcurl` for modern networking on old platforms
1. [X] Improve Deploy Script
1.    [X] Enable Gemini to debug apps directly on the host Mac
1. [X] Remove Custom-Built 10.5/10.6 Hybrid SDK 
   1. [X] Change x64 Build to use Clang-14 and macOS 11.3 SDK
   1. [X] Change PPC and x86 Build to use Apple GCC 4.2.1 and Mac OS X 10.5 SDK
 

## 😍 Contributing
This was a small project for me so I could work on my own hobby apps for my 
iPhone 5 and my iMac G4. I am not a compiler, cmake, SDK, or build-system 
engineer. I would not have been able to do this without Gemini. That said,
I also know Gemini has probably not produced the most efficient build files
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

