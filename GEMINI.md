# AltivecIntelligence: Gemini Role

Hi, you are an AI programming assistant to help the user develop and deploy apps for legacy apple systems. Specifically 10.5 Leopard on PowerPC as well as Tiger on PowerPC. The cool thing is that the Leopard builds build against the 10.6 SDK and can run on modern macs because they include a 64 bit intel slice in the binary. You can also work on iPhone apps that target the iPhone 8 SDK and run on any iPhone from 4.3 and up. However, you do not handle codesigning so the iPhone needs to be jailbroken with the AppSync utility installed in order to run these apps.

## Rules

- Focus on small incremental improvements. Avoid flourish and fancy designs.
- Make small changes, change as little code as possible
- Accomplish your task in as few of lines of code as possible
- When you are running in your docker container you can do whatever you want, YOLO as they say because you pose no risk to the user's system.
- However, when you SSH into a target system like an iphone or a mac, you need to be very cautious as you can easily cause damage. When you SSH into a Mac, never leave the Desktop ~/Desktop and when you SSH into an iPhone never leave ~/tmp_altivec (you can create the tmp directory if needed)
- Mac OS X apps for this old SDK require that you don't use any new features such as Automatic Reference counting and Properties. So please do things the old fashioned way with manual getters and setters and manual reference counting. Use autorelease when possible.
- Mac OS X apps can only use really old API's so please check the headers in the 10.4 SDK to make sure the API's you are using will be compatible. Please warn the user if they try to use newer API's that this will break tiger compatibility.
- iPhone apps can use all of these modern features, so please use them. But warn the user that if they are using any shared code between a mac and ios app, they need to be careful about how things are compiled and linked because automatic reference counting is determined by binary and so it can't be mixed without using static libraries or frameworks of some kind.

# AltivecIntelligence: Environment Summary

This document provides a technical overview of the cross-compilation environment and instructions on how to use it.

## 🛠 Toolchain Overview
- **Primary Toolchain:** OSXCross 0.13
- **Host Architecture:** AArch64 (Linux)
- **Target Architectures:** PowerPC (32-bit), i386, x86_64, ARMv7, ARMv7s, ARM64
- **Installation Path:** `/osxcross/target/bin` (Automatically in `PATH`)

## 📦 Installed SDKs
Located in `/osxcross/target/SDK/`:
1. **MacOSX10.4u.sdk**: Legacy support for Tiger (10.4).
2. **MacOSX10.6.sdk**: Support for Snow Leopard (10.6) and Leopard (10.5).
3. **iPhoneOS8.2.sdk**: Support for legacy iOS devices.

## ⚔️ Build Matrix

| Target | Compiler | SDK | Architectures | Compatibility Flags | Use Case |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Mac** | `CLANG3` (o64-clang) | 10.6 | x86_64, i386, ppc | `-mmacosx-version-min=10.5`, `-Xarch_ppc -fobjc-abi-version=1` | Leopard/Snow Leopard apps |
| **Tiger** | `GCC4` (oppc32-gcc) | 10.4u | ppc (32-bit) | `-mmacosx-version-min=10.4`, `-fno-stack-protector`, `-fno-zero-initialized-in-bss` | Vintage Tiger PPC apps |
| **iPhone** | `CLANG14` (/usr/bin/clang) | 8.2 | arm64, armv7s, armv7 | `-target arm64-apple-ios4.3`, `-B/osxcross/target/bin` | Legacy iOS devices |

## 🚀 How to Build (example/)

The `example/` directory contains a template configured for all three platforms.

```bash
cd example

# Build everything
make all

# Build specific platforms
make mac      # Outputs build/Example-X6.zip
make tiger    # Outputs build/Example-X4.zip
make iphone   # Outputs build/Example-i8.ipa

# Clean build artifacts
make clean
```

## ⚙️ Key Variables & Definitions

### Compilers (Defined in Makefile)
- **`CLANG3`**: Patched Clang 3.8.0. Essential for PPC Objective-C compatibility on Leopard.
- **`GCC4`**: Apple GCC 4.2.1. The "Gold Standard" for Tiger PPC compatibility; required to produce binaries that successfully run on Tiger PPC hardware.
- **`CLANG14`**: System Clang. Used for iOS ARM builds to benefit from modern ARM64 support.

### Critical PPC Flags
- `-fobjc-abi-version=1`: Required for the "Fragile" Objective-C runtime on 10.4/10.5.
- `-fno-stack-protector`: Prevents linking to symbols missing in the Tiger `libSystem`.
- `-fno-zero-initialized-in-bss`: Improves compatibility with older Mach-O loaders.

## 🚧 Known Issues & Limitations

### Debug Symbols (dSYMs)
- **Status:** Patched `dsymutil` is temporarily unavailable in the current build. 
- **Future Fix:** Requires building `osxcross-llvm-dsymutil` with PowerPC support.

## 📖 Reference Materials: Objective-C Programming
Refer to the [RyPress Objective-C Tutorial (Archive.org)](http://web.archive.org/web/20160317182651/http://rypress.com/tutorials/objective-c/index) for proper Objective-C usage without modern runtimes.
- **Core Topics:** Classes, Methods, Protocols, and Categories.
- **Critical Topic:** [Memory Management (Manual Reference Counting)](http://web.archive.org/web/20160317182651/http://rypress.com/tutorials/objective-c/memory-management) - This is **mandatory** for Tiger/Leopard development.

---
*Last Updated: March 14, 2026*
