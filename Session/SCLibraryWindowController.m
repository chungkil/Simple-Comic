/*
    SCLibraryWindowController.m
 */

#import "SCLibraryWindowController.h"
#import "SCProgressStore.h"
#import "SCCoverCache.h"
#import "SimpleComicAppDelegate.h"

static const CGFloat SCLibraryRowHeight = 92.0f;


@implementation SCLibraryWindowController


- (id)init
{
    NSRect frame = NSMakeRect(0, 0, 720, 520);
    NSWindow * window = [[[NSWindow alloc] initWithContentRect: frame
                                                     styleMask: (NSWindowStyleMaskTitled |
                                                                 NSWindowStyleMaskClosable |
                                                                 NSWindowStyleMaskMiniaturizable |
                                                                 NSWindowStyleMaskResizable)
                                                       backing: NSBackingStoreBuffered
                                                         defer: YES] autorelease];
    [window setTitle: NSLocalizedString(@"Library", @"Library window title")];
    [window setReleasedWhenClosed: NO];
    [window setMinSize: NSMakeSize(420, 280)];
    [window center];

    self = [super initWithWindow: window];
    if(self)
    {
        NSScrollView * scrollView = [[[NSScrollView alloc] initWithFrame: [[window contentView] bounds]] autorelease];
        [scrollView setHasVerticalScroller: YES];
        [scrollView setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
        [scrollView setBorderType: NSNoBorder];

        tableView = [[NSTableView alloc] initWithFrame: [scrollView bounds]];
        NSTableColumn * column = [[[NSTableColumn alloc] initWithIdentifier: @"work"] autorelease];
        [column setResizingMask: NSTableColumnAutoresizingMask];
        [tableView addTableColumn: column];
        [tableView setHeaderView: nil];
        [tableView setRowHeight: SCLibraryRowHeight];
        [tableView setDataSource: self];
        [tableView setDelegate: self];
        [tableView setTarget: self];
        [tableView setDoubleAction: @selector(openSelected:)];
        [tableView setAllowsMultipleSelection: NO];

        NSMenu * contextMenu = [[[NSMenu alloc] initWithTitle: @"Library"] autorelease];
        [contextMenu addItemWithTitle: NSLocalizedString(@"Open", @"")
                               action: @selector(openSelected:)
                        keyEquivalent: @""];
        [contextMenu addItemWithTitle: NSLocalizedString(@"Remove from Library", @"")
                               action: @selector(removeSelected:)
                        keyEquivalent: @""];
        for(NSMenuItem * mi in [contextMenu itemArray])
        {
            [mi setTarget: self];
        }
        [tableView setMenu: contextMenu];

        [scrollView setDocumentView: tableView];
        [window setContentView: scrollView];

        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(coverReady:)
                                                     name: SCCoverReadyNotification
                                                   object: nil];
    }
    return self;
}


- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [tableView release];
    [workKeys release];
    [super dealloc];
}


- (void)reload
{
    NSArray * keys = [[[SCProgressStore sharedStore] allWorkKeys] copy];
    [workKeys release];
    workKeys = keys;
    [tableView reloadData];
}


- (void)showWindow:(id)sender
{
    [self reload];
    [super showWindow: sender];
    [[self window] makeKeyAndOrderFront: sender];
}


- (void)coverReady:(NSNotification *)note
{
    NSString * key = [[note userInfo] objectForKey: @"key"];
    NSUInteger row = [workKeys indexOfObject: key];
    if(row != NSNotFound)
    {
        [tableView reloadDataForRowIndexes: [NSIndexSet indexSetWithIndex: row]
                             columnIndexes: [NSIndexSet indexSetWithIndex: 0]];
    }
}


#pragma mark - Actions


- (NSString *)keyForRow:(NSInteger)row
{
    if(row >= 0 && row < (NSInteger)[workKeys count])
    {
        return [workKeys objectAtIndex: row];
    }
    return nil;
}


- (void)openSelected:(id)sender
{
    NSInteger row = [tableView clickedRow] >= 0 ? [tableView clickedRow] : [tableView selectedRow];
    NSString * key = [self keyForRow: row];
    if([key length])
    {
        [(SimpleComicAppDelegate *)[NSApp delegate] openWorkAtPath: key];
    }
}


- (void)removeSelected:(id)sender
{
    NSInteger row = [tableView clickedRow] >= 0 ? [tableView clickedRow] : [tableView selectedRow];
    NSString * key = [self keyForRow: row];
    if([key length])
    {
        [[SCProgressStore sharedStore] removeRecordForKey: key];
        [[SCCoverCache sharedCache] removeCoverForKey: key];
        [self reload];
    }
}


- (void)keyDown:(NSEvent *)event
{
    unichar c = [[event charactersIgnoringModifiers] length] ? [[event charactersIgnoringModifiers] characterAtIndex: 0] : 0;
    if(c == NSDeleteCharacter || c == NSDeleteFunctionKey || c == 0x7F)
    {
        [self removeSelected: nil];
        return;
    }
    [super keyDown: event];
}


#pragma mark - Table data source / delegate


- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv
{
    return [workKeys count];
}


- (NSView *)tableView:(NSTableView *)tv
   viewForTableColumn:(NSTableColumn *)column
                  row:(NSInteger)row
{
    NSString * key = [self keyForRow: row];
    if(!key)
    {
        return nil;
    }

    NSView * cell = [tv makeViewWithIdentifier: @"SCLibraryCell" owner: self];
    NSImageView * cover;
    NSTextField * title;
    NSTextField * detail;

    if(!cell)
    {
        cell = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 600, SCLibraryRowHeight)] autorelease];
        [cell setIdentifier: @"SCLibraryCell"];

        cover = [[[NSImageView alloc] initWithFrame: NSMakeRect(8, 6, 60, SCLibraryRowHeight - 12)] autorelease];
        [cover setImageScaling: NSImageScaleProportionallyUpOrDown];
        [cover setImageAlignment: NSImageAlignCenter];
        [cover setTag: 1];
        [cover setAutoresizingMask: NSViewHeightSizable];
        [cell addSubview: cover];

        title = [[[NSTextField alloc] initWithFrame: NSMakeRect(80, 50, 500, 22)] autorelease];
        [title setEditable: NO];
        [title setBordered: NO];
        [title setDrawsBackground: NO];
        [title setFont: [NSFont boldSystemFontOfSize: 14]];
        [title setLineBreakMode: NSLineBreakByTruncatingTail];
        [title setTag: 2];
        [title setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
        [cell addSubview: title];

        detail = [[[NSTextField alloc] initWithFrame: NSMakeRect(80, 14, 500, 32)] autorelease];
        [detail setEditable: NO];
        [detail setBordered: NO];
        [detail setDrawsBackground: NO];
        [detail setFont: [NSFont systemFontOfSize: 11]];
        [detail setTextColor: [NSColor secondaryLabelColor]];
        [detail setTag: 3];
        [detail setAutoresizingMask: NSViewWidthSizable | NSViewMaxYMargin];
        [cell addSubview: detail];
    }
    else
    {
        cover = (NSImageView *)[cell viewWithTag: 1];
        title = (NSTextField *)[cell viewWithTag: 2];
        detail = (NSTextField *)[cell viewWithTag: 3];
    }

    NSImage * art = [[SCCoverCache sharedCache] coverForKey: key path: key];
    if(!art)
    {
        art = [[NSWorkspace sharedWorkspace] iconForFile: key];
    }
    [cover setImage: art];

    [title setStringValue: [[key lastPathComponent] stringByDeletingPathExtension]];

    NSDictionary * record = [[SCProgressStore sharedStore] recordForKey: key];
    NSInteger lastPage = [[record objectForKey: @"lastPage"] integerValue];
    NSInteger bookmarks = [[record objectForKey: @"bookmarks"] count];
    BOOL webtoon = [[record objectForKey: @"layoutMode"] integerValue] == 1;
    NSDate * updated = [record objectForKey: @"updated"];

    NSString * when = @"";
    if(updated)
    {
        NSDateFormatter * df = [[[NSDateFormatter alloc] init] autorelease];
        [df setDateStyle: NSDateFormatterMediumStyle];
        [df setTimeStyle: NSDateFormatterShortStyle];
        when = [df stringFromDate: updated];
    }
    NSString * detailText = [NSString stringWithFormat:
        NSLocalizedString(@"Page %ld%@%@\n%@", @"Library row detail"),
        (long)(lastPage + 1),
        webtoon ? NSLocalizedString(@"  ·  Webtoon", @"") : @"",
        bookmarks > 0 ? [NSString stringWithFormat: NSLocalizedString(@"  ·  %ld bookmarks", @""), (long)bookmarks] : @"",
        when];
    [detail setStringValue: detailText];

    return cell;
}

@end
