[![AltiveIntelligence Fun 90's Header Image](README.png)](README.thumb.png)

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
- `SingleWindow.app`: Universal Mac App compatible with:
  - Tiger+ (PPC, X86)
  - Leopard+ (PPC, X86, X64)
  - Big Sur+ (X64, ARM64)
- `SingleWindow.zip`: App Package as a Zip
- `SingleWindow.[X86|ARM].dSYM`: Debug Symbols for X64 and ARM Macs

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

### 5. Use Gemini AI to Build Your Own Apps

Launch Gemini CLI and login with your Google Account. Even the free account 
should allow plenty of retro-app creation time. Please see 
[Gemini documentation](https://geminicli.com/docs/get-started/examples/)
for more info on how to use Gemini CLI.

```bash
docker compose run --rm altivec-intelligence
```

I always recommend starting your session by either resuming the previous session
with `/resume` so it can reload its context OR by asking it to pre-populate its
context so that it knows about its own environment

```
Hello, can you start off by reading the README.md file as well as your
GEMINI.md file. Then explore the docker container you are in, especially
/osxcross and the apps folder in the current working directory. After that, let
me know what you can do and what you can help me with. 
```

### 6. Make Your Own App with Gemini

Decide whether you want to make an iPhone App or a Mac App, and then ask Gemini
to make you a new app.

``` I want to make my own app, can you start with the SingleWindow app and make
me a new app called MyCoolApp? Then we can get started creating the exact retro
app for my favorite retro device. ```

## 📂 Project Structure
- [`apps`](./apps/): Sample projects and Makefiles
- [`altivec_common_mac.mk`](./altivec_common_mac.mk): A "parent" Makefile with the general rules for compiling Mac apps
- [`altivec_common_iphone.mk`](./altivec_common_iphone.mk): A "parent" Makefile with the general rules for compiling iPhone apps
- `altivec_deploy.sh`: Automated SSH deployment script.
- `GEMINI.md`: AI mandates and technical constraints.

## 🚧 To-Do List
1. [ ] Build `libcurl` for modern networking on old platforms
1. [ ] Update Deploy Script for Mac to deploy entire build folder for better debugging in GDB
1. [ ] Setup Github Actions
   1. [ ] Build release apps and save in artifact storage
   1. [ ] Execute tests on Mac runners
1. [ ] Remove Custom-Built 10.5/10.6 Hybrid SDK 
   1. [ ] Change x64 Build to use Clang-14 and macOS 10.11 SDK
   1. [ ] Change PPC and x86 Build to use Apple GCC 4.0 and Mac OS X 10.4u SDK
1. [ ] Enable on-device debugging for iOS
1. [ ] Enable Gemini to debug apps directly on the host Mac
1. [ ] Include [`PLBlocks` \(Plausible Blocks\)](https://plausible.coop/blog/2009/07/02/blocks-for-iphone-3.0-and-mac-os-x-10/) for use in the 10.4u SDK slices to enable block usage for all toolchains 

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

