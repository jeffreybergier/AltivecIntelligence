# Problems

## cctools signs non-signable Mach-O outputs

- [ ] Prevent the cctools post-processing hook from invoking `ldid` for
  relocatable Mach-O objects.

  - `ld -r` successfully creates a valid `MH_OBJECT` and exits with status 0,
    but prints `ldid: Unsupported Mach-O type`.
  - `bitcode_strip` exhibits the same behavior.
  - The current workaround is to run these commands with `NO_LDID=1`.

## C++ standard-library headers are missing

- [ ] Package usable C++ standard-library headers and configure Clang to select
  the intended standard library by default.

  - `clang++` and `c++` can compile C++ code that does not use the standard
    library.
  - Compiling `#include <vector>` with `-stdlib=libc++` fails because the header
    is not installed.
  - Without `-stdlib=libc++`, Clang warns that the libstdc++ include path is
    missing.

## Git CVS server is an unsupported stub

- [ ] Decide whether to include Perl support for `git-cvsserver` or omit the
  unsupported command from the package.

  - The installed command exits with status 128 and reports that Git was built
    with `NO_PERL=YesPlease`.

## ImageMagick GUI commands require unavailable X11 support

- [ ] Decide whether to add X11 support for `animate`, `display`, and `import`
  or omit those command aliases from the CLI-only package.

  - The commands load and print their version correctly.
  - Actual GUI operation fails because no X11 delegate/server is available on
    the phone.
