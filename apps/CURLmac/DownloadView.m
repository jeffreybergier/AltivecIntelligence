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
    // X: 8, Y: height - 8 (padding) - 24 (height) = height - 32
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
    // Aligning visually with URL field.
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

    // 3. Image View (Well): Centerpiece
    // Spacing: Even 8px on left, right, and bottom.
    // X: 8, Y: 8, Width: width - 16
    // Height: height - 36 (button top) - 4 (gap) - 8 (bottom) = height - 48
    imageView_ = [[NSImageView alloc] initWithFrame:NSMakeRect(padding, 
                                                                padding, 
                                                                width - (padding * 2), 
                                                                height - 48)];
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
  [imageView_ release];
  [identifier_ release];
  [super dealloc];
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
