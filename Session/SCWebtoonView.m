/*
    SCWebtoonView.m
 */

#import "SCWebtoonView.h"
#import "TSSTSessionWindowController.h"
#import "TSSTPage.h"
#import "SimpleComicAppDelegate.h"

/* Aspect (width / height) assumed for a page whose real dimensions are not
   known yet.  Korean webtoon panels are far taller than wide, so a tall
   estimate keeps the strip from collapsing before images decode. */
static const CGFloat SCDefaultAspect = 0.66f;

/* How many pages past the visible range to decode ahead of time. */
static const NSInteger SCPrefetchAhead = 4;
static const NSInteger SCPrefetchBehind = 1;


@implementation SCWebtoonView

@synthesize sessionController;


- (id)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame: frameRect];
    if(self)
    {
        pageOffsets = NULL;
        pageWidths = NULL;
        pageHeights = NULL;
        pageMeasured = NULL;
        pageCount = 0;
        layoutScale = 0.0f;
        layoutWidth = NSWidth(frameRect) > 1 ? NSWidth(frameRect) : 800;
        reportedPageIndex = -1;
        observingClipView = NO;

        imageCache = [[NSCache alloc] init];
        [imageCache setCountLimit: 8];
        loadingPages = [[NSMutableIndexSet alloc] init];
    }
    return self;
}


- (void)freeLayoutArrays
{
    free(pageOffsets);  pageOffsets = NULL;
    free(pageWidths);   pageWidths = NULL;
    free(pageHeights);  pageHeights = NULL;
    free(pageMeasured); pageMeasured = NULL;
}


- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [self freeLayoutArrays];
    [imageCache release];
    [loadingPages release];
    [pages release];
    [super dealloc];
}


- (BOOL)isFlipped
{
    return YES;
}


- (BOOL)isOpaque
{
    return YES;
}


#pragma mark - Page set


- (void)setPages:(NSArray *)pageArray
{
    if(pageArray == pages)
    {
        return;
    }

    [pageArray retain];
    [pages release];
    pages = pageArray;

    [self freeLayoutArrays];
    pageCount = [pages count];

    if(pageCount > 0)
    {
        pageOffsets  = (CGFloat *)calloc(pageCount + 1, sizeof(CGFloat));
        pageWidths   = (CGFloat *)calloc(pageCount, sizeof(CGFloat));
        pageHeights  = (CGFloat *)calloc(pageCount, sizeof(CGFloat));
        pageMeasured = (BOOL *)calloc(pageCount, sizeof(BOOL));

        for(NSUInteger i = 0; i < pageCount; ++i)
        {
            /* Core Data already caches the pixel size of any page that has
               ever been displayed; reuse it so the strip is laid out
               correctly without decoding every image up front. */
            TSSTPage * page = [pages objectAtIndex: i];
            CGFloat w = [[page valueForKey: @"width"] floatValue];
            CGFloat h = [[page valueForKey: @"height"] floatValue];
            if(w > 0.0f && h > 0.0f)
            {
                pageWidths[i] = w;
                pageHeights[i] = h;
                pageMeasured[i] = YES;
            }
        }
    }

    [imageCache removeAllObjects];
    [loadingPages removeAllIndexes];
    reportedPageIndex = -1;

    [self rebuildOffsetsForWidth: [self clipWidth]];
    [self setNeedsDisplay: YES];
}


#pragma mark - Layout


- (CGFloat)clipWidth
{
    NSScrollView * scrollView = [self enclosingScrollView];
    if(scrollView)
    {
        CGFloat width = NSWidth([[scrollView contentView] bounds]);
        if(width > 1)
        {
            return width;
        }
    }
    return layoutWidth > 1 ? layoutWidth : 800;
}


/* Pending per-page rotation (clockwise degrees) owned by the session
   controller, so live preview matches what will be saved on close. */
- (NSInteger)rotationForIndex:(NSUInteger)index
{
    if(index >= pageCount || !sessionController)
    {
        return 0;
    }
    NSInteger r = [sessionController pendingRotationForPage: [pages objectAtIndex: index]];
    return ((r % 360) + 360) % 360;
}


/* Measured pixel size with the pending rotation applied (90/270 swap
   width and height, changing the page's footprint in the strip). */
- (void)effectiveWidth:(CGFloat *)outW height:(CGFloat *)outH forIndex:(NSUInteger)index
{
    CGFloat w = pageWidths[index];
    CGFloat h = pageHeights[index];
    NSInteger r = [self rotationForIndex: index];
    if(r == 90 || r == 270)
    {
        CGFloat t = w; w = h; h = t;
    }
    *outW = w;
    *outH = h;
}


/* base rotated to match the page's pending rotation (or base if none). */
- (NSImage *)displayImage:(NSImage *)base forIndex:(NSUInteger)index
{
    if(!base || !sessionController || [self rotationForIndex: index] == 0)
    {
        return base;
    }
    NSImage * rotated = [sessionController rotatedImageIfNeeded: base
                                                        forPage: [pages objectAtIndex: index]];
    return rotated ? rotated : base;
}


/* Width of the widest measured page (rotation-aware); the strip is
   scaled so this page exactly fills the viewport width. */
- (CGFloat)widestMeasuredWidth
{
    CGFloat widest = 0.0f;
    for(NSUInteger i = 0; i < pageCount; ++i)
    {
        if(pageMeasured[i])
        {
            CGFloat w, h;
            [self effectiveWidth: &w height: &h forIndex: i];
            if(w > widest)
            {
                widest = w;
            }
        }
    }
    return widest;
}


- (void)rebuildOffsetsForWidth:(CGFloat)width
{
    if(width < 1)
    {
        width = 800;
    }
    layoutWidth = width;

    if(pageCount == 0 || pageOffsets == NULL)
    {
        layoutScale = 0.0f;
        [self setFrameSize: NSMakeSize(width, 1)];
        return;
    }

    CGFloat widest = [self widestMeasuredWidth];
    layoutScale = widest > 0.0f ? (width / widest) : 0.0f;

    pageOffsets[0] = 0.0f;
    for(NSUInteger i = 0; i < pageCount; ++i)
    {
        CGFloat height;
        CGFloat effW, effH;
        [self effectiveWidth: &effW height: &effH forIndex: i];
        if(pageMeasured[i] && layoutScale > 0.0f && effH > 0.0f)
        {
            height = effH * layoutScale;
        }
        else
        {
            /* Full-width placeholder until the real size is known. */
            height = width / SCDefaultAspect;
        }
        if(!isfinite(height) || height < 1.0f)
        {
            height = width / SCDefaultAspect;
        }
        pageOffsets[i + 1] = pageOffsets[i] + height;
    }

    CGFloat total = pageOffsets[pageCount];
    if(total < 1.0f)
    {
        total = 1.0f;
    }
    [self setFrameSize: NSMakeSize(width, total)];
}


- (NSUInteger)pageIndexForOffset:(CGFloat)y
{
    if(pageCount == 0)
    {
        return 0;
    }
    if(y <= 0.0f)
    {
        return 0;
    }
    if(y >= pageOffsets[pageCount])
    {
        return pageCount - 1;
    }

    NSUInteger lo = 0;
    NSUInteger hi = pageCount;          /* search in pageOffsets[0..pageCount] */
    while(hi - lo > 1)
    {
        NSUInteger mid = (lo + hi) / 2;
        if(pageOffsets[mid] <= y)
        {
            lo = mid;
        }
        else
        {
            hi = mid;
        }
    }
    return lo;
}


- (NSRect)rectForPageAtIndex:(NSUInteger)index
{
    if(index >= pageCount)
    {
        return NSZeroRect;
    }
    CGFloat viewWidth = NSWidth([self bounds]);
    CGFloat top = pageOffsets[index];
    CGFloat height = pageOffsets[index + 1] - top;

    CGFloat displayWidth;
    CGFloat effW, effH;
    [self effectiveWidth: &effW height: &effH forIndex: index];
    if(pageMeasured[index] && layoutScale > 0.0f && effW > 0.0f)
    {
        displayWidth = effW * layoutScale;
        if(displayWidth > viewWidth)
        {
            displayWidth = viewWidth;
        }
    }
    else
    {
        displayWidth = viewWidth;
    }

    CGFloat x = (viewWidth - displayWidth) * 0.5f;
    return NSMakeRect(x, top, displayWidth, height);
}


- (void)relayoutPreservingAnchor
{
    if(pageCount == 0)
    {
        [self rebuildOffsetsForWidth: [self clipWidth]];
        [self setNeedsDisplay: YES];
        return;
    }

    CGFloat oldOriginY = NSMinY([self visibleRect]);
    NSUInteger anchor = [self pageIndexForOffset: oldOriginY];
    CGFloat anchorHeight = pageOffsets[anchor + 1] - pageOffsets[anchor];
    CGFloat fraction = anchorHeight > 0.0f ? (oldOriginY - pageOffsets[anchor]) / anchorHeight : 0.0f;

    [self rebuildOffsetsForWidth: [self clipWidth]];

    CGFloat newAnchorHeight = pageOffsets[anchor + 1] - pageOffsets[anchor];
    CGFloat newOriginY = pageOffsets[anchor] + fraction * newAnchorHeight;
    [self scrollPoint: NSMakePoint(0.0f, newOriginY)];
    [self setNeedsDisplay: YES];
}


- (void)scrollToPageIndex:(NSInteger)index
{
    if(pageCount == 0)
    {
        return;
    }
    if(index < 0)
    {
        index = 0;
    }
    if((NSUInteger)index >= pageCount)
    {
        index = pageCount - 1;
    }
    reportedPageIndex = index;
    [self scrollPoint: NSMakePoint(0.0f, pageOffsets[index])];
    [self setNeedsDisplay: YES];
}


- (NSInteger)currentPageIndex
{
    if(pageCount == 0)
    {
        return 0;
    }
    return (NSInteger)[self pageIndexForOffset: NSMinY([self visibleRect])];
}


#pragma mark - Drawing


- (void)drawRect:(NSRect)dirtyRect
{
    NSColor * background = [[self enclosingScrollView] backgroundColor];
    if(!background)
    {
        background = [NSColor controlBackgroundColor];
    }
    [background set];
    NSRectFill(dirtyRect);

    if(pageCount == 0 || pageOffsets == NULL)
    {
        return;
    }

    NSUInteger first = [self pageIndexForOffset: NSMinY(dirtyRect)];
    CGFloat maxY = NSMaxY(dirtyRect);
    NSUInteger last = first;

    for(NSUInteger i = first; i < pageCount && pageOffsets[i] < maxY; ++i)
    {
        last = i;
        NSRect pageRect = [self rectForPageAtIndex: i];
        NSImage * image = [imageCache objectForKey: @(i)];
        if(image)
        {
            [[self displayImage: image forIndex: i] drawInRect: pageRect
                                                       fromRect: NSZeroRect
                                                      operation: NSCompositingOperationSourceOver
                                                       fraction: 1.0
                                                 respectFlipped: YES
                                                          hints: nil];
        }
        else
        {
            [self requestImageForIndex: i];
        }
    }

    /* Decode a window of pages around what is on screen so scrolling stays
       smooth without ever holding the whole chapter in memory. */
    NSInteger prefetchStart = (NSInteger)first - SCPrefetchBehind;
    NSInteger prefetchEnd = (NSInteger)last + SCPrefetchAhead;
    for(NSInteger p = prefetchStart; p <= prefetchEnd; ++p)
    {
        if(p >= 0 && (NSUInteger)p < pageCount)
        {
            [self requestImageForIndex: (NSUInteger)p];
        }
    }
}


#pragma mark - Lazy image loading


- (void)requestImageForIndex:(NSUInteger)index
{
    if(index >= pageCount)
    {
        return;
    }
    if([imageCache objectForKey: @(index)])
    {
        return;
    }
    if([loadingPages containsIndex: index])
    {
        return;
    }
    [loadingPages addIndex: index];

    TSSTPage * page = [pages objectAtIndex: index];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        @autoreleasepool
        {
            NSData * data = [page pageData];
            NSImage * image = nil;
            CGFloat pixelWidth = 0.0f;
            CGFloat pixelHeight = 0.0f;

            if(data)
            {
                image = [[NSImage alloc] initWithData: data];
                NSArray * reps = [image representations];
                NSImageRep * rep = [reps count] ? [reps objectAtIndex: 0] : nil;
                NSInteger pw = rep ? [rep pixelsWide] : 0;
                NSInteger ph = rep ? [rep pixelsHigh] : 0;

                if(image && pw > 0 && ph > 0)
                {
                    pixelWidth = (CGFloat)pw;
                    pixelHeight = (CGFloat)ph;
                    [image setCacheMode: NSImageCacheNever];
                    [image setSize: NSMakeSize(pixelWidth, pixelHeight)];
                }
                else
                {
                    [image release];
                    image = nil;
                }
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                [loadingPages removeIndex: index];

                if(index >= pageCount || page != [pages objectAtIndex: index])
                {
                    /* The page set changed while this decode was in flight. */
                    [image release];
                    return;
                }

                if(image)
                {
                    [imageCache setObject: image forKey: @(index)];

                    BOOL layoutChanged = NO;
                    if(pixelWidth > 0.0f && pixelHeight > 0.0f && !pageMeasured[index])
                    {
                        pageMeasured[index] = YES;
                        pageWidths[index] = pixelWidth;
                        pageHeights[index] = pixelHeight;
                        /* A newly measured page changes its own height and
                           may set a new widest-page reference, so the whole
                           strip is relaid out around the current anchor. */
                        layoutChanged = YES;
                    }

                    if(layoutChanged)
                    {
                        [self relayoutPreservingAnchor];
                    }
                    else
                    {
                        [self setNeedsDisplayInRect: [self rectForPageAtIndex: index]];
                    }
                }
                [image release];
            });
        }
    });
}


#pragma mark - Scroll tracking


- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];

    NSScrollView * scrollView = [self enclosingScrollView];
    NSClipView * clipView = [scrollView contentView];

    if([self window] && clipView && !observingClipView)
    {
        [clipView setPostsBoundsChangedNotifications: YES];
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(clipViewBoundsChanged:)
                                                     name: NSViewBoundsDidChangeNotification
                                                   object: clipView];
        observingClipView = YES;
    }
    else if(![self window] && observingClipView)
    {
        [[NSNotificationCenter defaultCenter] removeObserver: self
                                                        name: NSViewBoundsDidChangeNotification
                                                      object: nil];
        observingClipView = NO;
    }
}


- (void)clipViewBoundsChanged:(NSNotification *)notification
{
    NSInteger index = [self currentPageIndex];
    if(index != reportedPageIndex)
    {
        reportedPageIndex = index;
        [sessionController webtoonScrolledToPageIndex: index];
    }
}


#pragma mark - Loupe


/*  Returns a magnified image of the strip centred on the cursor.  rect is
    given in this (flipped) view's coordinates: rect.origin is the point
    under the cursor and rect.size is the loupe's pixel size. */
- (NSImage *)imageInRect:(NSRect)rect
{
    if(pageCount == 0 || pageOffsets == NULL)
    {
        return nil;
    }
    NSSize loupeSize = rect.size;
    if(loupeSize.width < 1.0f || loupeSize.height < 1.0f)
    {
        return nil;
    }

    float power = [[[NSUserDefaults standardUserDefaults] valueForKey: TSSTLoupePower] floatValue];
    if(power < 1.0f)
    {
        power = 2.0f;
    }

    NSPoint cursor = rect.origin;
    CGFloat srcW = loupeSize.width / power;
    CGFloat srcH = loupeSize.height / power;
    NSRect src = NSMakeRect(cursor.x - srcW * 0.5f,
                            cursor.y - srcH * 0.5f,
                            srcW, srcH);

    NSImage * out = [[NSImage alloc] initWithSize: loupeSize];
    [out lockFocus];

    NSColor * background = [[self enclosingScrollView] backgroundColor];
    if(!background)
    {
        background = [NSColor blackColor];
    }
    [background set];
    NSRectFill(NSMakeRect(0.0f, 0.0f, loupeSize.width, loupeSize.height));
    [[NSGraphicsContext currentContext] setImageInterpolation: NSImageInterpolationHigh];

    NSUInteger first = [self pageIndexForOffset: NSMinY(src) < 0.0f ? 0.0f : NSMinY(src)];
    CGFloat bandMaxY = NSMaxY(src);
    for(NSUInteger i = first; i < pageCount && pageOffsets[i] < bandMaxY; ++i)
    {
        NSImage * image = [imageCache objectForKey: @(i)];
        if(!image)
        {
            NSData * data = [[pages objectAtIndex: i] pageData];
            if(data)
            {
                image = [[[NSImage alloc] initWithData: data] autorelease];
                if(image)
                {
                    [imageCache setObject: image forKey: @(i)];
                }
            }
        }
        if(!image)
        {
            continue;
        }

        NSRect pr = [self rectForPageAtIndex: i];
        CGFloat dstX = (NSMinX(pr) - NSMinX(src)) * power;
        CGFloat dstW = NSWidth(pr) * power;
        CGFloat dstY = loupeSize.height - (NSMaxY(pr) - NSMinY(src)) * power;
        CGFloat dstH = NSHeight(pr) * power;

        [[self displayImage: image forIndex: i] drawInRect: NSMakeRect(dstX, dstY, dstW, dstH)
                                                   fromRect: NSZeroRect
                                                  operation: NSCompositingOperationSourceOver
                                                   fraction: 1.0
                                             respectFlipped: YES
                                                      hints: nil];
    }

    [out unlockFocus];
    return [out autorelease];
}


#pragma mark - Keyboard


- (BOOL)acceptsFirstResponder
{
    return YES;
}


- (void)scrollByVertical:(CGFloat)dy
{
    NSRect visible = [self visibleRect];
    CGFloat maxY = NSMaxY([self bounds]) - NSHeight(visible);
    if(maxY < 0.0f)
    {
        maxY = 0.0f;
    }
    CGFloat newY = NSMinY(visible) + dy;
    if(newY < 0.0f)
    {
        newY = 0.0f;
    }
    if(newY > maxY)
    {
        newY = maxY;
    }
    [self scrollPoint: NSMakePoint(0.0f, newY)];
}


- (void)keyDown:(NSEvent *)event
{
    NSString * chars = [event charactersIgnoringModifiers];
    unichar key = [chars length] ? [chars characterAtIndex: 0] : 0;
    BOOL shift = ([event modifierFlags] & NSEventModifierFlagShift) != 0;
    CGFloat pageStep = NSHeight([self visibleRect]) * 0.94f;
    CGFloat lineStep = 80.0f;

    switch(key)
    {
        case ' ':
            [self scrollByVertical: shift ? -pageStep : pageStep];
            break;
        case NSPageDownFunctionKey:
            [self scrollByVertical: pageStep];
            break;
        case NSPageUpFunctionKey:
            [self scrollByVertical: -pageStep];
            break;
        case NSDownArrowFunctionKey:
            [self scrollByVertical: lineStep];
            break;
        case NSUpArrowFunctionKey:
            [self scrollByVertical: -lineStep];
            break;
        case NSHomeFunctionKey:
            [self scrollPoint: NSZeroPoint];
            break;
        case NSEndFunctionKey:
        {
            CGFloat maxY = NSMaxY([self bounds]) - NSHeight([self visibleRect]);
            [self scrollPoint: NSMakePoint(0.0f, maxY < 0.0f ? 0.0f : maxY)];
            break;
        }
        default:
            [super keyDown: event];
            break;
    }
}

@end
