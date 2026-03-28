#import "DownloadView.h"

@implementation DownloadView

- (id)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    [self setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    
    CGFloat height = frame.size.height;
    CGFloat width = frame.size.width;
    CGFloat padding = 8;
    CGFloat buttonWidth = 90;

    // 1. URL Field: Top row, flexible width
    // X: 8, Width: width - buttonWidth (90) - padding (8) - gap (4) - startX (8) = width - 110
    _urlField = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, height - 32, width - 110, 24)];
    [_urlField setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [[_urlField cell] setPlaceholderString:@"Enter URL here..."];
    [_urlField setStringValue:@"https://platform.theverge.com/wp-content/uploads/sites/2/2026/03/Rank-Apple-Products-Lead-Art-1.jpg?quality=90&strip=all&crop=0%2C0%2C100%2C100&w=1440"];
    
    // Ensure no wrapping and horizontal scrolling
    [[_urlField cell] setScrollable:YES];
    
    [self addSubview:_urlField];
    
    // 2. Download Button: To the right of URL
    // Aligning top with URL field.
    _downloadButton = [[NSButton alloc] initWithFrame:NSMakeRect(width - buttonWidth - padding, height - 36, buttonWidth, 32)];
    [_downloadButton setTitle:@"Download"];
    [_downloadButton setBezelStyle:XPBezelStyleRounded];
    [_downloadButton setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [_downloadButton setTarget:nil];
    [_downloadButton setAction:@selector(downloadButtonClicked:)];
    [self addSubview:_downloadButton];

    // 3. Image View (Well): Centerpiece (Expanded)
    // Gap check: URL bottom is at height - 32. 
    // We want 4px gap. 32 + 4 = 36.
    // So the well should start at height - 36 downwards.
    // Bottom area is 32.
    // Height = height - 36 - 32 = height - 68.
    _imageView = [[NSImageView alloc] initWithFrame:NSMakeRect(padding, 32, width - (padding * 2), height - 68)];
    [_imageView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [_imageView setImageFrameStyle:NSImageFrameGrayBezel];
    [_imageView setImageScaling:NSImageScaleProportionallyUpOrDown];
    [self addSubview:_imageView];

    // 4. Status Label: At bottom
    // X: 8, Y: 8, Height: 20
    _statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, 8, width - (padding * 2), 20)];
    [_statusLabel setStringValue:@"Ready"];
    [_statusLabel setBezeled:NO];
    [_statusLabel setDrawsBackground:NO];
    [_statusLabel setEditable:NO];
    [_statusLabel setSelectable:YES];
    [_statusLabel setFont:[NSFont systemFontOfSize:11]];
    [_statusLabel setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [self addSubview:_statusLabel];

    // 5. Progress Indicator: At bottom (on top of label)
    // X: 8, Y: 8, Height: 20
    _progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(padding, 8, width - (padding * 2), 20)];
    [_progressIndicator setStyle:XPProgressIndicatorStyleBar];
    [_progressIndicator setIndeterminate:YES];
    [_progressIndicator setDisplayedWhenStopped:NO];
    [_progressIndicator setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [self addSubview:_progressIndicator];
  }
  return self;
}

- (NSTextField *)urlField { return _urlField; }
- (NSTextField *)statusLabel { return _statusLabel; }
- (NSButton *)downloadButton { return _downloadButton; }
- (NSProgressIndicator *)progressIndicator { return _progressIndicator; }
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
  [_progressIndicator release];
  [_imageView release];
  [_statusLabel release];
  [_identifier release];
  [super dealloc];
}

@end
