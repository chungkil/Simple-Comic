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

static NSString * const SCLibraryFolderKey = @"SCLibraryFolderBookmark";


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

        /* Header bar: choose-folder button + current folder label. */
        NSView * content = [[[NSView alloc] initWithFrame: [[window contentView] bounds]] autorelease];
        [content setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
        CGFloat barH = 40.0;
        NSRect cb = [content bounds];

        NSButton * chooseButton = [[[NSButton alloc] initWithFrame:
            NSMakeRect(10, NSMaxY(cb) - barH + 6, 150, 28)] autorelease];
        [chooseButton setTitle: NSLocalizedString(@"Choose Folder…", @"")];
        [chooseButton setBezelStyle: NSBezelStyleRounded];
        [chooseButton setTarget: self];
        [chooseButton setAction: @selector(chooseFolder:)];
        [chooseButton setAutoresizingMask: NSViewMinYMargin];
        [content addSubview: chooseButton];

        folderLabel = [[NSTextField alloc] initWithFrame:
            NSMakeRect(170, NSMaxY(cb) - barH + 9, NSWidth(cb) - 180, 22)];
        [folderLabel setEditable: NO];
        [folderLabel setBordered: NO];
        [folderLabel setDrawsBackground: NO];
        [folderLabel setFont: [NSFont systemFontOfSize: 11]];
        [folderLabel setTextColor: [NSColor secondaryLabelColor]];
        [folderLabel setLineBreakMode: NSLineBreakByTruncatingMiddle];
        [folderLabel setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
        [content addSubview: folderLabel];

        [scrollView setFrame: NSMakeRect(0, 0, NSWidth(cb), NSHeight(cb) - barH)];
        [content addSubview: scrollView];

        [window setContentView: content];

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
    [folderLabel release];
    [workKeys release];
    [super dealloc];
}


- (NSURL *)libraryFolderURL
{
    NSData * bm = [[NSUserDefaults standardUserDefaults] objectForKey: SCLibraryFolderKey];
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


- (BOOL)folderHasImage:(NSString *)dirPath
{
    NSArray * imgExt = [TSSTPage imageExtensions];
    for(NSString * n in [[NSFileManager defaultManager] contentsOfDirectoryAtPath: dirPath error: NULL])
    {
        if([imgExt containsObject: [[n pathExtension] lowercaseString]])
        {
            return YES;
        }
    }
    return NO;
}


/* Top-level archives and image-containing subfolders of the chosen
   library folder (caller must hold security-scoped access). */
- (NSArray *)scannedWorkPathsInFolder:(NSURL *)folder
{
    NSFileManager * fm = [NSFileManager defaultManager];
    NSString * dir = [folder path];
    NSMutableArray * result = [NSMutableArray array];
    NSArray * names = [[fm contentsOfDirectoryAtPath: dir error: NULL]
                       sortedArrayUsingSelector: @selector(localizedStandardCompare:)];
    NSArray * archExt = [TSSTManagedArchive archiveExtensions];
    for(NSString * name in names)
    {
        if([name hasPrefix: @"."]) continue;
        NSString * full = [dir stringByAppendingPathComponent: name];
        BOOL isDir = NO;
        if(![fm fileExistsAtPath: full isDirectory: &isDir]) continue;
        if(isDir)
        {
            if([self folderHasImage: full]) [result addObject: full];
        }
        else if([archExt containsObject: [[name pathExtension] lowercaseString]])
        {
            [result addObject: full];
        }
    }
    return result;
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
    if(bm)
    {
        [[NSUserDefaults standardUserDefaults] setObject: bm forKey: SCLibraryFolderKey];
        [self reload];
    }
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

    NSURL * folder = [self libraryFolderURL];
    if(folder)
    {
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
        [folderLabel setStringValue: [folder path]];
    }
    else
    {
        [folderLabel setStringValue: NSLocalizedString(@"No library folder chosen", @"")];
    }

    [workKeys release];
    workKeys = [keys copy];
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
