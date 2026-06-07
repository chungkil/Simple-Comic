//
//  SCExposeWindowController.m
//  Simple Comic
//

#import "SCExposeWindowController.h"

static NSString * const SCExposePasteboardType = @"com.dancingtortoise.simplecomic.expose.page";
static const CGFloat SCExposeItemSize = 180.0;
static const CGFloat SCExposeItemSpacing = 8.0;
static const CGFloat SCExposeSectionInset = 24.0;
static const CGFloat SCExposeHoverDelay = 0.05;
static const CGFloat SCExposePreviewMax = 720.0;


#pragma mark - Item

@class SCExposeItem;

@protocol SCExposeItemDelegate <NSObject>
- (void)exposeItem:(SCExposeItem *)item hoverEntered:(BOOL)entered;
@end


@interface SCExposeItem : NSCollectionViewItem
@property (assign, nonatomic) id <SCExposeItemDelegate> itemDelegate;
@property (assign, nonatomic) NSInteger pageIndex;
@property (assign, nonatomic) BOOL isCurrent;
- (void)setThumbnail:(NSImage *)image label:(NSString *)label;
@end


@implementation SCExposeItem
{
    NSImageView * _imageView;
    NSTextField * _label;
    NSView * _selectionRing;
    NSTrackingArea * _tracking;
}

- (void)loadView
{
    NSView * v = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, SCExposeItemSize, SCExposeItemSize)] autorelease];
    [v setWantsLayer: YES];
    v.layer.backgroundColor = [[NSColor colorWithCalibratedWhite: 0 alpha: 0.25] CGColor];
    v.layer.cornerRadius = 6.0;

    _selectionRing = [[NSView alloc] initWithFrame: [v bounds]];
    [_selectionRing setWantsLayer: YES];
    _selectionRing.layer.borderColor = [[NSColor controlAccentColor] CGColor];
    _selectionRing.layer.borderWidth = 0.0;
    _selectionRing.layer.cornerRadius = 6.0;
    [_selectionRing setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
    [v addSubview: _selectionRing];
    [_selectionRing release];

    _imageView = [[NSImageView alloc] initWithFrame: NSInsetRect([v bounds], 6, 22)];
    [_imageView setImageScaling: NSImageScaleProportionallyUpOrDown];
    [_imageView setImageAlignment: NSImageAlignCenter];
    [_imageView setImageFrameStyle: NSImageFrameNone];
    [_imageView setEditable: NO];
    [_imageView setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
    [v addSubview: _imageView];
    [_imageView release];

    _label = [[NSTextField alloc] initWithFrame: NSMakeRect(4, 2, NSWidth([v bounds]) - 8, 16)];
    [_label setBezeled: NO];
    [_label setEditable: NO];
    [_label setSelectable: NO];
    [_label setDrawsBackground: NO];
    [_label setAlignment: NSTextAlignmentCenter];
    [_label setFont: [NSFont systemFontOfSize: 10]];
    [_label setTextColor: [NSColor whiteColor]];
    [_label setLineBreakMode: NSLineBreakByTruncatingMiddle];
    [_label setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
    [v addSubview: _label];
    [_label release];

    [self setView: v];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    _tracking = [[NSTrackingArea alloc] initWithRect: NSZeroRect
                                             options: NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                               owner: self
                                            userInfo: nil];
    [self.view addTrackingArea: _tracking];
}

- (void)dealloc
{
    if(_tracking)
    {
        [self.view removeTrackingArea: _tracking];
        [_tracking release];
    }
    [super dealloc];
}

- (void)setThumbnail:(NSImage *)image label:(NSString *)label
{
    [_imageView setImage: image];
    [_label setStringValue: label ?: @""];
}

- (void)setSelected:(BOOL)selected
{
    [super setSelected: selected];
    [self updateRing];
}

- (void)setIsCurrent:(BOOL)isCurrent
{
    _isCurrent = isCurrent;
    [self updateRing];
}

- (void)updateRing
{
    if(self.isSelected)
    {
        _selectionRing.layer.borderColor = [[NSColor controlAccentColor] CGColor];
        _selectionRing.layer.borderWidth = 3.0;
    }
    else if(self.isCurrent)
    {
        _selectionRing.layer.borderColor = [[NSColor colorWithCalibratedWhite: 1 alpha: 0.7] CGColor];
        _selectionRing.layer.borderWidth = 2.0;
    }
    else
    {
        _selectionRing.layer.borderWidth = 0.0;
    }
}

- (void)mouseEntered:(NSEvent *)event
{
    [self.itemDelegate exposeItem: self hoverEntered: YES];
}

- (void)mouseExited:(NSEvent *)event
{
    [self.itemDelegate exposeItem: self hoverEntered: NO];
}

@end


#pragma mark - Window (Esc to dismiss, Delete to remove selection)

@class SCExposeWindowController;

@interface SCExposePanel : NSPanel
@property (assign, nonatomic) SCExposeWindowController * exposeController;
@end

@implementation SCExposePanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
- (void)keyDown:(NSEvent *)event
{
    /* Forward keystrokes that the Expose window cares about (Delete /
       Backspace / Return) to the controller.  Everything else falls
       through so Esc still works via cancelOperation: and the system
       beep fires on unhandled keys. */
    if([(id)self.exposeController handleKeyDown: event]) return;
    [super keyDown: event];
}
@end


#pragma mark - Collection view (keyDown forwarder)

/*  NSCollectionView's own -keyDown: swallows keys it doesn't recognize
    (Delete / Backspace / Return) and beeps instead of letting them
    propagate.  This subclass forwards those keys to the window so the
    panel's -keyDown: override can route them to the controller. */
@interface SCExposeCollectionView : NSCollectionView
@end

@implementation SCExposeCollectionView
- (void)keyDown:(NSEvent *)event
{
    NSString * chars = [event charactersIgnoringModifiers];
    if([chars length] > 0)
    {
        unichar ch = [chars characterAtIndex: 0];
        if(ch == NSDeleteCharacter || ch == NSBackspaceCharacter ||
           ch == NSDeleteFunctionKey || ch == NSCarriageReturnCharacter ||
           ch == NSNewlineCharacter || ch == NSEnterCharacter)
        {
            [[self window] keyDown: event];
            return;
        }
    }
    [super keyDown: event];
}
@end


#pragma mark - Controller

@interface SCExposeWindowController () <NSCollectionViewDataSource, NSCollectionViewDelegate, NSCollectionViewDelegateFlowLayout, SCExposeItemDelegate>
- (BOOL)handleKeyDown:(NSEvent *)event;
@end


@implementation SCExposeWindowController
{
    NSCollectionView * _collectionView;
    NSScrollView * _scrollView;
    NSPanel * _previewPanel;
    NSImageView * _previewImageView;
    NSInteger _previewIndex;
    NSTimer * _previewDelayTimer;
    SCExposeItem * _pendingItem;
    id <SCExposeViewDelegate> _externalDelegate;
    BOOL _shown;
}

+ (instancetype)sharedController
{
    static SCExposeWindowController * sc = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ sc = [[SCExposeWindowController alloc] init]; });
    return sc;
}

- (instancetype)init
{
    NSRect contentRect = NSMakeRect(0, 0, 1024, 768);
    SCExposePanel * panel = [[SCExposePanel alloc] initWithContentRect: contentRect
                                                             styleMask: NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                               backing: NSBackingStoreBuffered
                                                                 defer: NO];
    [panel setOpaque: NO];
    [panel setBackgroundColor: [NSColor clearColor]];
    [panel setHasShadow: NO];
    [panel setReleasedWhenClosed: NO];
    [panel setLevel: NSFloatingWindowLevel];
    [panel setAcceptsMouseMovedEvents: YES];
    [panel setHidesOnDeactivate: NO];

    self = [super initWithWindow: panel];
    [panel release];
    if(self)
    {
        [(SCExposePanel *)panel setExposeController: self];
        _previewIndex = -1;
        [self setupContent];
    }
    return self;
}

- (void)setupContent
{
    NSWindow * w = [self window];
    NSRect bounds = [[w contentView] bounds];

    NSVisualEffectView * blur = [[NSVisualEffectView alloc] initWithFrame: bounds];
    [blur setMaterial: NSVisualEffectMaterialHUDWindow];
    [blur setBlendingMode: NSVisualEffectBlendingModeBehindWindow];
    [blur setState: NSVisualEffectStateActive];
    [blur setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
    [w setContentView: blur];
    [blur release];

    NSView * content = [w contentView];

    NSCollectionViewFlowLayout * layout = [[NSCollectionViewFlowLayout alloc] init];
    [layout setItemSize: NSMakeSize(SCExposeItemSize, SCExposeItemSize)];
    [layout setMinimumInteritemSpacing: SCExposeItemSpacing];
    [layout setMinimumLineSpacing: SCExposeItemSpacing];
    [layout setSectionInset: NSEdgeInsetsMake(SCExposeSectionInset, SCExposeSectionInset, SCExposeSectionInset, SCExposeSectionInset)];

    _collectionView = [[SCExposeCollectionView alloc] initWithFrame: [content bounds]];
    [_collectionView setCollectionViewLayout: layout];
    [_collectionView setDataSource: self];
    [_collectionView setDelegate: self];
    [_collectionView setSelectable: YES];
    /* Cmd / Shift click extends the selection; Delete removes all
       selected pages.  Plain click still jumps to a single page. */
    [_collectionView setAllowsMultipleSelection: YES];
    [_collectionView setBackgroundColors: @[[NSColor clearColor]]];
    [_collectionView registerForDraggedTypes: @[SCExposePasteboardType]];
    [_collectionView setDraggingSourceOperationMask: NSDragOperationMove forLocal: YES];
    [layout release];

    _scrollView = [[NSScrollView alloc] initWithFrame: [content bounds]];
    [_scrollView setHasVerticalScroller: YES];
    [_scrollView setHasHorizontalScroller: NO];
    [_scrollView setAutohidesScrollers: YES];
    [_scrollView setBorderType: NSNoBorder];
    [_scrollView setDrawsBackground: NO];
    [_scrollView setDocumentView: _collectionView];
    [_scrollView setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
    [content addSubview: _scrollView];

    [_collectionView release];

    /* Hover preview panel */
    _previewPanel = [[NSPanel alloc] initWithContentRect: NSMakeRect(0, 0, 400, 400)
                                               styleMask: NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                 backing: NSBackingStoreBuffered
                                                   defer: NO];
    [_previewPanel setOpaque: NO];
    [_previewPanel setBackgroundColor: [NSColor clearColor]];
    [_previewPanel setHasShadow: YES];
    [_previewPanel setLevel: NSFloatingWindowLevel + 1];
    [_previewPanel setHidesOnDeactivate: NO];
    [_previewPanel setIgnoresMouseEvents: YES];

    NSView * previewContent = [[NSView alloc] initWithFrame: [[_previewPanel contentView] bounds]];
    [previewContent setWantsLayer: YES];
    previewContent.layer.backgroundColor = [[NSColor colorWithCalibratedWhite: 0 alpha: 0.85] CGColor];
    previewContent.layer.cornerRadius = 8.0;
    [previewContent setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];

    _previewImageView = [[NSImageView alloc] initWithFrame: NSInsetRect([previewContent bounds], 8, 8)];
    [_previewImageView setImageScaling: NSImageScaleProportionallyUpOrDown];
    [_previewImageView setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
    [previewContent addSubview: _previewImageView];
    [_previewImageView release];

    [_previewPanel setContentView: previewContent];
    [previewContent release];

    [_collectionView registerClass: [SCExposeItem class] forItemWithIdentifier: @"SCExposeItem"];
}

- (void)dealloc
{
    [_previewDelayTimer invalidate];
    [_previewDelayTimer release];
    [_scrollView release];
    [_previewPanel release];
    [super dealloc];
}

- (BOOL)isShown { return _shown; }

- (void)showForParentWindow:(NSWindow *)parent delegate:(id <SCExposeViewDelegate>)delegate
{
    _externalDelegate = delegate;
    NSScreen * screen = [parent screen] ?: [NSScreen mainScreen];
    NSRect frame = [screen frame];
    [[self window] setFrame: frame display: NO];
    [_collectionView reloadData];
    _shown = YES;
    [[self window] makeKeyAndOrderFront: self];

    NSInteger current = [_externalDelegate currentPageIndexForExposeView: self];
    if(current >= 0 && current < [_externalDelegate pageCountForExposeView: self])
    {
        NSIndexPath * ip = [NSIndexPath indexPathForItem: current inSection: 0];
        [_collectionView scrollToItemsAtIndexPaths: [NSSet setWithObject: ip] scrollPosition: NSCollectionViewScrollPositionCenteredVertically];
    }
}

- (void)hide
{
    [self cancelHoverPreview];
    [_previewPanel orderOut: nil];
    [[self window] orderOut: nil];
    _shown = NO;
    _externalDelegate = nil;
}

- (void)reloadData
{
    [_collectionView reloadData];
}

- (void)cancelOperation:(id)sender
{
    [self hide];
}

#pragma mark NSCollectionViewDataSource

- (NSInteger)collectionView:(NSCollectionView *)cv numberOfItemsInSection:(NSInteger)section
{
    return _externalDelegate ? [_externalDelegate pageCountForExposeView: self] : 0;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)cv itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath
{
    SCExposeItem * item = [cv makeItemWithIdentifier: @"SCExposeItem" forIndexPath: indexPath];
    NSInteger i = [indexPath item];
    NSImage * thumb = [_externalDelegate exposeView: self thumbnailForPageAtIndex: i];
    NSString * name = [_externalDelegate exposeView: self nameForPageAtIndex: i];
    [item setThumbnail: thumb label: name];
    [item setPageIndex: i];
    [item setItemDelegate: self];
    [item setIsCurrent: (i == [_externalDelegate currentPageIndexForExposeView: self])];
    return item;
}

#pragma mark NSCollectionViewDelegate

- (void)collectionView:(NSCollectionView *)cv didSelectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths
{
    NSIndexPath * ip = [indexPaths anyObject];
    if(!ip) return;

    /* If the user is extending a multi-selection with Cmd / Shift,
       just keep the selection — don't dismiss and jump.  A plain
       click (no modifiers) still acts as "open this page". */
    NSEventModifierFlags mods = [NSEvent modifierFlags] &
        (NSEventModifierFlagCommand | NSEventModifierFlagShift);
    if(mods != 0)
    {
        /* Modifier-click is a multi-selection gesture — dismiss any hover
           preview already on screen so it doesn't cover the grid. */
        [self cancelHoverPreview];
        [_previewPanel orderOut: nil];
        _previewIndex = -1;
        return;
    }

    NSInteger i = [ip item];
    [self cancelHoverPreview];
    [_previewPanel orderOut: nil];
    id <SCExposeViewDelegate> d = [_externalDelegate retain];
    [self hide];
    [d exposeView: self didSelectPageAtIndex: i];
    [d release];
}

- (BOOL)handleKeyDown:(NSEvent *)event
{
    NSString * chars = [event charactersIgnoringModifiers];
    if([chars length] == 0) return NO;
    unichar ch = [chars characterAtIndex: 0];

    if(ch == NSDeleteCharacter || ch == NSBackspaceCharacter || ch == NSDeleteFunctionKey)
    {
        [self deleteSelectedPages];
        return YES;
    }
    if(ch == NSCarriageReturnCharacter || ch == NSNewlineCharacter || ch == NSEnterCharacter)
    {
        /* Enter on a multi-selection: jump to the first selected page. */
        NSSet<NSIndexPath *> * sel = [_collectionView selectionIndexPaths];
        NSIndexPath * first = nil;
        for(NSIndexPath * ip in sel)
        {
            if(!first || [ip item] < [first item]) first = ip;
        }
        if(!first) return NO;
        [self collectionView: _collectionView didSelectItemsAtIndexPaths: [NSSet setWithObject: first]];
        return YES;
    }
    return NO;
}

- (IBAction)delete:(id)sender
{
    [self deleteSelectedPages];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if([item action] == @selector(delete:))
    {
        return _shown && [[_collectionView selectionIndexPaths] count] > 0;
    }
    return YES;
}

- (void)deleteSelectedPages
{
    NSSet<NSIndexPath *> * sel = [_collectionView selectionIndexPaths];
    if([sel count] == 0)
    {
        NSBeep();
        return;
    }
    if(![_externalDelegate respondsToSelector: @selector(exposeView:didRequestDeletePagesAtIndexes:)])
    {
        NSBeep();
        return;
    }

    NSMutableIndexSet * indexes = [NSMutableIndexSet indexSet];
    for(NSIndexPath * ip in sel) [indexes addIndex: (NSUInteger)[ip item]];

    [self cancelHoverPreview];
    [_previewPanel orderOut: nil];
    _previewIndex = -1;

    [_externalDelegate exposeView: self didRequestDeletePagesAtIndexes: indexes];
    [_collectionView deselectAll: nil];
    [_collectionView reloadData];
}

#pragma mark Drag & drop reorder

- (BOOL)collectionView:(NSCollectionView *)cv canDragItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths withEvent:(NSEvent *)event
{
    return YES;
}

- (id <NSPasteboardWriting>)collectionView:(NSCollectionView *)cv pasteboardWriterForItemAtIndexPath:(NSIndexPath *)indexPath
{
    NSPasteboardItem * pbItem = [[[NSPasteboardItem alloc] init] autorelease];
    [pbItem setString: [NSString stringWithFormat: @"%ld", (long)[indexPath item]] forType: SCExposePasteboardType];
    return pbItem;
}

- (NSDragOperation)collectionView:(NSCollectionView *)cv
                     validateDrop:(id <NSDraggingInfo>)draggingInfo
                proposedIndexPath:(NSIndexPath * __autoreleasing *)proposedIndexPath
                    dropOperation:(NSCollectionViewDropOperation *)proposedDropOperation
{
    if(*proposedDropOperation == NSCollectionViewDropOn)
    {
        *proposedDropOperation = NSCollectionViewDropBefore;
    }
    return NSDragOperationMove;
}

- (BOOL)collectionView:(NSCollectionView *)cv
            acceptDrop:(id <NSDraggingInfo>)draggingInfo
             indexPath:(NSIndexPath *)indexPath
         dropOperation:(NSCollectionViewDropOperation)dropOperation
{
    NSString * payload = [[draggingInfo draggingPasteboard] stringForType: SCExposePasteboardType];
    if(!payload) return NO;
    NSInteger from = [payload integerValue];
    NSInteger to = [indexPath item];
    /* NSCollectionView reports the gap index; adjust so "drop after slot k"
       lands at index k when from < to (because removing from shifts things). */
    if(from < to) to -= 1;
    if(from == to) return NO;
    [_externalDelegate exposeView: self didMovePageFromIndex: from toIndex: to];
    [_collectionView reloadData];
    return YES;
}

#pragma mark Hover preview

- (void)exposeItem:(SCExposeItem *)item hoverEntered:(BOOL)entered
{
    if(entered)
    {
        if(_pendingItem == item) return;
        _pendingItem = item;
        [self cancelHoverPreview];
        /* While extending a multi-selection (Cmd/Shift held), don't pop the
           large hover preview — it covers the grid and fights the selection. */
        if([NSEvent modifierFlags] & (NSEventModifierFlagCommand | NSEventModifierFlagShift))
        {
            [_previewPanel orderOut: nil];
            _previewIndex = -1;
            return;
        }
        _previewDelayTimer = [[NSTimer scheduledTimerWithTimeInterval: SCExposeHoverDelay
                                                               target: self
                                                             selector: @selector(showHoverPreview:)
                                                             userInfo: nil
                                                              repeats: NO] retain];
    }
    else
    {
        if(_pendingItem == item)
        {
            _pendingItem = nil;
        }
        [self cancelHoverPreview];
        [_previewPanel orderOut: nil];
        _previewIndex = -1;
    }
}

- (void)cancelHoverPreview
{
    [_previewDelayTimer invalidate];
    [_previewDelayTimer release];
    _previewDelayTimer = nil;
}

- (void)showHoverPreview:(NSTimer *)t
{
    [_previewDelayTimer release];
    _previewDelayTimer = nil;
    /* A modifier was pressed after the timer was scheduled — the user is
       extending a selection, so suppress the preview. */
    if([NSEvent modifierFlags] & (NSEventModifierFlagCommand | NSEventModifierFlagShift)) return;
    SCExposeItem * item = _pendingItem;
    if(!item || ![self isShown]) return;

    NSInteger idx = item.pageIndex;
    if(idx == _previewIndex && [_previewPanel isVisible]) return;
    _previewIndex = idx;

    NSImage * full = [_externalDelegate exposeView: self fullImageForPageAtIndex: idx];
    if(!full) full = [_externalDelegate exposeView: self thumbnailForPageAtIndex: idx];
    if(!full) return;

    NSSize is = [full size];
    if(is.width <= 0 || is.height <= 0) return;
    CGFloat scale = MIN(SCExposePreviewMax / is.width, SCExposePreviewMax / is.height);
    if(scale > 1.0) scale = 1.0;
    NSSize panelSize = NSMakeSize(round(is.width * scale) + 16, round(is.height * scale) + 16);

    NSRect itemFrame = [item.view convertRect: [item.view bounds] toView: nil];
    itemFrame = [[self window] convertRectToScreen: itemFrame];
    NSRect screen = [[[self window] screen] visibleFrame];

    NSPoint origin;
    origin.x = NSMaxX(itemFrame) + 12;
    origin.y = NSMidY(itemFrame) - panelSize.height / 2;
    if(origin.x + panelSize.width > NSMaxX(screen))
    {
        origin.x = NSMinX(itemFrame) - panelSize.width - 12;
    }
    if(origin.x < NSMinX(screen)) origin.x = NSMinX(screen) + 8;
    if(origin.y < NSMinY(screen)) origin.y = NSMinY(screen) + 8;
    if(origin.y + panelSize.height > NSMaxY(screen))
        origin.y = NSMaxY(screen) - panelSize.height - 8;

    [_previewImageView setImage: full];
    [_previewPanel setFrame: NSMakeRect(origin.x, origin.y, panelSize.width, panelSize.height) display: NO];
    [[self window] addChildWindow: _previewPanel ordered: NSWindowAbove];
}

@end
