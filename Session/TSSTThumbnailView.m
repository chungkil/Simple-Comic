//
//  TSSTThumbnailView.m
//  SimpleComic
//
//  Created by Alexander Rauchfuss on 8/22/07.
//  Copyright 2007 Dancing Tortoise Software. All rights reserved.
//

#import "TSSTThumbnailView.h"
#import "TSSTSessionWindowController.h"
#import "TSSTImageUtilities.h"
#import "TSSTImageView.h"
#import "TSSTInfoWindow.h"


@implementation TSSTThumbnailView


- (void)awakeFromNib
{
    [[self window] makeFirstResponder: self];
    [[self window] setAcceptsMouseMovedEvents: YES];
    [thumbnailView setClears: YES];
}



- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self)
    {
        hoverIndex = NSNotFound;
        trackingRects = [NSMutableIndexSet new];
        trackingIndexes = [NSMutableSet new];
        threadIdent = 0;
        thumbLock = [NSLock new];
        dragStartIndex = -1;
        dropTargetIndex = -1;
        dragInProgress = NO;
    }
    return self;
}



- (void) dealloc
{
    [thumbLock release];
    thumbLock = nil;
    [trackingRects release];
    [trackingIndexes release];
    [super dealloc];
}



- (NSRect)rectForIndex:(NSInteger)index
{
    NSRect bounds = [[[self window] screen] visibleFrame];
    float ratio = (NSHeight(bounds)) / NSWidth(bounds);
    NSInteger horCount = ceilf(sqrtf([[pageController content] count] / ratio));
    NSInteger vertCount = ceilf((float)[[pageController content] count] / (float)horCount);
    float side = NSHeight(bounds) / vertCount;
    float horSide = NSWidth(bounds) / horCount;
    NSInteger horGridPos = index % horCount;
    NSInteger vertGridPos = (index / horCount) % vertCount;
    
    NSRect thumbRect;
    if([[[dataSource session] valueForKey: @"pageOrder"] boolValue])
    {
        thumbRect = NSMakeRect(horGridPos * horSide, NSMaxY(bounds) - side - vertGridPos * side, horSide, side);
    }
    else
    {
        thumbRect = NSMakeRect(NSMaxX(bounds) - horSide - horGridPos * horSide, NSMaxY(bounds) - side - vertGridPos * side, horSide, side);
    }
    return thumbRect;
}



- (void)setDataSource:(id)source
{
    dataSource = source;
}



- (id)dataSource
{
    return dataSource;
}



- (void)removeTrackingRects
{
    [thumbnailView setImage: nil];
    hoverIndex = NSNotFound;
    NSInteger tagIndex = [trackingRects firstIndex];
    while (tagIndex != NSNotFound)
    {
        [self removeTrackingRect: tagIndex];
        tagIndex = [trackingRects indexGreaterThanIndex: tagIndex];
    }
    [trackingRects removeAllIndexes];
    [trackingIndexes removeAllObjects];
}



- (void)buildTrackingRects
{
    hoverIndex = NSNotFound;
    [self removeTrackingRects];
	NSInteger counter = 0;
	NSRect trackRect;
	NSNumber * rectIndex;
    NSInteger tagIndex;
	for (; counter < ([[pageController content] count]); ++counter)
	{
		trackRect = NSInsetRect([self rectForIndex: counter], 2, 2);
		rectIndex = @(counter);
		tagIndex = [self addTrackingRect: trackRect 
								   owner: self 
								userData: rectIndex
							assumeInside: NO];
		[trackingRects addIndex: tagIndex];
		[trackingIndexes addObject: rectIndex];
	}
    [self setNeedsDisplay: YES];
}



- (void)drawRect:(NSRect)rect
{
    NSImage * thumbnail;
    NSRect drawRect;
    NSInteger counter = 0;
    NSPoint mouse = [NSEvent mouseLocation];
    NSRect point = NSMakeRect(mouse.x, mouse.y, 6.0f, 6.0f);
    NSPoint mousePoint = [[self window] convertRectFromScreen: point].origin;
	mousePoint = [self convertPoint: mousePoint fromView: nil];
    /*  `limit` is published by the background thumbnail thread and can lag a
        delete that already shrank the page list, so clamp before drawing. */
    NSInteger drawLimit = MIN(limit, [self livePageCount]);
    while (counter < drawLimit)
    {
        thumbnail = [dataSource imageForPageAtIndex: counter];
        drawRect = [self rectForIndex: counter];
        drawRect = rectWithSizeCenteredInRect([thumbnail size], NSInsetRect(drawRect, 2, 2));
        CGFloat alpha = (dragInProgress && counter == dragStartIndex) ? 0.35f : 1.0f;
        [thumbnail drawInRect: drawRect fromRect: NSZeroRect operation: NSCompositeSourceOver fraction: alpha];
		if(!dragInProgress && NSMouseInRect(mousePoint, drawRect, NO))
		{
			hoverIndex = counter;
            [self zoomThumbnailAtIndex: hoverIndex];
		}
        ++counter;
    }

    if(dragInProgress && dropTargetIndex >= 0 && dropTargetIndex < drawLimit)
    {
        NSRect target = NSInsetRect([self rectForIndex: dropTargetIndex], 2, 2);
        [[[NSColor controlAccentColor] colorWithAlphaComponent: 0.9] set];
        NSBezierPath * p = [NSBezierPath bezierPathWithRect: target];
        [p setLineWidth: 3.0];
        [p stroke];
    }

    if(dragInProgress && dragStartIndex >= 0 && dragStartIndex < drawLimit)
    {
        NSImage * ghost = [dataSource imageForPageAtIndex: dragStartIndex];
        if(ghost)
        {
            NSSize s = [ghost size];
            CGFloat maxDim = 120.0;
            CGFloat scale = MIN(1.0, maxDim / MAX(s.width, s.height));
            NSSize gs = NSMakeSize(s.width * scale, s.height * scale);
            NSRect gr = NSMakeRect(dragCurrentPoint.x - gs.width / 2,
                                   dragCurrentPoint.y - gs.height / 2,
                                   gs.width, gs.height);
            [ghost drawInRect: gr fromRect: NSZeroRect operation: NSCompositeSourceOver fraction: 0.85];
        }
    }
}



- (NSInteger)indexForPoint:(NSPoint)p
{
    NSInteger n = [[pageController content] count];
    for(NSInteger i = 0; i < n; ++i)
    {
        if(NSPointInRect(p, [self rectForIndex: i]))
        {
            return i;
        }
    }
    return -1;
}


- (void)mouseDown:(NSEvent *)event
{
    dragStartIndex = (hoverIndex < [[pageController content] count] && hoverIndex >= 0) ? hoverIndex : -1;
    dropTargetIndex = -1;
    dragInProgress = NO;
    dragStartPoint = [self convertPoint: [event locationInWindow] fromView: nil];
    dragCurrentPoint = dragStartPoint;
}


- (void)mouseDragged:(NSEvent *)event
{
    if(dragStartIndex < 0)
    {
        return;
    }
    dragCurrentPoint = [self convertPoint: [event locationInWindow] fromView: nil];
    if(!dragInProgress)
    {
        CGFloat dx = dragCurrentPoint.x - dragStartPoint.x;
        CGFloat dy = dragCurrentPoint.y - dragStartPoint.y;
        if((dx * dx + dy * dy) < 25.0)        /* 5 pt threshold */
        {
            return;
        }
        dragInProgress = YES;
        [thumbnailView setImage: nil];       /* hide hover zoom floater while dragging */
    }
    dropTargetIndex = [self indexForPoint: dragCurrentPoint];
    [self setNeedsDisplay: YES];
}


- (void)mouseUp:(NSEvent *)event
{
    BOOL wasDrag = dragInProgress;
    NSInteger from = dragStartIndex;
    NSInteger to = dropTargetIndex;
    dragStartIndex = -1;
    dropTargetIndex = -1;
    dragInProgress = NO;

    if(wasDrag)
    {
        if(from >= 0 && to >= 0 && from != to
           && [dataSource respondsToSelector: @selector(thumbnailView:didMovePageFromIndex:toIndex:)])
        {
            [dataSource thumbnailView: self didMovePageFromIndex: from toIndex: to];
        }
        [self setNeedsDisplay: YES];
        return;
    }

    if(from >= 0)
    {
        [pageController setSelectionIndex: from];
    }
    [[self window] orderOut: self];
}



- (void)keyDown:(NSEvent *)event
{
    NSNumber * charNumber = @([[event charactersIgnoringModifiers] characterAtIndex: 0]);
    switch ([charNumber unsignedIntValue])
    {
        case 27:
            [[[self window] windowController] killTopOptionalUIElement];
            break;
        default:
            break;
    }
}



/*  The array controller may only be touched on the main thread, and
    -processThumbs runs on a detached one, so bounce the count through the
    main queue.  A direct call when we are already on main. */
- (NSInteger)livePageCount
{
    __block NSInteger n = 0;
    void (^count)(void) = ^{ n = (NSInteger)[[pageController content] count]; };
    if([NSThread isMainThread])
    {
        count();
    }
    else
    {
        dispatch_sync(dispatch_get_main_queue(), count);
    }
    return n;
}


- (void)processThumbs
{
    NSAutoreleasePool * pool = [NSAutoreleasePool new];
    unsigned localIdent;
    /*  A page removal fires the KVO that spawns this thread, so several of
        these can be in flight at once; the ident hand-off has to be atomic
        or two threads can both believe they are the current one. */
    @synchronized(self)
    {
        localIdent = ++threadIdent;
    }
    [thumbLock lock];
	NSAutoreleasePool * localPool = [NSAutoreleasePool new];
    limit = 0;
    /*  Re-read the count on every pass rather than snapshotting it up front:
        deletes can shrink the page list while this thread waits on the lock
        or generates a thumbnail, and a stale count walks off the end. */
    while(limit < [self livePageCount] &&
          localIdent == threadIdent &&
          [dataSource respondsToSelector: @selector(imageForPageAtIndex:)])
    {
        [dataSource imageForPageAtIndex: limit];

        
        if(!(limit % 5))
        {
			if([[self window] isVisible])
			{
				[self setNeedsDisplay: YES];
			}
			
			[localPool release];
			localPool = [NSAutoreleasePool new];
        }
        ++limit;
    }
	[localPool release];
    [thumbLock unlock];
    [pool release];
    [self setNeedsDisplay: YES];
}



- (void)mouseEntered:(NSEvent *)theEvent
{
	if(dragInProgress) return;
	hoverIndex = [(NSNumber *)[theEvent userData] integerValue];
    if(limit == [[pageController content] count])
    {
        [NSTimer scheduledTimerWithTimeInterval: 0.05 target: self selector: @selector(dwell:) userInfo: @(hoverIndex) repeats: NO];
    }
}



- (void)mouseExited:(NSEvent *)theEvent
{
    if([(NSNumber *)[theEvent userData] integerValue] == hoverIndex)
    {
        hoverIndex = NSNotFound;
        
		[thumbnailView setImage: nil];
		[[self window] removeChildWindow: [thumbnailView window]];
		[[thumbnailView window] orderOut: self];
    }
}



- (void)dwell:(NSTimer *)timer
{
     if([[timer userInfo] integerValue] == hoverIndex)
     {
         [self zoomThumbnailAtIndex: hoverIndex];
     }
}



- (void)zoomThumbnailAtIndex:(NSInteger)index
{
    NSImage * thumb = [[pageController arrangedObjects][index] valueForKey: @"pageImage"];
	[thumbnailView setImage: thumb];
	[thumbnailView setNeedsDisplay: YES];

    NSSize imageSize = [thumb size];
    thumbnailView.imageName = [[pageController arrangedObjects][index] valueForKey: @"name"];
    NSRect indexRect = [self rectForIndex: index];
    NSRect visibleRect = [[[self window] screen] visibleFrame];
    NSPoint thumbPoint = NSMakePoint(NSMinX(indexRect) + NSWidth(indexRect) / 2,
                                     NSMinY(indexRect) + NSHeight(indexRect) / 2);
    float viewSize = 312;//[thumbnailView frame].size.width;
    float aspect = imageSize.width / imageSize.height;
    
    if(aspect <= 1)
    {
        imageSize = NSMakeSize( aspect * viewSize, viewSize);
    }
    else
    {
        imageSize = NSMakeSize( viewSize, viewSize / aspect);
    }
    
    if(thumbPoint.y + imageSize.height / 2 > NSMaxY(visibleRect))
    {
        thumbPoint.y = NSMaxY(visibleRect) - imageSize.height / 2;
    }
    else if(thumbPoint.y - imageSize.height / 2 < NSMinY(visibleRect))
    {
        thumbPoint.y = NSMinY(visibleRect) + imageSize.height / 2;
    }
    
    if(thumbPoint.x + imageSize.width / 2 > NSMaxX(visibleRect))
    {
        thumbPoint.x = NSMaxX(visibleRect) - imageSize.width / 2;
    }
    else if(thumbPoint.x - imageSize.width / 2 < NSMinX(visibleRect))
    {
        thumbPoint.x = NSMinX(visibleRect) + imageSize.width / 2;
    }
	
    [(TSSTInfoWindow *)[thumbnailView window] setFrame: NSMakeRect(thumbPoint.x - imageSize.width / 2, thumbPoint.y - imageSize.height / 2, imageSize.width, imageSize.height)
											   display: NO
											   animate: NO];
	[[self window] addChildWindow: [thumbnailView window] ordered: NSWindowAbove];
}



@end


