# Altivec Intelligence FAQ

## AI Questions

### Do I have to use AI?
No, the AI container is built on top of the build system container. So you can
just use the build system container called `altivec` and not use any AI. See
the quick start guide for commands on how to use it without AI.

### I have moral and/or ethical objections to using LLM technology
Then please don't use it. The quick start guide for commands on how to use it 
without AI.

### If I have no software development experience can I make apps?
I really think have software development background helps with guiding the AI.
That said, I want you to try. Even if the code is not good, if the app works
for you, then it works for you and you should feel extremely accomplished.

### I want to use a different AI
Go for it, just tell your AI to read the compose file and it will easily be 
able to run commands inside the docker container from your hose computer.

### The AI keeps changing things when I just ask it questions
This is one of my biggest annoyances with Gemini. I often want its opinions
before deciding how to move forward with changes. My suggestion is to change
your prompt:

```
Do not change any code, I just want to know your top 3 options for how I should
do X
```

### The AI keeps overwriting my changes
This is one of my biggest annoyances with Gemini. If I change a file manually,
Gemini will often happily overwrite me changes. My suggestion is to change your
prompt:

```
I updated some files manually because its the style I want. Can you check to
sure I did not break anything?
```

## Safety Questions

### Why did you include AI in the Container?
I don't like installing developer tools (aside from Xcode) on my Mac. So whether
I am working with NPM, Ruby, Python, etc, I always containerize the development
environment so I do not have to remember how I set up my Mac to build and run
the app. For this reason, I also do that with AI. I always run Gemini in a container so
it does not have access to my personal files and data.

### Is it safe to run this AI tool?
Yes, the environment is containerized within Docker. The AI only has access to
the files within the container and the specific repository you are working in.
It cannot access your personal files on your host machine.

### What about SSH access?
SSH access is disabled by default for security. If you choose to enable it (by
uncommenting the line in `compose.yml`), the AI can theoretically access any
system your SSH keys have access to. **Use this feature with caution.**

## Objective-C Questions

### My Project is Full of Errors and Warnings!
When targeting these old platforms you have a basic lowest common denominator 
problem. Meaning you can only use API's that were available in the lowest system
you want target. When Altivec builds the different slices of the Mac app, it
outputs the warnings from that compiler.

In general, deprecation warnings from newer SDK's is OK. These deprecated 
functions work fine. But if you see warnings about "'Foo' may not respond to 
selector 'Bar'" then you will likely experience a crash when you run on an old
system. So please remove those.

You can ask Gemini

```
Can you rebuild the app and summarize all the warnings for me? You can ignore
deprecation warnings for now.
```

### Where can I learn about programming legacy Objective-C?
I recommend the following resources:
- [RyPress Objective-C (Manual Memory Management)](http://web.archive.org/web/20160317182651/http://rypress.com/tutorials/objective-c/index)
- [Lapcat Software Blog](https://lapcatsoftware.com/articles/): A series of blog posts about how to make Mac apps without a NIB (Part [1](https://lapcatsoftware.com/blog/2007/05/16/working-without-a-nib-part-1/), [2](https://lapcatsoftware.com/blog/2007/06/04/working-without-a-nib-part-2-also-also-wik/), [3](https://lapcatsoftware.com/blog/2007/06/10/working-without-a-nib-part-5-no-3/), [4](https://lapcatsoftware.com/blog/2007/06/17/working-without-a-nib-part-4-setapplemenu/), [5](https://lapcatsoftware.com/blog/2007/07/10/working-without-a-nib-part-5-open-recent-menu/), [6](https://lapcatsoftware.com/blog/2007/11/25/working-without-a-nib-part-6-working-without-a-xib/), [7](https://lapcatsoftware.com/blog/2008/10/20/working-without-a-nib-part-7-the-empire-strikes-back/), [8](https://lapcatsoftware.com/articles/working-without-a-nib-part-8-the-nib-awakens.html), [9](https://lapcatsoftware.com/articles/working-without-a-nib-part-9-shipping.html), [10](https://lapcatsoftware.com/articles/working-without-a-nib-part-10.html), [11](https://lapcatsoftware.com/articles/working-without-a-nib-part-11.html), [12](https://lapcatsoftware.com/articles/working-without-a-nib-part-12.html))

### What architectures and SDKs are supported?

See the table below to understand the compilers and SDK's used:

| Target | Compiler | SDK | Architectures | Compatibility |
| :--- | :--- | :--- | :--- | :--- |
| **Mac (Intel, PowerPC)** | Apple GCC 4.2.1 | 10.6 + 10.5 Hybrid | ppc, x86, x64 | 10.4 Tiger |
| **Mac (Apple Silicon)** | Clang 14 | 11.3 | arm64 | 11.0 Big Sur |
| **iPhone** | Clang 14.0 | 8.4 | armv7, arm64 | iPhone 3GS+ iOS 4.3+ |

Even though the Mac version uses 2 compilers and 2 SDK's, it combines them into
one application binary with the lipo command. In the future, I want to change to
actually use 3 SDK's for the Mac version, but that is in the To-Do list for now.

## Project Origins

### Why was this project built?
Developing for legacy systems is often tedious, requiring slow virtual machines
and manual memory management. This project was created to provide a portable,
fast cross-compilation environment that allows you to build for everything from
Tiger PPC to modern Apple Silicon in one place.

### Why use AI for retro development?
While modern Objective-C and Swift provide "syntactic sugar" (like ARC and
Properties) that makes development easier for humans, AI is perfectly capable of
handling the verbosity of manual `[retain]` and `[release]` calls. This allows
developers to focus on features while the AI manages the boilerplate of older
runtimes.

