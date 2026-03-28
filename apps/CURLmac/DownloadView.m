#import "DownloadView.h"

@implementation DownloadView

- (id)initWithFrame:(NSRect)frame;
{
  if ((self = [super initWithFrame:frame])) {
    [self setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    
    CGFloat height = frame.size.height;
    CGFloat width = frame.size.width;
    CGFloat padding = 8;
    CGFloat buttonWidth = 90;

    // 1. URL Field: Top row, flexible width
    urlField_ = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, 
                                                              height - 32, 
                                                              width - 110, 
                                                              24)];
    [urlField_ setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [[urlField_ cell] setPlaceholderString:@"Enter URL here..."];
    [urlField_ setStringValue:@"https://platform.theverge.com/wp-content/uploads/sites/2/2026/03/Rank-Apple-Products-Lead-Art-1.jpg?quality=90&strip=all&crop=0%2C0%2C100%2C100&w=1440"];
    
    // Ensure no wrapping and horizontal scrolling
    [[urlField_ cell] setScrollable:YES];
    
    [self addSubview:urlField_];
    
    // 2. Download Button: To the right of URL
    downloadButton_ = [[NSButton alloc] initWithFrame:NSMakeRect(width - buttonWidth - padding, 
                                                                  height - 36, 
                                                                  buttonWidth, 
                                                                  32)];
    [downloadButton_ setTitle:@"Download"];
    [downloadButton_ setBezelStyle:XPBezelStyleRounded];
    [downloadButton_ setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [downloadButton_ setTarget:nil];
    [downloadButton_ setAction:@selector(downloadButtonClicked:)];
    [self addSubview:downloadButton_];

    // 3. Image View (Well): Centerpiece (Expanded)
    imageView_ = [[NSImageView alloc] initWithFrame:NSMakeRect(padding, 
                                                                32, 
                                                                width - (padding * 2), 
                                                                height - 68)];
    [imageView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [imageView_ setImageFrameStyle:NSImageFrameGrayBezel];
    [imageView_ setImageScaling:NSImageScaleProportionallyUpOrDown];
    [self addSubview:imageView_];

    // 4. Status Label: At bottom
    statusLabel_ = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, 
                                                                 8, 
                                                                 width - (padding * 2), 
                                                                 20)];
    [statusLabel_ setStringValue:@"Ready"];
    [statusLabel_ setBezeled:NO];
    [statusLabel_ setDrawsBackground:NO];
    [statusLabel_ setEditable:NO];
    [statusLabel_ setSelectable:YES];
    [statusLabel_ setFont:[NSFont systemFontOfSize:11]];
    [statusLabel_ setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [self addSubview:statusLabel_];

    // 5. Progress Indicator: At bottom (on top of label)
    progressIndicator_ = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(padding, 
                                                                               8, 
                                                                               width - (padding * 2), 
                                                                               20)];
    [progressIndicator_ setStyle:XPProgressIndicatorStyleBar];
    [progressIndicator_ setIndeterminate:YES];
    [progressIndicator_ setDisplayedWhenStopped:NO];
    [progressIndicator_ setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [self addSubview:progressIndicator_];
  }
  return self;
}

- (void)dealloc;
{
  [urlField_ release];
  [downloadButton_ release];
  [progressIndicator_ release];
  [imageView_ release];
  [statusLabel_ release];
  [identifier_ release];
  [super dealloc];
}

#pragma mark - Accessors

- (NSTextField *)urlField;
{
  return urlField_;
}

- (NSTextField *)statusLabel;
{
  return statusLabel_;
}

- (NSButton *)downloadButton;
{
  return downloadButton_;
}

- (NSProgressIndicator *)progressIndicator;
{
  return progressIndicator_;
}

- (NSImageView *)imageView;
{
  return imageView_;
}

- (NSString *)identifier;
{
  return identifier_;
}

- (void)setIdentifier:(NSString *)identifier;
{
  [identifier_ autorelease];
  identifier_ = [identifier copy];
}

@end
