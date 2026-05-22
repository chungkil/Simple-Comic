/*
    SCLibraryWindowController.m

    Grid (cover-shelf) browser over every work the reader has opened.
 */

#import "SCLibraryWindowController.h"
#import "SCProgressStore.h"
#import "SCCoverCache.h"
#import "SimpleComicAppDelegate.h"
#import "TSSTManagedGroup.h"
#import "TSSTPage.h"

static NSString * const SCLibraryFolderKey = @"SCLibraryFolderBookmark";   /* legacy single folder */
static NSString * const SCLibraryFoldersKey = @"SCLibraryFolderBookmarks"; /* array of bookmarks */
static NSString * const SCLibrarySortKey = @"SCLibrarySortMode";
static NSString * const SCLibraryCoverWidthKey = @"SCLibraryCoverWidth";

enum { SCSortRecentRead = 0, SCSortRecentAdded, SCSortName, SCSortProgress };

static const CGFloat SCMinCoverWidth = 110.0;
static const CGFloat SCMaxCoverWidth = 240.0;


#pragma mark - Collection item


@interface SCLibraryItem : NSCollectionViewItem
{
    NSView * unreadBadge;
}
- (void)setUnread:(BOOL)unread;
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

    unreadBadge = [[[NSView alloc] initWithFrame: NSMakeRect(148, 224, 12, 12)] autorelease];
    [unreadBadge setWantsLayer: YES];
    unreadBadge.layer.cornerRadius = 6.0;
    unreadBadge.layer.backgroundColor = [[NSColor systemBlueColor] CGColor];
    [unreadBadge setAutoresizingMask: NSViewMinXMargin | NSViewMinYMargin];
    [unreadBadge setHidden: YES];
    [v addSubview: unreadBadge];

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

- (void)setUnread:(BOOL)unread
{
    [unreadBadge setHidden: !unread];
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
        gridScroll = [[NSScrollView alloc] initWithFrame: [[window contentView] bounds]];
        [gridScroll setHasVerticalScroller: YES];
        [gridScroll setBorderType: NSNoBorder];

        NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
        sortMode = [defaults integerForKey: SCLibrarySortKey];
        CGFloat coverW = [defaults objectForKey: SCLibraryCoverWidthKey]
            ? [defaults doubleForKey: SCLibraryCoverWidthKey] : 150.0;
        if(coverW < SCMinCoverWidth) coverW = SCMinCoverWidth;
        if(coverW > SCMaxCoverWidth) coverW = SCMaxCoverWidth;

        NSCollectionViewFlowLayout * layout = [[[NSCollectionViewFlowLayout alloc] init] autorelease];
        [layout setItemSize: NSMakeSize(coverW + 20, coverW * 1.4 + 36)];
        [layout setMinimumInteritemSpacing: 8];
        [layout setMinimumLineSpacing: 12];
        [layout setSectionInset: NSEdgeInsetsMake(14, 14, 14, 14)];

        collectionView = [[SCLibraryCollectionView alloc] initWithFrame: [gridScroll bounds]];
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

        [gridScroll setDocumentView: collectionView];

        /* Continue-reading shelf: horizontal strip of recent works. */
        continueScroll = [[NSScrollView alloc] initWithFrame: NSZeroRect];
        [continueScroll setHasHorizontalScroller: YES];
        [continueScroll setHasVerticalScroller: NO];
        [continueScroll setBorderType: NSNoBorder];

        NSCollectionViewFlowLayout * cl = [[[NSCollectionViewFlowLayout alloc] init] autorelease];
        [cl setScrollDirection: NSCollectionViewScrollDirectionHorizontal];
        [cl setItemSize: NSMakeSize(130, 180)];
        [cl setMinimumInteritemSpacing: 8];
        [cl setMinimumLineSpacing: 8];
        [cl setSectionInset: NSEdgeInsetsMake(8, 12, 8, 12)];

        continueView = [[NSCollectionView alloc] initWithFrame: NSZeroRect];
        [continueView setCollectionViewLayout: cl];
        [continueView setDataSource: self];
        [continueView setSelectable: YES];
        [continueView setBackgroundColors: @[[NSColor controlBackgroundColor]]];
        [continueView registerClass: [SCLibraryItem class] forItemWithIdentifier: @"item"];
        NSClickGestureRecognizer * single = [[[NSClickGestureRecognizer alloc]
            initWithTarget: self action: @selector(handleContinueClick:)] autorelease];
        [single setNumberOfClicksRequired: 1];
        [continueView addGestureRecognizer: single];
        [continueScroll setDocumentView: continueView];

        /* Two-row header: row 1 = choose folder + path; row 2 = sort,
           search, cover-size slider. */
        NSView * content = [[[NSView alloc] initWithFrame: [[window contentView] bounds]] autorelease];
        [content setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
        CGFloat barH = 72.0;
        NSRect cb = [content bounds];
        CGFloat row1 = NSMaxY(cb) - 32;
        CGFloat row2 = NSMaxY(cb) - 64;

        NSButton * chooseButton = [[[NSButton alloc] initWithFrame: NSMakeRect(10, row1, 150, 26)] autorelease];
        [chooseButton setTitle: NSLocalizedString(@"Choose Folder…", @"")];
        [chooseButton setBezelStyle: NSBezelStyleRounded];
        [chooseButton setTarget: self];
        [chooseButton setAction: @selector(chooseFolder:)];
        [chooseButton setAutoresizingMask: NSViewMinYMargin];
        [content addSubview: chooseButton];

        NSButton * clearButton = [[[NSButton alloc] initWithFrame: NSMakeRect(166, row1, 64, 26)] autorelease];
        [clearButton setTitle: NSLocalizedString(@"Clear", @"")];
        [clearButton setBezelStyle: NSBezelStyleRounded];
        [clearButton setTarget: self];
        [clearButton setAction: @selector(clearFolders:)];
        [clearButton setAutoresizingMask: NSViewMinYMargin];
        [content addSubview: clearButton];

        folderLabel = [[NSTextField alloc] initWithFrame: NSMakeRect(238, row1 + 3, NSWidth(cb) - 248, 20)];
        [folderLabel setEditable: NO];
        [folderLabel setBordered: NO];
        [folderLabel setDrawsBackground: NO];
        [folderLabel setFont: [NSFont systemFontOfSize: 11]];
        [folderLabel setTextColor: [NSColor secondaryLabelColor]];
        [folderLabel setLineBreakMode: NSLineBreakByTruncatingMiddle];
        [folderLabel setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
        [content addSubview: folderLabel];

        sortPopup = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect(10, row2, 150, 26)] autorelease];
        [sortPopup addItemsWithTitles: @[NSLocalizedString(@"Recently read", @""),
                                         NSLocalizedString(@"Recently added", @""),
                                         NSLocalizedString(@"Name", @""),
                                         NSLocalizedString(@"Progress", @"")]];
        [sortPopup selectItemAtIndex: sortMode];
        [sortPopup setTarget: self];
        [sortPopup setAction: @selector(sortChanged:)];
        [sortPopup setAutoresizingMask: NSViewMinYMargin];
        [content addSubview: sortPopup];

        sizeSlider = [[[NSSlider alloc] initWithFrame: NSMakeRect(NSWidth(cb) - 130, row2, 120, 26)] autorelease];
        [sizeSlider setMinValue: SCMinCoverWidth];
        [sizeSlider setMaxValue: SCMaxCoverWidth];
        [sizeSlider setDoubleValue: coverW];
        [sizeSlider setTarget: self];
        [sizeSlider setAction: @selector(coverSizeChanged:)];
        [sizeSlider setAutoresizingMask: NSViewMinXMargin | NSViewMinYMargin];
        [content addSubview: sizeSlider];

        searchField = [[[NSSearchField alloc] initWithFrame: NSMakeRect(170, row2, NSWidth(cb) - 170 - 140, 24)] autorelease];
        [[searchField cell] setPlaceholderString: NSLocalizedString(@"Search", @"")];
        [searchField setTarget: self];
        [searchField setAction: @selector(searchChanged:)];
        [searchField setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
        [content addSubview: searchField];

        continueLabel = [[NSTextField alloc] initWithFrame: NSZeroRect];
        [continueLabel setEditable: NO];
        [continueLabel setBordered: NO];
        [continueLabel setDrawsBackground: NO];
        [continueLabel setFont: [NSFont boldSystemFontOfSize: 11]];
        [continueLabel setTextColor: [NSColor secondaryLabelColor]];
        [continueLabel setStringValue: NSLocalizedString(@"Continue Reading", @"")];
        [content addSubview: continueLabel];

        [content addSubview: continueScroll];
        [content addSubview: gridScroll];
        [window setContentView: content];
        [window setDelegate: self];

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
    [continueView release];
    [continueScroll release];
    [gridScroll release];
    [continueLabel release];
    [continueKeys release];
    [folderLabel release];
    [workKeys release];
    [allKeys release];
    [super dealloc];
}


/* Stored library-folder bookmarks (array), migrating the legacy single
   key on first read. */
- (NSArray *)libraryFolderBookmarks
{
    NSUserDefaults * d = [NSUserDefaults standardUserDefaults];
    NSArray * arr = [d arrayForKey: SCLibraryFoldersKey];
    if([arr count])
    {
        return arr;
    }
    NSData * legacy = [d objectForKey: SCLibraryFolderKey];
    return [legacy isKindOfClass: [NSData class]] ? @[legacy] : @[];
}


- (NSURL *)resolveBookmark:(NSData *)bm
{
    if(![bm isKindOfClass: [NSData class]])
    {
        return nil;
    }
    BOOL stale = NO;
    return [NSURL URLByResolvingBookmarkData: bm
                                    options: NSURLBookmarkResolutionWithSecurityScope
                              relativeToURL: nil
                        bookmarkDataIsStale: &stale
                                      error: NULL];
}


/* Recursively collects works under dir: a directory that directly holds
   images is itself a work (not descended into); archives at any depth
   are works; otherwise recurse into subfolders (depth-capped). */
- (void)collectWorksInDirectory:(NSString *)dir depth:(NSInteger)depth into:(NSMutableArray *)out
{
    if(depth > 6)
    {
        return;
    }
    NSFileManager * fm = [NSFileManager defaultManager];
    NSArray * names = [[fm contentsOfDirectoryAtPath: dir error: NULL]
                       sortedArrayUsingSelector: @selector(localizedStandardCompare:)];
    NSArray * archExt = [TSSTManagedArchive archiveExtensions];
    NSArray * imgExt = [TSSTPage imageExtensions];
    BOOL dirHasImage = NO;
    NSMutableArray * subdirs = [NSMutableArray array];

    for(NSString * name in names)
    {
        if([name hasPrefix: @"."]) continue;
        NSString * full = [dir stringByAppendingPathComponent: name];
        BOOL isDir = NO;
        if(![fm fileExistsAtPath: full isDirectory: &isDir]) continue;
        if(isDir)
        {
            [subdirs addObject: full];
        }
        else
        {
            NSString * ext = [[name pathExtension] lowercaseString];
            if([archExt containsObject: ext]) [out addObject: full];
            else if([imgExt containsObject: ext]) dirHasImage = YES;
        }
    }

    if(dirHasImage)
    {
        [out addObject: dir];
    }
    else
    {
        for(NSString * sub in subdirs)
        {
            [self collectWorksInDirectory: sub depth: depth + 1 into: out];
        }
    }
}


- (NSArray *)scannedWorkPathsInFolder:(NSURL *)folder
{
    NSMutableArray * out = [NSMutableArray array];
    [self collectWorksInDirectory: [folder path] depth: 0 into: out];
    return out;
}


- (IBAction)chooseFolder:(id)sender
{
    NSOpenPanel * panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles: NO];
    [panel setCanChooseDirectories: YES];
    [panel setAllowsMultipleSelection: NO];
    [panel setPrompt: NSLocalizedString(@"Choose", @"")];
    if([panel runModal] != NSModalResponseOK)
    {
        return;
    }
    NSURL * url = [[panel URLs] firstObject];
    NSData * bm = [url bookmarkDataWithOptions: NSURLBookmarkCreationWithSecurityScope
                includingResourceValuesForKeys: nil
                                 relativeToURL: nil
                                         error: NULL];
    if(!bm)
    {
        return;
    }

    NSMutableArray * folders = [NSMutableArray arrayWithArray: [self libraryFolderBookmarks]];
    /* Dedupe by resolved path. */
    for(NSData * existing in [self libraryFolderBookmarks])
    {
        if([[[self resolveBookmark: existing] path] isEqualToString: [url path]])
        {
            return [self reload];
        }
    }
    [folders addObject: bm];
    NSUserDefaults * d = [NSUserDefaults standardUserDefaults];
    [d setObject: folders forKey: SCLibraryFoldersKey];
    [d removeObjectForKey: SCLibraryFolderKey];
    [self reload];
}


- (IBAction)clearFolders:(id)sender
{
    NSUserDefaults * d = [NSUserDefaults standardUserDefaults];
    [d removeObjectForKey: SCLibraryFoldersKey];
    [d removeObjectForKey: SCLibraryFolderKey];
    [self reload];
}


- (void)reload
{
    NSMutableArray * keys = [NSMutableArray array];
    NSMutableSet * seen = [NSMutableSet set];

    for(NSString * k in [[SCProgressStore sharedStore] allWorkKeys])
    {
        if([k length] && ![seen containsObject: k])
        {
            [keys addObject: k];
            [seen addObject: k];
        }
    }

    NSMutableArray * folderNames = [NSMutableArray array];
    for(NSData * bm in [self libraryFolderBookmarks])
    {
        NSURL * folder = [self resolveBookmark: bm];
        if(!folder) continue;
        BOOL access = [folder startAccessingSecurityScopedResource];
        for(NSString * p in [self scannedWorkPathsInFolder: folder])
        {
            if([p length] && ![seen containsObject: p])
            {
                [keys addObject: p];
                [seen addObject: p];
            }
        }
        if(access) [folder stopAccessingSecurityScopedResource];
        [folderNames addObject: [folder lastPathComponent]];
    }

    if([folderNames count])
    {
        [folderLabel setStringValue: [NSString stringWithFormat:
            NSLocalizedString(@"%lu folder(s): %@", @""),
            (unsigned long)[folderNames count], [folderNames componentsJoinedByString: @", "]]];
    }
    else
    {
        [folderLabel setStringValue: NSLocalizedString(@"No library folder chosen", @"")];
    }

    [allKeys release];
    allKeys = [keys copy];

    /* Continue-reading: most-recently-read existing works (max 8). */
    NSFileManager * fm = [NSFileManager defaultManager];
    NSMutableArray * recent = [NSMutableArray array];
    for(NSString * k in [[SCProgressStore sharedStore] allWorkKeys])
    {
        if([k length] && [fm fileExistsAtPath: k])
        {
            [recent addObject: k];
            if([recent count] >= 8) break;
        }
    }
    [continueKeys release];
    continueKeys = [recent copy];
    [continueView reloadData];
    [self layoutRegions];

    [self applyFilterAndSort];
}


- (void)layoutRegions
{
    NSView * content = [[self window] contentView];
    NSRect cb = [content bounds];
    CGFloat headerH = 72.0;
    CGFloat labelH = 18.0;
    CGFloat stripH = [continueKeys count] ? 196.0 : 0.0;
    BOOL show = stripH > 0.0;
    CGFloat afterHeader = NSHeight(cb) - headerH;

    [continueLabel setHidden: !show];
    [continueScroll setHidden: !show];
    if(show)
    {
        [continueLabel setFrame: NSMakeRect(12, afterHeader - labelH, NSWidth(cb) - 24, labelH)];
        [continueScroll setFrame: NSMakeRect(0, afterHeader - stripH, NSWidth(cb), stripH - labelH)];
    }
    [gridScroll setFrame: NSMakeRect(0, 0, NSWidth(cb), afterHeader - stripH)];
}


- (void)windowDidResize:(NSNotification *)note
{
    [self layoutRegions];
}


- (void)handleContinueClick:(NSGestureRecognizer *)gesture
{
    NSPoint p = [gesture locationInView: continueView];
    NSIndexPath * ip = [continueView indexPathForItemAtPoint: p];
    if(ip && [ip item] >= 0 && [ip item] < (NSInteger)[continueKeys count])
    {
        NSString * key = [continueKeys objectAtIndex: [ip item]];
        if([key length])
        {
            [(SimpleComicAppDelegate *)[NSApp delegate] openWorkAtPath: key];
        }
    }
}


- (void)applyFilterAndSort
{
    NSString * q = [[searchField stringValue] lowercaseString];
    NSMutableArray * filtered = [NSMutableArray array];
    for(NSString * k in allKeys)
    {
        if([q length] == 0
           || [[[k lastPathComponent] lowercaseString] rangeOfString: q].location != NSNotFound)
        {
            [filtered addObject: k];
        }
    }

    SCProgressStore * store = [SCProgressStore sharedStore];
    NSFileManager * fm = [NSFileManager defaultManager];
    NSInteger mode = sortMode;
    [filtered sortUsingComparator: ^NSComparisonResult(NSString * a, NSString * b) {
        switch(mode)
        {
            case SCSortName:
                return [[a lastPathComponent] localizedStandardCompare: [b lastPathComponent]];
            case SCSortRecentAdded:
            {
                NSDate * da = [[fm attributesOfItemAtPath: a error: NULL] fileModificationDate];
                NSDate * db = [[fm attributesOfItemAtPath: b error: NULL] fileModificationDate];
                if(!da && !db) return NSOrderedSame;
                if(!da) return NSOrderedDescending;
                if(!db) return NSOrderedAscending;
                return [db compare: da];
            }
            case SCSortProgress:
            {
                NSInteger pa = [[[store recordForKey: a] objectForKey: @"lastPage"] integerValue];
                NSInteger pb = [[[store recordForKey: b] objectForKey: @"lastPage"] integerValue];
                if(pa == pb) return [[a lastPathComponent] localizedStandardCompare: [b lastPathComponent]];
                return pa > pb ? NSOrderedAscending : NSOrderedDescending;
            }
            case SCSortRecentRead:
            default:
            {
                NSDate * da = [[store recordForKey: a] objectForKey: @"updated"];
                NSDate * db = [[store recordForKey: b] objectForKey: @"updated"];
                if(!da && !db) return [[a lastPathComponent] localizedStandardCompare: [b lastPathComponent]];
                if(!da) return NSOrderedDescending;
                if(!db) return NSOrderedAscending;
                return [db compare: da];
            }
        }
    }];

    [workKeys release];
    workKeys = [filtered copy];
    [collectionView reloadData];
}


- (void)searchChanged:(id)sender
{
    [self applyFilterAndSort];
}


- (void)sortChanged:(id)sender
{
    sortMode = [sortPopup indexOfSelectedItem];
    [[NSUserDefaults standardUserDefaults] setInteger: sortMode forKey: SCLibrarySortKey];
    [self applyFilterAndSort];
}


- (void)coverSizeChanged:(id)sender
{
    CGFloat w = [sizeSlider doubleValue];
    [[NSUserDefaults standardUserDefaults] setDouble: w forKey: SCLibraryCoverWidthKey];
    NSCollectionViewFlowLayout * layout = (NSCollectionViewFlowLayout *)[collectionView collectionViewLayout];
    [layout setItemSize: NSMakeSize(w + 20, w * 1.4 + 36)];
    [layout invalidateLayout];
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
        [collectionView reloadItemsAtIndexPaths:
            [NSSet setWithObject: [NSIndexPath indexPathForItem: idx inSection: 0]]];
    }
    NSUInteger cidx = [continueKeys indexOfObject: key];
    if(cidx != NSNotFound)
    {
        [continueView reloadItemsAtIndexPaths:
            [NSSet setWithObject: [NSIndexPath indexPathForItem: cidx inSection: 0]]];
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
    return (cv == continueView) ? [continueKeys count] : [workKeys count];
}


- (NSCollectionViewItem *)collectionView:(NSCollectionView *)cv
     itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath
{
    SCLibraryItem * item = (SCLibraryItem *)[cv makeItemWithIdentifier: @"item" forIndexPath: indexPath];
    NSArray * source = (cv == continueView) ? continueKeys : workKeys;
    NSString * key = ([indexPath item] >= 0 && [indexPath item] < (NSInteger)[source count])
        ? [source objectAtIndex: [indexPath item]] : nil;
    item.representedObject = key;

    BOOL missing = [key length] && ![[NSFileManager defaultManager] fileExistsAtPath: key];

    NSImage * art = [[SCCoverCache sharedCache] coverForKey: key path: key];
    if(!art)
    {
        art = [[NSWorkspace sharedWorkspace] iconForFile: key];
    }
    [item.imageView setImage: art];
    /* Reset every time — collection items are reused. */
    [item.imageView setAlphaValue: missing ? 0.4 : 1.0];

    NSString * title = [[key lastPathComponent] stringByDeletingPathExtension];
    NSDictionary * record = [[SCProgressStore sharedStore] recordForKey: key];
    [item setUnread: (record == nil)];
    if(record)
    {
        NSInteger lastPage = [[record objectForKey: @"lastPage"] integerValue];
        title = [NSString stringWithFormat: @"%@\np.%ld", title, (long)(lastPage + 1)];
    }
    if(missing)
    {
        title = [NSString stringWithFormat: NSLocalizedString(@"%@\n(파일 없음)", @"Missing file label"),
                 [[key lastPathComponent] stringByDeletingPathExtension]];
    }
    [item.textField setStringValue: title];
    [item.textField setTextColor: missing ? [NSColor tertiaryLabelColor] : [NSColor labelColor]];

    return item;
}

@end
