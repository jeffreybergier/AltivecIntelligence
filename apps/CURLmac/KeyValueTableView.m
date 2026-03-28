#import "KeyValueTableView.h"

@implementation KeyValueTableView

- (id)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    [self setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    _scrollView = [[NSScrollView alloc] initWithFrame:[self bounds]];
    [_scrollView setHasVerticalScroller:YES];
    [_scrollView setHasHorizontalScroller:YES];
    [_scrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [_scrollView setBorderType:NSBezelBorder];

    _tableView = [[NSTableView alloc] initWithFrame:[[_scrollView contentView] bounds]];
    
    NSTableColumn *keyCol = [[NSTableColumn alloc] initWithIdentifier:@"Key"];
    [[keyCol headerCell] setStringValue:@"Key"];
    [keyCol setWidth:152.0];
    [keyCol setEditable:NO];
    [_tableView addTableColumn:keyCol];
    [keyCol release];

    NSTableColumn *valCol = [[NSTableColumn alloc] initWithIdentifier:@"Value"];
    [[valCol headerCell] setStringValue:@"Value"];
    [valCol setWidth:252.0];
    [valCol setEditable:NO];
    [valCol setResizingMask:NSTableColumnAutoresizingMask];
    [_tableView addTableColumn:valCol];
    [valCol release];

    [_tableView setDataSource:self];
    [_tableView setDelegate:self];
    [_tableView setUsesAlternatingRowBackgroundColors:YES];
    [_tableView setAutoresizingMask:NSViewWidthSizable];

    [_scrollView setDocumentView:_tableView];
    [self addSubview:_scrollView];
  }
  return self;
}

- (void)setData:(NSDictionary *)data {
  if (_data != data) {
    [_data release];
    _data = [data retain];
    
    [_sortedKeys release];
    _sortedKeys = [[[_data allKeys] sortedArrayUsingSelector:@selector(compare:)] retain];
    
    [_tableView reloadData];
  }
}

- (NSDictionary *)data {
  return _data;
}

#pragma mark - NSTableDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  return (NSInteger)[_sortedKeys count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
  NSString *key = [_sortedKeys objectAtIndex:row];
  if ([[tableColumn identifier] isEqualToString:@"Key"]) {
    return key;
  } else {
    return [_data objectForKey:key];
  }
}

- (void)dealloc {
  [_scrollView release];
  [_tableView release];
  [_data release];
  [_sortedKeys release];
  [super dealloc];
}

@end
