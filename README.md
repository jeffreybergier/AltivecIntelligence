[![AltiveIntelligence Fun 90's Header Image](README.png)](README.thumb.png)

# 🤖 Altivec Intelligence

**Altivec Intelligence** is about making retro development fun. It's a containerized environment that lets you build the apps you've always wanted for your PowerPC Mac or early iPhone, from any modern computer. My hope is that veteran and beginner programmers alike will be able to use this to make their retro Mac or iPhone more useful in their daily life.

## 📦 Installation & Quick Start

### 1. Prerequisites
- **Docker & Docker Compose**
- **Git**
- **Resources**:
  - Ensure Docker has 6-8GB RAM.
  - Ensure Docker is allowed to use multiple CPU cores.
  - **Job Count**: Check the [Job Count in Containerfile](Containerfile#L53) and ensure it is the same or less than the number of cores assigned to Docker.

### 2. Setup

This project compiles Clang 3.8 from source, so this initial build step can take 20-90 minutes depending on how fast your computer is. But this only needs to be done once. After that, it is quick to load.

```bash
git clone https://github.com/your-username/AltivecIntelligence.git
cd AltivecIntelligence
docker compose build
```

### 3. Build Example Project
Verify the toolchain by building the `SingleWindow` app:
```bash
docker compose run --rm altivec "cd apps/SingleWindow && make all"
```
Outputs in `apps/SingleWindow/build/`:
- `SingleWindow-X6.zip`: Universal (x86_64, i386, ppc) for Leopard+
- `SingleWindow-X4.zip`: PowerPC for Tiger (10.4)
- `SingleWindow-i8.ipa`: iOS 4.3+ (arm64, armv7s, armv7)

### 4. Deploy to Hardware
Use the deployment script to send apps via SSH:
```bash
docker compose run --rm altivec "./altivec_deploy.sh -td username@retro-mac.local -tp apps/SingleWindow/build/SingleWindow-X4.zip"
```

### 5. Use Gemini AI
Launch the AI assistant to help with legacy Objective-C:
```bash
docker compose run --rm altivec-intelligence
```

## 📂 Project Structure
- `apps/SingleWindow`: Sample projects and Makefiles.
- `altivec_deploy.sh`: Automated SSH deployment script.
- `GEMINI.md`: AI mandates and technical constraints.
- `altivec_build/`: Toolchain patches and build scripts.

## 📖 Resources
- [RyPress Objective-C (Manual Memory Management)](http://web.archive.org/web/20160317182651/http://rypress.com/tutorials/objective-c/index)
- [Lapcat Software (Working Without a Nib)](https://lapcatsoftware.com/articles/)

## 🚧 To-Do
- [ ] Enable on-device debugging for iOS (lldb).
- [ ] Build `libcurl` for modern networking on old platforms.
- [ ] Fix `dsymutil` for PowerPC debug symbols.

## 🖥️ Supported Target Matrix

| Target | Compiler | SDK | Architectures | Compatibility |
| :--- | :--- | :--- | :--- | :--- |
| **Mac** | Clang 3.8.0 | 10.6 | x86_64, i386, ppc | 10.5 Leopard to macOS 27 (Rosetta 2) |
| **Tiger** | Apple GCC 4.2.1 | 10.4u | ppc (32-bit) | 10.4 Tiger (Native) |
| **iPhone** | Clang 14.0 | 8.2 | arm64, armv7s, armv7 | iOS 4.3 to modern |

## 🤨 Question: Why I Built This

About a year ago, I was hard at work on [MathEdit for
OpenStep](https://github.com/jeffreybergier/MathEdit). This project was very fun
but it was extremely tedious. I wrote all of the old Objective-C by hand, I
maintained a fleet of Virtual Machines to enable building the project in the
native development environment for that period. Updating the app required
booting up 5 different VM's and compiling one by one to build binaries. It was
extremely time intensive and tedious.

To avoid this, I wanted a portable cross-compile environment that uses the most
compatible SDK's so that I only need to build it once and run it everywhere.
This is why I chose Mac OS X 10.6 SDK and iPhone OS 8.2 SDK. 10.6 can compile
PPC apps for Tiger and up as well as i386 and x86_64 to run on modern Macs.
iPhoneOS 8.2SDK can deploy all the way down to iOS 4.3 with armv7 and can run on
modern iPhones with arm64. For this reason, I started working on this container.
But then why AI?

### In Defense of AI Development

Anyone can have their issues with modern LLM technology. It is controversial.
And I would caution people to use AI in production. There is a lot that can go
wrong. But in this case, when tinkering on retro software development for legacy
systems, the considerations are all different:

#### Reliability and Code Quality

These are normally concerns in production because you need reliability and you
need to be able to share development with others on your team. But when working
on retro software projects, you are probably just developing on your own for
your own hobby project. In that case, it just needs to work for you. And if it 
works for you, then someone coming in and giving 

#### Tedious Programming with Old Objective C

What makes developing with modern Objective C, Swift, and SwiftUI so great on
modern Apple platforms? **Syntactic Sugar**, I realized this when working on
MathEdit. Modern Objective C with Property Syntax, Dot Syntax, and Automatic
Reference Counting are just syntactic sugar. They are not needed at all. Its
just extremely tedious to work without them. But for AI, this is not a concern.
AI is happy to type `[retain]` and `[release]` all over the place with no concern.

For this reason, I think AI will actually be a **HUGE BOON** to the retro
computing world. Because if you want an open source app to be "backported" to an
old platform. Just point AI at it and ask it backport it for you. Well, maybe it
won't be that easy. But you get the idea. AI will allow tech-savvy beginning
programmers to more easily create new software for their favorite tech.

### 😎 Answer: Why I Built This

I think this and other projects like this will really help grow the retro tech
community and so I thought it was something exciting to share with others. I
hope you can find a way to use this to make your retro computer more useful in
your daily lives ❤️

## 🧯 Safety

I really enjoy working with GEMINI CLI. However, I am hesitant to let it run on
my Mac directly. So I always containerize Gemini in Docker container like in
this project. When GEMINI is contained like this, it cannot read or damage your
personal files. It only has access to the files in the docker container and the
repository you are working in. This makes me feel much safer because at any 
moment I can force quit the AI and then revert the changes in GIT.

There is one exception to this rule which is if you enable SSH access for the 
AI. This is disabled by default, but it will really help you with debug and test
speed. When you allow the AI to have access to your SSH keys, it could theoretically
log into any system you have acces to such as Github or other Macs on the network 
and once in there, it has the same permissions as you to read and write pretty much 
any file. So **USE WITH CAUTION**

To enable SSH in the Docker Container and thus in the AI, uncomment this line in
the [`compose.yml`](compose.yml#L20) and then rerun `docker compose run --rm
altivec-intelligence`

## ⚖️ License

This project is licensed under the **MIT License**. This is a permissive license that allows for free use, modification, and distribution. Note that it downloads various open-source and closed source components (like OSXCross and Apple's SDKs) which carry their own licenses.
