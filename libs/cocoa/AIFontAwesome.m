#import "AIFontAwesome.h"
#import <math.h>
#import <stdarg.h>

#if !__LP64__ && !TARGET_OS_IPHONE
#import <CoreServices/CoreServices.h> /* Gestalt — 10.4-capable build only */
#endif

#if TARGET_OS_IPHONE
  #import <CoreText/CoreText.h>
  #import <UIKit/UIKit.h> /* iOS-only UIFont/UIImage convenience (guarded) */
#else
  #import <ApplicationServices/ApplicationServices.h>
  #import <AppKit/AppKit.h> /* macOS-only NSImage convenience (guarded) */
#endif

/* Internal primitive — deliberately not in AIFontAwesome.h. Glyph -> square
 * CGImage; caller owns the +1 result and MUST CGImageRelease it. */
@interface AIFontAwesome ()
+ (CGImageRef)_newImageForCodePoint:(uint32_t)codePoint
                              style:(AIFontAwesomeStyle)style
                           iconSize:(CGFloat)iconSize
                         canvasSize:(CGFloat)canvasSize
                               fill:(CGColorRef)fill
                              scale:(CGFloat)scale;
@end

static void AIFALog(NSString *tag, NSString *format, ...)
{
  va_list ap;
  NSString *message;
  va_start(ap, format);
  message = [[[NSString alloc] initWithFormat:format
                                    arguments:ap] autorelease];
  va_end(ap);
  NSLog(@"[%@] %@", tag, message);
}

/* PostScript names from each bundled OTF's name table. */
static NSString *ai_fa_postscript_name(AIFontAwesomeStyle style)
{
  switch (style) {
    case AIFontAwesomeStyleSolid:
      return @"FontAwesome7Free-Solid";
    case AIFontAwesomeStyleRegular:
      return @"FontAwesome7Free-Regular";
    case AIFontAwesomeStyleBrands:
      return @"FontAwesome7Brands-Regular";
  }
  [NSException raise:NSInvalidArgumentException
              format:@"[AIFontAwesome] unknown style %d", (int)style];
  return nil;
}

static NSString *ai_fa_file_name(AIFontAwesomeStyle style)
{
  switch (style) {
    case AIFontAwesomeStyleSolid:
      return @"FA7-Solid-900.otf";
    case AIFontAwesomeStyleRegular:
      return @"FA7-Regular-400.otf";
    case AIFontAwesomeStyleBrands:
      return @"FA7-Brands-400.otf";
  }
  [NSException raise:NSInvalidArgumentException
              format:@"[AIFontAwesome] unknown style %d", (int)style];
  return nil;
}

static NSString *ai_fa_path_in_bundle(NSBundle *bundle, NSString *name)
{
  NSString *path;
  if (!bundle) return nil;
  path = [bundle pathForResource:name ofType:nil inDirectory:@"Fonts"];
  if (!path)
    path = [bundle pathForResource:name ofType:nil
                       inDirectory:@"Resources/Fonts"];
  return path;
}

static NSString *ai_fa_required_font_path(NSString *name)
{
  NSBundle *classBundle = [NSBundle bundleForClass:[AIFontAwesome class]];
  NSBundle *mainBundle = [NSBundle mainBundle];
  NSString *path = ai_fa_path_in_bundle(classBundle, name);
  if (!path && mainBundle != classBundle)
    path = ai_fa_path_in_bundle(mainBundle, name);
  if (!path) {
    [NSException raise:NSInternalInconsistencyException
                format:@"AIFontAwesome missing bundled font file %@", name];
  }
  return path;
}

static NSString *ai_fa_font_path(AIFontAwesomeStyle style)
{
  return ai_fa_required_font_path(ai_fa_file_name(style));
}

#if !__LP64__ && !TARGET_OS_IPHONE
static BOOL ai_fa_activate_ats_font(AIFontAwesomeStyle style)
{
  static BOOL solidTried = NO;
  static BOOL regularTried = NO;
  static BOOL brandsTried = NO;
  static NSData *solidData = nil;
  static NSData *regularData = nil;
  static NSData *brandsData = nil;
  static ATSFontContainerRef solidContainer = 0;
  static ATSFontContainerRef regularContainer = 0;
  static ATSFontContainerRef brandsContainer = 0;
  BOOL *tried = &solidTried;
  NSData **dataSlot = &solidData;
  ATSFontContainerRef *container = &solidContainer;

  switch (style) {
    case AIFontAwesomeStyleRegular:
      tried = &regularTried;
      dataSlot = &regularData;
      container = &regularContainer;
      break;
    case AIFontAwesomeStyleBrands:
      tried = &brandsTried;
      dataSlot = &brandsData;
      container = &brandsContainer;
      break;
    case AIFontAwesomeStyleSolid:
      break;
  }

  if (*tried) return (*container != 0);

  NSString *path = ai_fa_font_path(style);
  *tried = YES;
  *dataSlot = [[NSData alloc] initWithContentsOfFile:path];
  if (!*dataSlot) {
    AIFALog(@"AIFontAwesome.ats", @"cannot read %@", [path lastPathComponent]);
    return NO;
  }

  OSStatus err = ATSFontActivateFromMemory(
      (LogicalAddress)[(*dataSlot) bytes],
      (ByteCount)[(*dataSlot) length],
      kATSFontContextLocal,
      kATSFontFormatUnspecified,
      NULL,
      kATSOptionFlagsDefault,
      container);
  if (err != noErr) {
    AIFALog(@"AIFontAwesome.ats", @"activate %@ failed: %d",
            [path lastPathComponent], (int)err);
    [*dataSlot release];
    *dataSlot = nil;
    *container = 0;
    return NO;
  }
  return YES;
}
#endif

static CGContextRef ai_fa_make_context(size_t px, CGColorRef fill)
{
  CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
  if (!cs) return NULL;
  CGContextRef ctx = CGBitmapContextCreate(NULL, px, px, 8, 0, cs,
      (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
  CGColorSpaceRelease(cs);
  if (!ctx) {
    AIFALog(@"AIFontAwesome.make_context", @"CGBitmapContextCreate failed (%lu px)",
          (unsigned long)px);
    return NULL;
  }
  /* The glyph rasterises in the context fill color. `fill` NULL keeps the
   * historical opaque-black template (the caller tints: template image on
   * AppKit, tintColor on UIKit); a non-NULL color bakes the tint in directly,
   * so no second mask-and-fill pass is needed. */
  if (fill) {
    CGContextSetFillColorWithColor(ctx, fill);
  } else {
    CGContextSetRGBFillColor(ctx, 0.0, 0.0, 0.0, 1.0);
  }
  return ctx;
}

static int ai_fa_to_utf16(uint32_t cp, UniChar out[2])
{
  if (cp <= 0xFFFF) { out[0] = (UniChar)cp; return 1; }
  cp -= 0x10000;
  out[0] = (UniChar)(0xD800 + (cp >> 10));
  out[1] = (UniChar)(0xDC00 + (cp & 0x3FF));
  return 2;
}

/* `glyphPx` is the rasterised glyph size (the font size); `canvasPx` is the
 * square bitmap it is centred inside. They are equal for a tight icon and
 * differ when the caller wants padding (e.g. a 24pt glyph in a 32pt toolbar
 * slot so NSToolbar draws the image 1:1 instead of rescaling it). */
static BOOL ai_fa_draw_coretext(CGContextRef ctx, uint32_t cp,
                                CGFloat canvasPx, CGFloat glyphPx,
                                NSString *psname,
                                AIFontAwesomeStyle style)
{
#if __LP64__ || TARGET_OS_IPHONE
  (void)style;
#endif
  /* CTFontCreateWithName's name resolution crashes inside TFont::SetMatrix
   * on Leopard 10.5 (EXC_BAD_ACCESS). Go through CGFont instead: create the
   * CGFont by PostScript name, build the CTFont from it purely for Unicode
   * -> glyph mapping + metrics, and reuse the same CGFont to draw. */
  CGFontRef cgFont = CGFontCreateWithFontName((CFStringRef)psname);
#if !__LP64__ && !TARGET_OS_IPHONE
  if (!cgFont) {
    ATSFontRef atsFont = ATSFontFindFromPostScriptName(
        (CFStringRef)psname, kATSOptionFlagsDefault);
    if (atsFont == (ATSFontRef)kATSFontRefUnspecified) {
      (void)ai_fa_activate_ats_font(style);
      atsFont = ATSFontFindFromPostScriptName(
          (CFStringRef)psname, kATSOptionFlagsDefault);
    }
    if (atsFont != (ATSFontRef)kATSFontRefUnspecified) {
      cgFont = CGFontCreateWithPlatformFont(&atsFont);
    }
  }
#endif
  if (!cgFont) {
    AIFALog(@"AIFontAwesome.coretext", @"font '%@' unavailable", psname);
    return NO;
  }
  CTFontRef font = CTFontCreateWithGraphicsFont(cgFont, glyphPx, NULL, NULL);
  if (!font) {
    AIFALog(@"AIFontAwesome.coretext", @"CTFontCreateWithGraphicsFont failed");
    CGFontRelease(cgFont);
    return NO;
  }

  UniChar u16[2];
  CFIndex n = ai_fa_to_utf16(cp, u16);
  CGGlyph g[2] = { 0, 0 };
  if (!CTFontGetGlyphsForCharacters(font, u16, g, n) || g[0] == 0) {
    AIFALog(@"AIFontAwesome.coretext", @"no glyph for U+%04X", cp);
    CFRelease(font);
    CGFontRelease(cgFont);
    return NO;
  }

  /* 0 == default orientation on both the 10.5 and modern enums; passing the
   * literal avoids the renamed/deprecated symbol mismatch across SDKs. */
  CGRect bb = CTFontGetBoundingRectsForGlyphs(font, (CTFontOrientation)0,
                                              g, NULL, 1);
  CFRelease(font);
  CGPoint pos = CGPointMake((canvasPx - bb.size.width) / 2.0 - bb.origin.x,
                            (canvasPx - bb.size.height) / 2.0 - bb.origin.y);

  /* CTFontDrawGlyphs is 10.7+ (absent in the 10.5 SDK). The CGFont glyph-
   * show route works from 10.5 through modern; the localized pragma silences
   * its post-10.9 deprecation so the all-arch build stays warning-clean. */
#ifdef __clang__
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
  CGContextSetFont(ctx, cgFont);
  CGContextSetFontSize(ctx, glyphPx);
  CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
  CGContextShowGlyphsAtPoint(ctx, pos.x, pos.y, g, 1);
#ifdef __clang__
#pragma clang diagnostic pop
#endif
  CGFontRelease(cgFont);
  return YES;
}

#if !__LP64__ && !TARGET_OS_IPHONE
/* Genuine Tiger 10.4 path: Core Text is absent, so lay the single character
 * out with ATSUI directly into the CGContext. 32-bit macOS only — ATSUI exists
 * on neither 64-bit macOS (always >= 10.9, always Core Text) nor iOS (always
 * Core Text, and no ATSUI/Gestalt at all); both route to Core Text below. */
static BOOL ai_fa_draw_atsui(CGContextRef ctx, uint32_t cp,
                             CGFloat canvasPx, CGFloat glyphPx,
                             NSString *psname)
{
  if (cp > 0xFFFF) return NO; /* Font Awesome is entirely BMP */
  UniChar u = (UniChar)cp;

  ATSFontRef af = ATSFontFindFromPostScriptName(
      (CFStringRef)psname, kATSOptionFlagsDefault);
  if (af == (ATSFontRef)kATSFontRefUnspecified) {
    AIFALog(@"AIFontAwesome.atsui", @"font '%@' unavailable", psname);
    return NO;
  }
  ATSUFontID fid = FMGetFontFromATSFontRef(af);
  if (fid == 0) return NO;

  ATSUStyle atsuStyle = NULL;
  if (ATSUCreateStyle(&atsuStyle) != noErr || !atsuStyle) return NO;

  Fixed size = X2Fix((double)glyphPx);
  ATSUAttributeTag      tag[2]  = { kATSUFontTag, kATSUSizeTag };
  ByteCount             tsz[2]  = { sizeof(ATSUFontID), sizeof(Fixed) };
  ATSUAttributeValuePtr tval[2] = { &fid, &size };
  if (ATSUSetAttributes(atsuStyle, 2, tag, tsz, tval) != noErr) {
    ATSUDisposeStyle(atsuStyle);
    return NO;
  }

  ATSUTextLayout layout = NULL;
  UniCharCount runLen = 1;
  if (ATSUCreateTextLayoutWithTextPtr(&u, 0, 1, 1, 1, &runLen,
                                      &atsuStyle, &layout) != noErr ||
      !layout) {
    ATSUDisposeStyle(atsuStyle);
    return NO;
  }

  ATSUAttributeTag      ltag[1] = { kATSUCGContextTag };
  ByteCount             lsz[1]  = { sizeof(CGContextRef) };
  ATSUAttributeValuePtr lval[1] = { &ctx };
  ATSUSetLayoutControls(layout, 1, ltag, lsz, lval);

  Rect box;
  OSStatus mErr = ATSUMeasureTextImage(layout, 0, 1, 0, 0, &box);
  double gw = (mErr == noErr) ? (box.right - box.left) : glyphPx;
  double gh = (mErr == noErr) ? (box.bottom - box.top) : glyphPx;
  Fixed x = X2Fix((canvasPx - gw) / 2.0 - (mErr == noErr ? box.left : 0));
  Fixed y = X2Fix((canvasPx - gh) / 2.0 + (mErr == noErr ? box.bottom : 0));
  OSStatus dErr = ATSUDrawText(layout, 0, 1, x, y);

  ATSUDisposeTextLayout(layout);
  ATSUDisposeStyle(atsuStyle);
  return (dErr == noErr);
}
#endif

/* Core Text is 10.5+. Neither `&CTFn != NULL` nor dlsym() can tell 10.4 from
 * 10.5 here: this toolchain binds the referenced CT symbols through lazy
 * stubs that our own binary carries, so both report "present" on Tiger and
 * the call then jumps to 0x0. Gate on the actual OS version instead — Gestalt
 * is reliable on 10.4 and the CT path is simply never *called* on Tiger, so
 * its stubs never resolve. Only the 32-bit (10.4-capable) build needs this;
 * 64-bit is always >= 10.9. */
#if !__LP64__ && !TARGET_OS_IPHONE
static int ai_fa_have_coretext(void)
{
  static int cached = -1;
  if (cached < 0) {
    SInt32 v = 0;
    cached = (Gestalt(gestaltSystemVersion, &v) == noErr && v >= 0x1050)
             ? 1 : 0;
  }
  return cached;
}
#endif

/* Keep this embedded copy identical to
 * Resources/Fonts/LICENSE-Font-Awesome.txt. */
static NSString *const kAIFontAwesomeLicenseText =
  @"Fonticons, Inc. (https://fontawesome.com)\n"
  @"\n"
  @"----------------------------------------------------------------------"
  @"----------\n"
  @"\n"
  @"Font Awesome Free License\n"
  @"\n"
  @"Font Awesome Free is free, open source, and GPL friendly. You can use "
  @"it for\n"
  @"commercial projects, open source projects, or really almost whatever y"
  @"ou want.\n"
  @"Full Font Awesome Free license: https://fontawesome.com/license/free.\n"
  @"\n"
  @"----------------------------------------------------------------------"
  @"----------\n"
  @"\n"
  @"# Icons: CC BY 4.0 License (https://creativecommons.org/licenses/by/4."
  @"0/)\n"
  @"\n"
  @"The Font Awesome Free download is licensed under a Creative Commons\n"
  @"Attribution 4.0 International License and applies to all icons package"
  @"d\n"
  @"as SVG and JS file types.\n"
  @"\n"
  @"----------------------------------------------------------------------"
  @"----------\n"
  @"\n"
  @"# Fonts: SIL OFL 1.1 License\n"
  @"\n"
  @"In the Font Awesome Free download, the SIL OFL license applies to all "
  @"icons\n"
  @"packaged as web and desktop font files.\n"
  @"\n"
  @"Copyright (c) 2026 Fonticons, Inc. (https://fontawesome.com)\n"
  @"with Reserved Font Name: \"Font Awesome\".\n"
  @"\n"
  @"This Font Software is licensed under the SIL Open Font License, Versio"
  @"n 1.1.\n"
  @"This license is copied below, and is also available with a FAQ at:\n"
  @"http://scripts.sil.org/OFL\n"
  @"\n"
  @"SIL OPEN FONT LICENSE\n"
  @"Version 1.1 - 26 February 2007\n"
  @"\n"
  @"PREAMBLE\n"
  @"The goals of the Open Font License (OFL) are to stimulate worldwide\n"
  @"development of collaborative font projects, to support the font creati"
  @"on\n"
  @"efforts of academic and linguistic communities, and to provide a free "
  @"and\n"
  @"open framework in which fonts may be shared and improved in partnershi"
  @"p\n"
  @"with others.\n"
  @"\n"
  @"The OFL allows the licensed fonts to be used, studied, modified and\n"
  @"redistributed freely as long as they are not sold by themselves. The\n"
  @"fonts, including any derivative works, can be bundled, embedded,\n"
  @"redistributed and/or sold with any software provided that any reserved"
  @"\n"
  @"names are not used by derivative works. The fonts and derivatives,\n"
  @"however, cannot be released under any other type of license. The\n"
  @"requirement for fonts to remain under this license does not apply\n"
  @"to any document created using the fonts or their derivatives.\n"
  @"\n"
  @"DEFINITIONS\n"
  @"\"Font Software\" refers to the set of files released by the Copyright\n"
  @"Holder(s) under this license and clearly marked as such. This may\n"
  @"include source files, build scripts and documentation.\n"
  @"\n"
  @"\"Reserved Font Name\" refers to any names specified as such after the\n"
  @"copyright statement(s).\n"
  @"\n"
  @"\"Original Version\" refers to the collection of Font Software component"
  @"s as\n"
  @"distributed by the Copyright Holder(s).\n"
  @"\n"
  @"\"Modified Version\" refers to any derivative made by adding to, deletin"
  @"g,\n"
  @"or substituting — in part or in whole — any of the components of the\n"
  @"Original Version, by changing formats or by porting the Font Software "
  @"to a\n"
  @"new environment.\n"
  @"\n"
  @"\"Author\" refers to any designer, engineer, programmer, technical\n"
  @"writer or other person who contributed to the Font Software.\n"
  @"\n"
  @"PERMISSION & CONDITIONS\n"
  @"Permission is hereby granted, free of charge, to any person obtaining\n"
  @"a copy of the Font Software, to use, study, copy, merge, embed, modify"
  @",\n"
  @"redistribute, and sell modified and unmodified copies of the Font\n"
  @"Software, subject to the following conditions:\n"
  @"\n"
  @"1) Neither the Font Software nor any of its individual components,\n"
  @"in Original or Modified Versions, may be sold by itself.\n"
  @"\n"
  @"2) Original or Modified Versions of the Font Software may be bundled,\n"
  @"redistributed and/or sold with any software, provided that each copy\n"
  @"contains the above copyright notice and this license. These can be\n"
  @"included either as stand-alone text files, human-readable headers or\n"
  @"in the appropriate machine-readable metadata fields within text or\n"
  @"binary files as long as those fields can be easily viewed by the user."
  @"\n"
  @"\n"
  @"3) No Modified Version of the Font Software may use the Reserved Font\n"
  @"Name(s) unless explicit written permission is granted by the correspon"
  @"ding\n"
  @"Copyright Holder. This restriction only applies to the primary font na"
  @"me as\n"
  @"presented to the users.\n"
  @"\n"
  @"4) The name(s) of the Copyright Holder(s) or the Author(s) of the Font"
  @"\n"
  @"Software shall not be used to promote, endorse or advertise any\n"
  @"Modified Version, except to acknowledge the contribution(s) of the\n"
  @"Copyright Holder(s) and the Author(s) or with their explicit written\n"
  @"permission.\n"
  @"\n"
  @"5) The Font Software, modified or unmodified, in part or in whole,\n"
  @"must be distributed entirely under this license, and must not be\n"
  @"distributed under any other license. The requirement for fonts to\n"
  @"remain under this license does not apply to any document created\n"
  @"using the Font Software.\n"
  @"\n"
  @"TERMINATION\n"
  @"This license becomes null and void if any of the above conditions are\n"
  @"not met.\n"
  @"\n"
  @"DISCLAIMER\n"
  @"THE FONT SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND,\n"
  @"EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO ANY WARRANTIES OF\n"
  @"MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT\n"
  @"OF COPYRIGHT, PATENT, TRADEMARK, OR OTHER RIGHT. IN NO EVENT SHALL THE"
  @"\n"
  @"COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,\n"
  @"INCLUDING ANY GENERAL, SPECIAL, INDIRECT, INCIDENTAL, OR CONSEQUENTIAL"
  @"\n"
  @"DAMAGES, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING\n"
  @"FROM, OUT OF THE USE OR INABILITY TO USE THE FONT SOFTWARE OR FROM\n"
  @"OTHER DEALINGS IN THE FONT SOFTWARE.\n"
  @"\n"
  @"----------------------------------------------------------------------"
  @"----------\n"
  @"\n"
  @"# Code: MIT License (https://opensource.org/licenses/MIT)\n"
  @"\n"
  @"In the Font Awesome Free download, the MIT license applies to all non-"
  @"font and\n"
  @"non-icon files.\n"
  @"\n"
  @"Copyright 2026 Fonticons, Inc.\n"
  @"\n"
  @"Permission is hereby granted, free of charge, to any person obtaining "
  @"a copy of\n"
  @"this software and associated documentation files (the \"Software\"), to "
  @"deal in the\n"
  @"Software without restriction, including without limitation the rights "
  @"to use, copy,\n"
  @"modify, merge, publish, distribute, sublicense, and/or sell copies of "
  @"the Software,\n"
  @"and to permit persons to whom the Software is furnished to do so, subj"
  @"ect to the\n"
  @"following conditions:\n"
  @"\n"
  @"The above copyright notice and this permission notice shall be include"
  @"d in all\n"
  @"copies or substantial portions of the Software.\n"
  @"\n"
  @"THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRES"
  @"S OR IMPLIED,\n"
  @"INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNES"
  @"S FOR A\n"
  @"PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS "
  @"OR COPYRIGHT\n"
  @"HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER I"
  @"N AN ACTION\n"
  @"OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION "
  @"WITH THE\n"
  @"SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.\n"
  @"\n"
  @"----------------------------------------------------------------------"
  @"----------\n"
  @"\n"
  @"# Attribution\n"
  @"\n"
  @"Attribution is required by MIT, SIL OFL, and CC BY licenses. Downloade"
  @"d Font\n"
  @"Awesome Free files already contain embedded comments with sufficient\n"
  @"attribution, so you shouldn't need to do anything additional when usin"
  @"g these\n"
  @"files normally.\n"
  @"\n"
  @"We've kept attribution comments terse, so we ask that you do not activ"
  @"ely work\n"
  @"to remove them from files, especially code. They're a great way for fo"
  @"lks to\n"
  @"learn about Font Awesome.\n"
  @"\n"
  @"----------------------------------------------------------------------"
  @"----------\n"
  @"\n"
  @"# Brand Icons\n"
  @"\n"
  @"All brand icons are trademarks of their respective owners. The use of "
  @"these\n"
  @"trademarks does not indicate endorsement of the trademark holder by Fo"
  @"nt\n"
  @"Awesome, nor vice versa. **Please do not use brand logos for any purpo"
  @"se except\n"
  @"to represent the company, product, or service to which they refer.**\n";

@implementation AIFontAwesome

+ (NSString *)fontAwesomeLicenseText;
{
  return kAIFontAwesomeLicenseText;
}

+ (NSString *)solidFontPath;
{
  return ai_fa_required_font_path(@"FA7-Solid-900.otf");
}

+ (NSString *)regularFontPath;
{
  return ai_fa_required_font_path(@"FA7-Regular-400.otf");
}

+ (NSString *)brandsFontPath;
{
  return ai_fa_required_font_path(@"FA7-Brands-400.otf");
}

+ (NSString *)fontPathForStyle:(AIFontAwesomeStyle)style;
{
  return ai_fa_font_path(style);
}

+ (CGImageRef)_newImageForCodePoint:(uint32_t)codePoint
                              style:(AIFontAwesomeStyle)style
                           iconSize:(CGFloat)iconSize
                         canvasSize:(CGFloat)canvasSize
                               fill:(CGColorRef)fill
                              scale:(CGFloat)scale
{
  if (codePoint == 0 || iconSize <= 0.0 || canvasSize < iconSize ||
      scale <= 0.0) {
    AIFALog(@"AIFontAwesome._newImageForCodePoint", @"invalid args cp=%u "
          @"icon=%g canvas=%g scale=%g",
          codePoint, iconSize, canvasSize, scale);
    return NULL;
  }

  size_t canvasPx = (size_t)ceil(canvasSize * scale);
  CGFloat glyphPx = (CGFloat)ceil(iconSize * scale);
  if (canvasPx == 0 || glyphPx <= 0.0) return NULL;

  CGContextRef ctx = ai_fa_make_context(canvasPx, fill);
  if (!ctx) return NULL;

  NSString *psname = ai_fa_postscript_name(style);
  BOOL ok;
#if __LP64__ || TARGET_OS_IPHONE
  ok = ai_fa_draw_coretext(ctx, codePoint, (CGFloat)canvasPx, glyphPx, psname,
                           style);
#else
  if (ai_fa_have_coretext()) {
    ok = ai_fa_draw_coretext(ctx, codePoint, (CGFloat)canvasPx,
                                  glyphPx, psname, style);
  } else {
    ok = ai_fa_draw_atsui(ctx, codePoint, (CGFloat)canvasPx,
                               glyphPx, psname);
  }
#endif

  CGImageRef img = ok ? CGBitmapContextCreateImage(ctx) : NULL;
  CGContextRelease(ctx);
  return img;
}

#if !TARGET_OS_IPHONE
+ (NSImage *)imageForCodePoint:(uint32_t)codePoint
                     pointSize:(CGFloat)pointSize
                         scale:(CGFloat)scale
{
  return [self imageForCodePoint:codePoint
                           style:AIFontAwesomeStyleSolid
                        iconSize:pointSize
                      canvasSize:pointSize
                           scale:scale];
}

+ (NSImage *)imageForCodePoint:(uint32_t)codePoint
                         style:(AIFontAwesomeStyle)style
                     pointSize:(CGFloat)pointSize
                         scale:(CGFloat)scale
{
  return [self imageForCodePoint:codePoint
                           style:style
                        iconSize:pointSize
                      canvasSize:pointSize
                           scale:scale];
}

+ (NSImage *)imageForCodePoint:(uint32_t)codePoint
                         style:(AIFontAwesomeStyle)style
                      iconSize:(CGFloat)iconSize
                    canvasSize:(CGFloat)canvasSize
                         scale:(CGFloat)scale
{
  CGImageRef cg = [self _newImageForCodePoint:codePoint
                                        style:style
                                     iconSize:iconSize
                                   canvasSize:canvasSize
                                         fill:NULL
                                        scale:scale];
  if (!cg) return nil;

  /* Logical size is the canvas in points; the CGImage carries
   * canvasSize*scale pixels (crisp on HiDPI). NSToolbar draws an image at its
   * logical size, so sizing the canvas to the toolbar slot and the glyph
   * smaller yields an exactly-positioned icon with no toolbar rescaling.
   * -[NSImage initWithCGImage:] is 10.6+, so wrap the Tiger-safe way:
   * lockFocus + CGContextDrawImage into the focused context. */
  NSImage *img = [[[NSImage alloc]
    initWithSize:NSMakeSize(canvasSize, canvasSize)] autorelease];
  [img lockFocus];
#ifdef __clang__
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
  CGContextRef c =
    (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
#ifdef __clang__
#pragma clang diagnostic pop
#endif
  CGContextDrawImage(c, CGRectMake(0, 0, canvasSize, canvasSize), cg);
  [img unlockFocus];
  CGImageRelease(cg);

  /* The glyph is opaque black on a transparent canvas — exactly a template
   * image. -[NSImage setTemplate:] is 10.5+; guard for Tiger 10.4. */
  if ([img respondsToSelector:@selector(setTemplate:)]) {
    [img setTemplate:YES];
  }
  return img;
}

+ (NSImage *)imageForIcon:(AIFontAwesomeIcon)icon
                pointSize:(CGFloat)pointSize
                    scale:(CGFloat)scale
{
  return [self imageForCodePoint:(uint32_t)icon
                           style:AIFontAwesomeStyleSolid
                       pointSize:pointSize
                           scale:scale];
}

+ (NSImage *)imageForIcon:(AIFontAwesomeIcon)icon
                    style:(AIFontAwesomeStyle)style
                pointSize:(CGFloat)pointSize
                    scale:(CGFloat)scale
{
  return [self imageForCodePoint:(uint32_t)icon
                           style:style
                       pointSize:pointSize
                           scale:scale];
}

+ (NSImage *)imageForIcon:(AIFontAwesomeIcon)icon
                    style:(AIFontAwesomeStyle)style
                 iconSize:(CGFloat)iconSize
               canvasSize:(CGFloat)canvasSize
                    scale:(CGFloat)scale
{
  return [self imageForCodePoint:(uint32_t)icon
                           style:style
                        iconSize:iconSize
                      canvasSize:canvasSize
                           scale:scale];
}
#endif

#if TARGET_OS_IPHONE
+ (void)registerBundledFonts
{
  NSArray *paths = [NSArray arrayWithObjects:[self solidFontPath],
                    [self regularFontPath], [self brandsFontPath], nil];
  NSEnumerator *e = [paths objectEnumerator];
  NSString *path;
  while ((path = [e nextObject])) {
    if (path) [self registerFontFile:path];
  }
}

/* One OTF -> the process font manager. Already-registered is benign (e.g. a
 * second bootstrap) and only logged. Kept tiny so -registerBundledFonts stays
 * a flat loop. */
+ (void)registerFontFile:(NSString *)path
{
  NSURL *url = [NSURL fileURLWithPath:path];
  CFErrorRef err = NULL;
  if (CTFontManagerRegisterFontsForURL((CFURLRef)url,
                                       kCTFontManagerScopeProcess, &err)) {
    return;
  }
  AIFALog(@"AIFontAwesome.registerFontFile", @"register %@ failed: %@",
          [path lastPathComponent], (err ? (id)err : (id)@"unknown"));
  if (err) CFRelease(err);
}

+ (UIFont *)fontForStyle:(AIFontAwesomeStyle)style size:(CGFloat)size
{
  if (size <= 0.0) {
    AIFALog(@"AIFontAwesome.fontForStyle", @"invalid size %g", size);
    return nil;
  }
  NSString *ps = ai_fa_postscript_name(style);
  UIFont *font = [UIFont fontWithName:ps size:size];
  if (!font) {
    AIFALog(@"AIFontAwesome.fontForStyle",
            @"font '%@' unavailable -- did +registerBundledFonts run?", ps);
  }
  return font;
}

+ (UIImage *)imageForCodePoint:(uint32_t)codePoint
                         style:(AIFontAwesomeStyle)style
                      iconSize:(CGFloat)iconSize
                    canvasSize:(CGFloat)canvasSize
                         scale:(CGFloat)scale
{
  return [self imageForCodePoint:codePoint
                           style:style
                        iconSize:iconSize
                      canvasSize:canvasSize
                           color:nil
                           scale:scale];
}

+ (UIImage *)imageForCodePoint:(uint32_t)codePoint
                         style:(AIFontAwesomeStyle)style
                      iconSize:(CGFloat)iconSize
                    canvasSize:(CGFloat)canvasSize
                         color:(UIColor *)color
                         scale:(CGFloat)scale
{
  /* scale <= 0 means "use the main screen scale" — callers no longer fetch and
   * guard it themselves. -[UIScreen mainScreen].scale is always >= 1 on a real
   * device; the 1.0 fallback only covers a degenerate (headless) screen. */
  if (scale <= 0.0f) {
    scale = [UIScreen mainScreen].scale;
    if (scale <= 0.0f) scale = 1.0f;
  }
  /* color nil -> NULL fill -> the opaque-black template (UIKit then tints it
   * via tintColor / template rendering); a real color bakes the tint into the
   * glyph in one rasterisation pass. */
  CGImageRef cg = [self _newImageForCodePoint:codePoint
                                        style:style
                                     iconSize:iconSize
                                   canvasSize:canvasSize
                                         fill:(color ? color.CGColor : NULL)
                                        scale:scale];
  if (!cg) return nil;

  /* Bake the device scale into the UIImage so it draws at `canvasSize` points
   * (the CGImage carries canvasSize*scale pixels, with the glyph rasterised at
   * iconSize and centered). -imageWithCGImage:scale:orientation: is 4.0+, safe
   * on the 5.0 floor. */
  UIImage *img = [UIImage imageWithCGImage:cg
                                     scale:scale
                               orientation:UIImageOrientationUp];
  CGImageRelease(cg);
  return img;
}

+ (UIImage *)imageForCodePoint:(uint32_t)codePoint
                         style:(AIFontAwesomeStyle)style
                     pointSize:(CGFloat)pointSize
                         scale:(CGFloat)scale
{
  return [self imageForCodePoint:codePoint
                           style:style
                        iconSize:pointSize
                      canvasSize:pointSize
                           scale:scale];
}

+ (UIImage *)imageForIcon:(AIFontAwesomeIcon)icon
                    style:(AIFontAwesomeStyle)style
                pointSize:(CGFloat)pointSize
                    scale:(CGFloat)scale
{
  return [self imageForCodePoint:(uint32_t)icon
                           style:style
                       pointSize:pointSize
                           scale:scale];
}

+ (UIImage *)imageForIcon:(AIFontAwesomeIcon)icon
                    style:(AIFontAwesomeStyle)style
                 iconSize:(CGFloat)iconSize
               canvasSize:(CGFloat)canvasSize
                    scale:(CGFloat)scale
{
  return [self imageForCodePoint:(uint32_t)icon
                           style:style
                        iconSize:iconSize
                      canvasSize:canvasSize
                           color:nil
                           scale:scale];
}

+ (UIImage *)imageForIcon:(AIFontAwesomeIcon)icon
                    style:(AIFontAwesomeStyle)style
                 iconSize:(CGFloat)iconSize
               canvasSize:(CGFloat)canvasSize
                    color:(UIColor *)color
                    scale:(CGFloat)scale
{
  return [self imageForCodePoint:(uint32_t)icon
                           style:style
                        iconSize:iconSize
                      canvasSize:canvasSize
                           color:color
                           scale:scale];
}
#endif

+ (NSString *)stringForCodePoint:(uint32_t)codePoint
{
  if (codePoint == 0) {
    AIFALog(@"AIFontAwesome.stringForCodePoint", @"invalid code point 0");
    return nil;
  }
  UniChar u16[2];
  int n = ai_fa_to_utf16(codePoint, u16);
  return [NSString stringWithCharacters:u16 length:(NSUInteger)n];
}

@end
