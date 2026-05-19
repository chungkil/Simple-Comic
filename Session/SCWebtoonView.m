/*
    SCWebtoonView.m
 */

#import "SCWebtoonView.h"
#import "TSSTSessionWindowController.h"
#import "TSSTPage.h"

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
        pageAspects = NULL;
        pageMeasured = NULL;
        pageCount = 0;
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
    free(pageAspects);  pageAspects = NULL;
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
        pageAspects  = (CGFloat *)calloc(pageCount, sizeof(CGFloat));
        pageMeasured = (BOOL *)calloc(pageCount, sizeof(BOOL));

        for(NSUInteger i = 0; i < pageCount; ++i)
        {
            /* Core Data already caches the aspect ratio of any page that
               has ever been displayed; reuse it so the strip is laid out
               correctly without decoding every image up front. */
            NSNumber * cached = [[pages objectAtIndex: i] valueForKey: @"aspectRatio"];
            CGFloat aspect = cached ? [cached floatValue] : 0.0f;
            pageAspects[i] = aspect;
            pageMeasured[i] = (aspect > 0.0f);
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


- (CGFloat)effectiveAspectForIndex:(NSUInteger)index
{
    CGFloat aspect = pageAspects[index];
    return aspect > 0.0f ? aspect : SCDefaultAspect;
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
        [self setFrameSize: NSMakeSize(width, 1)];
        return;
    }

    pageOffsets[0] = 0.0f;
    for(NSUInteger i = 0; i < pageCount; ++i)
    {
        CGFloat height = width / [self effectiveAspectForIndex: i];
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
    CGFloat top = pageOffsets[index];
    CGFloat height = pageOffsets[index + 1] - top;
    return NSMakeRect(0.0f, top, NSWidth([self bounds]), height);
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
            [image drawInRect: pageRect
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
            CGFloat aspect = 0.0f;

            if(data)
            {
                image = [[NSImage alloc] initWithData: data];
                NSArray * reps = [image representations];
                NSImageRep * rep = [reps count] ? [reps objectAtIndex: 0] : nil;
                NSInteger pixelWidth = rep ? [rep pixelsWide] : 0;
                NSInteger pixelHeight = rep ? [rep pixelsHigh] : 0;

                if(image && pixelWidth > 0 && pixelHeight > 0)
                {
                    aspect = (CGFloat)pixelWidth / (CGFloat)pixelHeight;
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
                    if(aspect > 0.0f && !pageMeasured[index])
                    {
                        pageMeasured[index] = YES;
                        if(fabs(pageAspects[index] - aspect) > 0.001f)
                        {
                            pageAspects[index] = aspect;
                            layoutChanged = YES;
                        }
                        else
                        {
                            pageAspects[index] = aspect;
                        }
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

@end
