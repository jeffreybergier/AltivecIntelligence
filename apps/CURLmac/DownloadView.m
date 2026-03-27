#import "DownloadView.h"

@implementation DownloadView

- (id)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    [self setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    
    CGFloat height = frame.size.height;
    CGFloat width = frame.size.width;

    // URL Field: Full width, 120px tall
    _urlField = [[NSTextField alloc] initWithFrame:NSMakeRect(10, height - 130, width - 20, 120)];
    [_urlField setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [[_urlField cell] setPlaceholderString:@"Enter URL here..."];
    [_urlField setStringValue:@"https://platform.theverge.com/wp-content/uploads/sites/2/2026/03/Rank-Apple-Products-Lead-Art-1.jpg?quality=90&strip=all&crop=0%2C0%2C100%2C100&w=1440"];
    [self addSubview:_urlField];
    
    // Download Button
    _downloadButton = [[NSButton alloc] initWithFrame:NSMakeRect(10, height - 170, 100, 32)];
    [_downloadButton setTitle:@"Download"];
    [_downloadButton setBezelStyle:XPBezelStyleRounded];
    [_downloadButton setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];
    [_downloadButton setTarget:nil];
    [_downloadButton setAction:@selector(downloadButtonClicked:)];
    [self addSubview:_downloadButton];

    // Reset Button
    _resetButton = [[NSButton alloc] initWithFrame:NSMakeRect(110, height - 170, 100, 32)];
    [_resetButton setTitle:@"Reset"];
    [_resetButton setBezelStyle:XPBezelStyleRounded];
    [_resetButton setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];
    [_resetButton setTarget:nil];
    [_resetButton setAction:@selector(resetButtonClicked:)];
    [self addSubview:_resetButton];

    // Well (Image View): To the right
    _imageView = [[NSImageView alloc] initWithFrame:NSMakeRect(220, 10, width - 230, height - 140)];
    [_imageView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [_imageView setImageFrameStyle:NSImageFrameGrayBezel];
    [_imageView setImageScaling:NSImageScaleProportionallyUpOrDown];
    [self addSubview:_imageView];

    // Status View (Matches Tab 0 style, but smaller)
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(10, 10, 200, height - 180)];
    [scrollView setHasVerticalScroller:YES];
    [scrollView setBorderType:NSBezelBorder];
    [scrollView setAutoresizingMask:NSViewMaxXMargin | NSViewHeightSizable];
    
    NSSize contentSize = [scrollView contentSize];
    _statusView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
    [_statusView setEditable:NO];
    [_statusView setAutoresizingMask:NSViewWidthSizable];
    
    [scrollView setDocumentView:_statusView];
    [self addSubview:scrollView];
    [scrollView release];
  }
  return self;
}

- (NSTextField *)urlField { return _urlField; }
- (NSTextView *)statusView { return _statusView; }
- (NSButton *)downloadButton { return _downloadButton; }
- (NSButton *)resetButton { return _resetButton; }
- (NSImageView *)imageView { return _imageView; }

- (NSString *)identifier { return _identifier; }
- (void)setIdentifier:(NSString *)identifier {
  if (_identifier != identifier) {
    [_identifier release];
    _identifier = [identifier retain];
  }
}

- (void)dealloc {
  [_urlField release];
  [_downloadButton release];
  [_resetButton release];
  [_imageView release];
  [_statusView release];
  [_identifier release];
  [super dealloc];
}

@end
