# Cocoa application conventions

- The iOS deployment target is 5.0 and must match `MinimumOSVersion` in
  `source/iOS/Info.plist`.
- Put portable C and cross-platform resources under `source/shared`.
- Put UIKit code and iPhone-only artwork under `source/iOS`.
- Write Cocoa integration in Objective-C and portable logic in C. Do not add
  Swift.
- Use bracketed Objective-C message syntax rather than dot syntax.
- Keep localized strings under `source/shared/Resources/<locale>.lproj`.
- The required static launch-image matrix and matching plist entries are
  already present. Keep them unless the product deliberately changes its
  launch artwork; use `tools/generate-launch-images.sh` for replacements.
- The plain white app icons are development placeholders and must be replaced
  before shipping.
- Run `make clean`, `make analyze`, and `make release` from the repository root
  after changing source, metadata, resources, or build declarations.
- Do not install or launch the application unless the user explicitly asks.
