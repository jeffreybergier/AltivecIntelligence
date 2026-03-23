[![AltiveIntelligence Fun 90's Header Image](images/altivec/AltivecIntelligence-Header-Color-Quarter.png)](images/altivec/AltivecIntelligence-Header-Color-Half.png)

# 🤖 Altivec Intelligence

**Altivec Intelligence** is a specialized cross-compilation environment for
developing and deploying applications to legacy Apple systems, including PowerPC
Macs (Tiger/Leopard) and early iOS devices. On top of that, you can optionally
use Gemini to help you with your retro software development.

This is built on top of the now defunct `ppc-test` branch of the
[OSXCross](https://github.com/tpoechtrager/osxcross) toolchain, and enables
any computer that can run Docker to build and deploy to Retro Apple Devices 
with or without the use of AI.

## 🖥️ Supported Target Matrix

| Target | Compiler | SDK | Architectures | Minimum OS | Maximum OS |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Mac** | Clang 3.8.0 | 10.6 | x86_64, i386, ppc | Mac OS X 10.5 | macOS 27 (Rosetta 2) |
| **Mac (Legacy)** | Apple GCC 4.2.1 | 10.4u | ppc (32-bit) | Mac OS X 10.4 Tiger (10.3? Untested) | Mac OS X 10.6 (Rosetta) |
| **iPhone** | Clang 14.0 | 8.2 | arm64, armv7s, armv7 | iOS 4.3 | iOS 26 (Requires signature) |

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
the [`compose.yml`](compose.yml#L22) and then rerun `docker compose run --rm
altivec-intelligence`

## 🛠 Requirements

- **Docker & Docker Compose**: The entire toolchain is containerized for reproducibility.
- **Git**: Required to clone the repository.

## 📦 Installation & Usage

### 1. Install Prerequisites
- **Install Git**: If you are on a Mac, run `xcode-select --install` in your terminal. (sorry, not sure how to do on Windows)
- **Install Docker**: [Docker Desktop](https://www.docker.com/products/docker-desktop/)

### 2. Clone the Repository
Clone the project:
```bash
git clone https://github.com/your-username/AltivecIntelligence.git
cd AltivecIntelligence
```

### 3. Pre-Build

The Clang build is quite system intensive. It takes 20-60 minutes depending on
how powerful your computer is.

- Docker Resources: Settings→Resources in the Docker Desktop App
  - Confirm that Docker is allowed to use 6-8GB of RAM
  - Confirm that Docker is allowed to use all of your CPU cores (or as many as you like)
- [Job Count in ContainerFile](Containerfile#L52)
  - Confirm this is the same or less than the number of cores that Docker is allowed to use above

### 4. Build the Environment
Build the Docker image (this will take approximately 20-60 minutes as it
compiles GCC and Clang from source):
```bash
docker compose build
```

### 5. Confirm the Build System Works

There is an example project in the `example` folder. It contains 2 `main.m`
files, one for a Mac app and one for an iPhone app. These apps just set up the
interface and display a view with a red background. 

The `makefile` in this example project compiles 3 different apps:

1. X6 - Universal (x86_64, i386, ppc) any Mac running Leopard or newer
1. X4 - PowerPC binary compatible with Tiger on PowerPC, maybe compatible with Panther? But that is untested
1. i8 - Universal (arm64, armv7s, armv7) binary that will run on any iPhone running iOS 4.3 or newer

I really tried to not need the X4 binary for Tiger. I was able to get the X6 
binary to run on Tiger for Intel, but no matter how hard I tried, I could not
get it to run on Tiger for PowerPC.

To compile all of these apps at once and confirm the build system works:
```bash
docker compose run --rm altivec "cd example && make all"
```

After this, if you are running a Mac, you should be able to double click 
`Example-X6.app` and it should launch and work fine.

### 6. Deploy to your Retro Devices

Altivec Intelligence includes a script called 
[`altivec_deploy.sh`](altivec_deploy.sh) where you can deploy and test your apps
to your retro devices via SSH. If Xcode is installed on your retro Mac, this
script will dump you straight into the debugger, if you don't it will tail
the system log so you can at least see log output from your app. 

Now this script does assume you have SSH configured to work with key 
authentication. It should work without this but you may have to type in your
password 5-10 times to get it to finish executing.

```bash
docker compose run --rm altivec "./altivec_deploy.sh -td username@retro-mac.local -tp example/build/Example-X4.zip"
```
Change `username@retro-mac.local` in this script to the actual username and
IP address or Bonjour address of your retro Mac.

### 7. Boost Your Speed with Gemini

If you want to program the old fashioned way, you can end this tutorial in 
Step 6. From there the toolchain works just like a cobbled together Xcode. 
But if you want to use the AI to help you speed up your programming work, you
can boot up Gemini with the following command.

```bash
docker compose run --rm altivec-intelligence
```

After Gemini boots up and you login, I recommend always starting with the 
following prompt.

> Hello, can you read your GEMINI.md and README.md in the project? Also look at
> the example project in the example folder. After that, let me know what you
> are capable of and what you can help me with.

From there you should be able to ask GEMINI to modify the code for you, let you
know what the compile warnings are, and deploy to your systems to test your 
apps. One hint, when you quit gemini and restart type `/resume` to resume your
old session and restore the context. That will make it a lot easier to keep
going where you left off.

## 📂 Project Structure

- **`example/`**: Basic sample Mac and iPhone apps with a Makefile for cross-compilation.
- **`GEMINI.md`**: Technical guidelines and mandates for the AI programming assistant.
- **`Containerfile` / `compose.yml`**: Docker configuration for the cross-compilation environment.
- **`altivec_deploy.sh`**: Script to automate application deployment to legacy hardware via SSH.

## 🚧 Known Limitations & ToDo

- [x] **Automated Deployment**: Add scripts to automate SSH deployment to retro hardware.
- [ ] **Enable Debugging on iPhone** Add lldb and configure scripts to enable on device debugging
- [ ] **Use Within App Repos**: Provide instructions on how to embed this project in another app repo to aid in building your own apps
- [ ] **Build libcurl**: Build libcurl with this project to enable modern networking on old platforms
- [ ] **Fix dsymutil for Clang 3.8**: Resolve PowerPC target mapping to enable debug symbol generation.
- [ ] **Tiger PPC Support in Clang**: Investigate Clang 3.8 Objective-C metadata issues to allow replacing GCC 4.
- [ ] **Modern SDK Support**: Integrate macOS 10.15+ SDKs to enable Apple Silicon (M1/M2/M3) cross-compilation.

## 💬 Request for Feedback and Pull Requests

I am not an expert in build systems or compilers or even Docker. But I was able 
to cobble together this project together so I could work on my own retro apps
because of the assistance of Gemini. It took a long time, but I would not have 
been able to do it at all without help. That said, its definitely not perfect
and you may have a lot more experience with Makefiles, Compiler Linking, Docker,
etc. So if you see something that could be improved, **please file an issue 
or submit a pull request** as I am interested in improving this thing.

## 📖 Resources

- [RyPress Objective-C Tutorial](http://web.archive.org/web/20160317182651/http://rypress.com/tutorials/objective-c/index): The best Objective-C introduction I have ever found
- [Lapcat Software Blog](https://lapcatsoftware.com/articles/): A series of blog posts about how to make Mac (Part [1](https://lapcatsoftware.com/blog/2007/05/16/working-without-a-nib-part-1/), [2](https://lapcatsoftware.com/blog/2007/06/04/working-without-a-nib-part-2-also-also-wik/), 3, [4](https://lapcatsoftware.com/blog/2007/06/17/working-without-a-nib-part-4-setapplemenu/), [5](https://lapcatsoftware.com/blog/2007/07/10/working-without-a-nib-part-5-open-recent-menu/), [6](https://lapcatsoftware.com/blog/2007/11/25/working-without-a-nib-part-6-working-without-a-xib/), [7](https://lapcatsoftware.com/blog/2008/10/20/working-without-a-nib-part-7-the-empire-strikes-back/), [8](https://lapcatsoftware.com/articles/working-without-a-nib-part-8-the-nib-awakens.html), [9](https://lapcatsoftware.com/articles/working-without-a-nib-part-9-shipping.html), [10](https://lapcatsoftware.com/articles/working-without-a-nib-part-10.html), [11](https://lapcatsoftware.com/articles/working-without-a-nib-part-11.html), [12](https://lapcatsoftware.com/articles/working-without-a-nib-part-12.html))

## ⚖️ Credit and License

This project was not really built by me, but rather assembled/compiled/cobbled
together by me. So I want to make sure to give credit to the sources I used.

- [OSXCross](https://github.com/tpoechtrager/osxcross): macOS Cross-Toolchain for Linux and *BSD
- [RyPress Objective-C Tutorial](http://web.archive.org/web/20160317182651/http://rypress.com/tutorials/objective-c/index): No longer online but accessible via Archive.org.
- [Lapcat Software Blog](https://lapcatsoftware.com/articles/): This content is not embedded in the repo, but links are provided in this readme

- Gemini: No one knows how many millions of engineers' code has been training Gemini, but I thought I would call out that these tools did not come out of nowhere and the provenance of their code generation ability is questionable

This project incorporates various open-source components including OSXCross 
which is GPLv2 Licensed, so I marked this as GPLv2 License.
