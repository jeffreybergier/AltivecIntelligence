#import "DownloadView.h"
#import "DownloadManager.h"

@implementation DownloadView

- (id)initWithFrame:(NSRect)frame;
{
  if ((self = [super initWithFrame:frame])) {
    [self setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    
    CGFloat height = frame.size.height;
    CGFloat width = frame.size.width;
    CGFloat padding = 8;
    CGFloat buttonWidth = 90;

    // 1. URL Field: Top row
    urlField_ = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, 
                                                              height - 32, 
                                                              width - 110, 
                                                              24)];
    [urlField_ setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [[urlField_ cell] setPlaceholderString:@"Enter URL here..."];
    [urlField_ setStringValue:@"https://platform.theverge.com/wp-content/uploads/sites/2/2026/03/Rank-Apple-Products-Lead-Art-1.jpg?quality=90&strip=all&crop=0%2C0%2C100%2C100&w=1440"];
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
    [downloadButton_ setTarget:self];
    [downloadButton_ setAction:@selector(downloadButtonClicked:)];
    [self addSubview:downloadButton_];

    // 3. Progress Indicator: Below Top Row
    progressIndicator_ = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(padding, 
                                                                               height - 56, 
                                                                               width - (padding * 2), 
                                                                               16)];
    [progressIndicator_ setStyle:XPProgressIndicatorStyleBar];
    [progressIndicator_ setIndeterminate:NO];
    [progressIndicator_ setMinValue:0.0];
    [progressIndicator_ setMaxValue:1.0];
    [progressIndicator_ setDoubleValue:1.0]; // Set to 1 of 1 on load
    [progressIndicator_ setDisplayedWhenStopped:YES];
    [progressIndicator_ setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [self addSubview:progressIndicator_];

    // 4. Status Label: At bottom
    statusLabel_ = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, 
                                                                 4, 
                                                                 width - (padding * 2), 
                                                                 16)];
    [statusLabel_ setStringValue:@"Ready"];
    [statusLabel_ setBezeled:NO];
    [statusLabel_ setDrawsBackground:NO];
    [statusLabel_ setEditable:NO];
    [statusLabel_ setSelectable:NO];
    [statusLabel_ setFont:[NSFont systemFontOfSize:11]];
    [statusLabel_ setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [self addSubview:statusLabel_];

    // 5. Image View (Well): Centerpiece
    // Space below: 4 (padding) + 16 (status) + 4 (gap) = 24
    // Space above: 56 (progress top) + 4 (gap) = 60
    imageView_ = [[NSImageView alloc] initWithFrame:NSMakeRect(padding, 
                                                                24, 
                                                                width - (padding * 2), 
                                                                height - 84)];
    [imageView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [imageView_ setImageFrameStyle:NSImageFrameGrayBezel];
    [imageView_ setImageScaling:NSImageScaleProportionallyUpOrDown];
    [self addSubview:imageView_];
  }
  return self;
}

- (void)dealloc;
{
  [urlField_ release];
  [downloadButton_ release];
  [progressIndicator_ release];
  [statusLabel_ release];
  [imageView_ release];
  [identifier_ release];
  [manager_ release];
  [super dealloc];
}

#pragma mark - Actions

- (void)downloadButtonClicked:(id)sender;
{
  if (manager_) {
    [manager_ downloadButtonClicked:sender];
  }
}

#pragma mark - Accessors

- (NSTextField *)urlField;
{
  return urlField_;
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

- (NSTextField *)statusLabel;
{
  return statusLabel_;
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

- (DownloadManager *)manager;
{
  return manager_;
}

- (void)setManager:(DownloadManager *)manager;
{
  if (manager_ != manager) {
    [manager_ release];
    manager_ = [manager retain];
  }
}

@end
