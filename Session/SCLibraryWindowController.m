/*
    SCLibraryWindowController.m

    Grid (cover-shelf) browser over every work the reader has opened.
 */

#import "SCLibraryWindowController.h"
#import "SCProgressStore.h"
#import "SCCoverCache.h"
#import "SimpleComicAppDelegate.h"


#pragma mark - Collection item


@interface SCLibraryItem : NSCollectionViewItem
@end

@implementation SCLibraryItem

- (void)loadView
{
    NSView * v = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 170, 250)] autorelease];
    [v setWantsLayer: YES];

    NSImageView * iv = [[[NSImageView alloc] initWithFrame: NSMakeRect(10, 40, 150, 200)] autorelease];
    [iv setImageScaling: NSImageScaleProportionallyUpOrDown];
    [iv setImageAlignment: NSImageAlignBottom];
    [iv setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
    [v addSubview: iv];
    self.imageView = iv;

    NSTextField * tf = [[[NSTextField alloc] initWithFrame: NSMakeRect(6, 4, 158, 32)] autorelease];
    [tf setEditable: NO];
    [tf setSelectable: NO];
    [tf setBordered: NO];
    [tf setDrawsBackground: NO];
    [tf setAlignment: NSTextAlignmentCenter];
    [tf setFont: [NSFont systemFontOfSize: 11]];
    [tf setLineBreakMode: NSLineBreakByTruncatingMiddle];
    [tf setMaximumNumberOfLines: 2];
    [tf setAutoresizingMask: NSViewWidthSizable | NSViewMaxYMargin];
    [v addSubview: tf];
    self.textField = tf;

    self.view = v;
}

- (void)setSelected:(BOOL)selected
{
    [super setSelected: selected];
    NSColor * highlight;
    if(@available(macOS 10.14, *))
    {
        highlight = [NSColor selectedContentBackgroundColor];
    }
    else
    {
        highlight = [NSColor alternateSelectedControlColor];
    }
    self.view.layer.cornerRadius = 6.0;
    self.view.layer.backgroundColor = selected
        ? [[highlight colorWithAlphaComponent: 0.30] CGColor]
        : NULL;
}

@end


#pragma mark - Collection view (selects under the cursor before a context menu)


@interface SCLibraryCollectionView : NSCollectionView
@end

@implementation SCLibraryCollectionView

- (NSMenu *)menuForEvent:(NSEvent *)event
{
    NSPoint p = [self convertPoint: [event locationInWindow] fromView: nil];
    NSIndexPath * ip = [self indexPathForItemAtPoint: p];
    if(ip)
    {
        [self setSelectionIndexPaths: [NSSet setWithObject: ip]];
    }
    return [self menu];
}

@end


#pragma mark - Window controller


@implementation SCLibraryWindowController


- (id)init
{
    NSRect frame = NSMakeRect(0, 0, 760, 560);
    NSWindow * window = [[[NSWindow alloc] initWithContentRect: frame
                                                     styleMask: (NSWindowStyleMaskTitled |
                                                                 NSWindowStyleMaskClosable |
                                                                 NSWindowStyleMaskMiniaturizable |
                                                                 NSWindowStyleMaskResizable)
                                                       backing: NSBackingStoreBuffered
                                                         defer: YES] autorelease];
    [window setTitle: NSLocalizedString(@"Library", @"Library window title")];
    [window setReleasedWhenClosed: NO];
    [window setMinSize: NSMakeSize(420, 320)];
    [window center];

    self = [super initWithWindow: window];
    if(self)
    {
        NSScrollView * scrollView = [[[NSScrollView alloc] initWithFrame: [[window contentView] bounds]] autorelease];
        [scrollView setHasVerticalScroller: YES];
        [scrollView setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
        [scrollView setBorderType: NSNoBorder];

        NSCollectionViewFlowLayout * layout = [[[NSCollectionViewFlowLayout alloc] init] autorelease];
        [layout setItemSize: NSMakeSize(170, 250)];
        [layout setMinimumInteritemSpacing: 8];
        [layout setMinimumLineSpacing: 12];
        [layout setSectionInset: NSEdgeInsetsMake(14, 14, 14, 14)];

        collectionView = [[SCLibraryCollectionView alloc] initWithFrame: [scrollView bounds]];
        [collectionView setCollectionViewLayout: layout];
        [collectionView setDataSource: self];
        [collectionView setDelegate: self];
        [collectionView setSelectable: YES];
        [collectionView setAllowsEmptySelection: YES];
        [collectionView setAllowsMultipleSelection: NO];
        [collectionView setBackgroundColors: @[[NSColor controlBackgroundColor]]];
        [collectionView registerClass: [SCLibraryItem class]
                forItemWithIdentifier: @"item"];

        NSClickGestureRecognizer * dbl = [[[NSClickGestureRecognizer alloc]
            initWithTarget: self action: @selector(handleDoubleClick:)] autorelease];
        [dbl setNumberOfClicksRequired: 2];
        [dbl setDelaysPrimaryMouseButtonEvents: NO];
        [collectionView addGestureRecognizer: dbl];

        NSMenu * contextMenu = [[[NSMenu alloc] initWithTitle: @"Library"] autorelease];
        [[contextMenu addItemWithTitle: NSLocalizedString(@"Open", @"")
                                action: @selector(openSelected:)
                         keyEquivalent: @""] setTarget: self];
        [[contextMenu addItemWithTitle: NSLocalizedString(@"Remove from Library", @"")
                                action: @selector(removeSelected:)
                         keyEquivalent: @""] setTarget: self];
        [collectionView setMenu: contextMenu];

        [scrollView setDocumentView: collectionView];
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
    [collectionView release];
    [workKeys release];
    [super dealloc];
}


- (void)reload
{
    NSArray * keys = [[[SCProgressStore sharedStore] allWorkKeys] copy];
    [workKeys release];
    workKeys = keys;
    [collectionView reloadData];
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
    NSUInteger idx = [workKeys indexOfObject: key];
    if(idx != NSNotFound)
    {
        NSIndexPath * ip = [NSIndexPath indexPathForItem: idx inSection: 0];
        [collectionView reloadItemsAtIndexPaths: [NSSet setWithObject: ip]];
    }
}


#pragma mark - Selection helpers


- (NSString *)keyForIndexPath:(NSIndexPath *)ip
{
    NSInteger i = [ip item];
    if(ip && i >= 0 && i < (NSInteger)[workKeys count])
    {
        return [workKeys objectAtIndex: i];
    }
    return nil;
}


- (NSString *)selectedKey
{
    return [self keyForIndexPath: [[collectionView selectionIndexPaths] anyObject]];
}


#pragma mark - Actions


- (void)handleDoubleClick:(NSGestureRecognizer *)gesture
{
    NSPoint p = [gesture locationInView: collectionView];
    NSString * key = [self keyForIndexPath: [collectionView indexPathForItemAtPoint: p]];
    if([key length])
    {
        [(SimpleComicAppDelegate *)[NSApp delegate] openWorkAtPath: key];
    }
}


- (void)openSelected:(id)sender
{
    NSString * key = [self selectedKey];
    if([key length])
    {
        [(SimpleComicAppDelegate *)[NSApp delegate] openWorkAtPath: key];
    }
}


- (void)removeSelected:(id)sender
{
    NSString * key = [self selectedKey];
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


#pragma mark - Collection data source


- (NSInteger)collectionView:(NSCollectionView *)cv numberOfItemsInSection:(NSInteger)section
{
    return [workKeys count];
}


- (NSCollectionViewItem *)collectionView:(NSCollectionView *)cv
     itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath
{
    SCLibraryItem * item = (SCLibraryItem *)[cv makeItemWithIdentifier: @"item" forIndexPath: indexPath];
    NSString * key = [self keyForIndexPath: indexPath];
    item.representedObject = key;

    NSImage * art = [[SCCoverCache sharedCache] coverForKey: key path: key];
    if(!art)
    {
        art = [[NSWorkspace sharedWorkspace] iconForFile: key];
    }
    [item.imageView setImage: art];

    NSString * title = [[key lastPathComponent] stringByDeletingPathExtension];
    NSDictionary * record = [[SCProgressStore sharedStore] recordForKey: key];
    if(record)
    {
        NSInteger lastPage = [[record objectForKey: @"lastPage"] integerValue];
        title = [NSString stringWithFormat: @"%@\np.%ld", title, (long)(lastPage + 1)];
    }
    [item.textField setStringValue: title];

    return item;
}

@end
