/*	
	Copyright (c) 2006-2009 Dancing Tortoise Software
	Created by Alexander Rauchfuss
 
	Permission is hereby granted, free of charge, to any person 
	obtaining a copy of this software and associated documentation
	files (the "Software"), to deal in the Software without 
	restriction, including without limitation the rights to use, 
	copy, modify, merge, publish, distribute, sublicense, and/or 
	sell copies of the Software, and to permit persons to whom the
	Software is furnished to do so, subject to the following 
	conditions:
 
	The above copyright notice and this permission notice shall be
	included in all copies or substantial portions of the Software.
 
	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, 
	EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES 
	OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND 
	NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT 
	HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, 
	WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING 
	FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR 
	OTHER DEALINGS IN THE SOFTWARE.
 
    TSSTSessionWindowController.m

*/


#import <XADMaster/XADArchive.h>
#import "UKXattrMetadataStore.h"
#import "SimpleComicAppDelegate.h"
#import "TSSTSessionWindowController.h"
#import "TSSTPageView.h"
#import "SCWebtoonView.h"
#import "SCProgressStore.h"
#import "TSSTSortDescriptor.h"
#import <objc/runtime.h>
#import "TSSTImageUtilities.h"
#import "TSSTPage.h"
#import "TSSTManagedGroup.h"
#import "TSSTInfoWindow.h"
#import "TSSTThumbnailView.h"
#import "TSSTManagedSession.h"
#import "DTPolishedProgressBar.h"
#import "DTWindowCategory.h"


@implementation TSSTSessionWindowController

@synthesize pageTurn, pageNames, pageSortDescriptor;


#pragma mark - Per-session page ordinal (drives drag reorder)


static const char SCPageOrdinalKey = 'o';

static double SCOrdinalForPage(id page)
{
	NSNumber * n = objc_getAssociatedObject(page, &SCPageOrdinalKey);
	return n ? [n doubleValue] : INFINITY;
}

static void SCSetOrdinalForPage(id page, double v)
{
	objc_setAssociatedObject(page, &SCPageOrdinalKey, @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}



/*!
 Turns all of the toolbar images in to templates so that they look consistent with
 othe Apple generated icons.
 */
+ (void)initialize
{
    NSImage * segmentImage = [NSImage imageNamed: @"org_size"];
    [segmentImage setTemplate: YES];
    segmentImage = [NSImage imageNamed: @"Loupe"];
    [segmentImage setTemplate: YES];
    segmentImage = [NSImage imageNamed: @"rotate_l"];
    [segmentImage setTemplate: YES];
    segmentImage = [NSImage imageNamed: @"rotate_r"];
    [segmentImage setTemplate: YES];
    segmentImage = [NSImage imageNamed: @"win_scale"];
    [segmentImage setTemplate: YES];
    segmentImage = [NSImage imageNamed: @"hor_scale"];
    [segmentImage setTemplate: YES];
    segmentImage = [NSImage imageNamed: @"one_page"];
    [segmentImage setTemplate: YES];
    segmentImage = [NSImage imageNamed: @"two_page"];
    [segmentImage setTemplate: YES];
    segmentImage = [NSImage imageNamed: @"rl_order"];
    [segmentImage setTemplate: YES];
    segmentImage = [NSImage imageNamed: @"lr_order"];
    [segmentImage setTemplate: YES];
	segmentImage = [NSImage imageNamed: @"equal"];
    [segmentImage setTemplate: YES];
	segmentImage = [NSImage imageNamed: @"thumbnails"];
    [segmentImage setTemplate: YES];
	segmentImage = [NSImage imageNamed: @"extract"];
    [segmentImage setTemplate: YES];
}



/*!
 
*/
- (id)initWithSession:(TSSTManagedSession *)aSession
{
    self = [super init];
    if (self != nil)
    {
		pageTurn = 0;
		pageSelectionInProgress = None;
		layoutModeOverride = -1;
		progressRestored = NO;
		pagedImageCache = [[NSCache alloc] init];
		[pagedImageCache setCountLimit: 8];
		pagedPrefetching = [[NSMutableIndexSet alloc] init];
		mouseMovedTimer = nil;
//		closing = NO;
		pendingFolderDeletes = [[NSMutableArray alloc] init];
		pendingArchiveDeletes = [[NSMutableDictionary alloc] init];
		pendingFolderRotations = [[NSMutableDictionary alloc] init];
		pendingArchiveRotations = [[NSMutableDictionary alloc] init];
		pendingFolderReorders = [[NSMutableDictionary alloc] init];
		pendingArchiveReorders = [[NSMutableDictionary alloc] init];
        session = [aSession retain];
        BOOL cascade = [session valueForKey: @"position"] ? NO : YES;
        [self setShouldCascadeWindows: cascade];
		/* Make sure that the session does not start out in fullscreen, nor with the loupe enabled. */
        [session setValue: @NO forKey: @"loupe"];
		/* Pages sort by an attached per-session ordinal (set by reorder),
		   falling back to natural group + filename order for pages that
		   have not been reordered (ordinal still unset). */
		NSSortDescriptor * ordSort = [NSSortDescriptor sortDescriptorWithKey: nil
																 ascending: YES
																comparator: ^NSComparisonResult(id a, id b) {
			double da = SCOrdinalForPage(a);
			double db = SCOrdinalForPage(b);
			if(da < db) return NSOrderedAscending;
			if(da > db) return NSOrderedDescending;
			NSString * ga = [a valueForKeyPath: @"group.path"] ?: @"";
			NSString * gb = [b valueForKeyPath: @"group.path"] ?: @"";
			NSComparisonResult r = [ga localizedStandardCompare: gb];
			if(r != NSOrderedSame) return r;
			NSString * ia = [a valueForKey: @"imagePath"] ?: @"";
			NSString * ib = [b valueForKey: @"imagePath"] ?: @"";
			return [ia localizedStandardCompare: ib];
		}];
		self.pageSortDescriptor = @[ordSort];
    }
	
    return self;
}



- (NSString *)windowNibName
{
    return @"TSSTSessionWindow";
}



/*  Sets up all of the observers and bindings. */
- (void)awakeFromNib
{
    /* This needs to be set as the window subclass that the expose window
        uses has mouse events turned off by default */
    [exposeBezel setIgnoresMouseEvents: NO];
    [exposeBezel setFloatingPanel: YES];
	[exposeBezel setWindowController: self];
    [[self window] setAcceptsMouseMovedEvents: YES];
    [pageController setSelectionIndex: [[session valueForKey: @"selection"] intValue]];

    NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
    
    [defaults addObserver: self forKeyPath: TSSTConstrainScale options: 0 context: nil];
    [defaults addObserver: self forKeyPath: TSSTStatusbarVisible options: 0 context: nil];
    [defaults addObserver: self forKeyPath: TSSTScrollersVisible options: 0 context: nil];
    [defaults addObserver: self forKeyPath: TSSTBackgroundColor options: 0 context: nil];
    [defaults addObserver: self forKeyPath: TSSTLoupeDiameter options: 0 context: nil];
	[defaults addObserver: self forKeyPath: TSSTLoupePower options: 0 context: nil];
	[defaults addObserver: self forKeyPath: TSSTWebtoonMode options: 0 context: nil];
	/* Retained so swapping the scroll view's document view (paged <->
	   webtoon) never deallocates the xib-owned page view. */
	[pageView retain];
    [session addObserver: self forKeyPath: TSSTPageOrder options: 0 context: nil];
    [session addObserver: self forKeyPath: TSSTPageScaleOptions options: 0 context: nil];
    [session addObserver: self forKeyPath: TSSTTwoPageSpread options: 0 context: nil];
	[session addObserver: self forKeyPath: @"loupe" options: 0 context: nil];
	
    [session bind: @"selection" toObject: pageController withKeyPath: @"selectionIndex" options: nil];
    
	[pageScrollView setPostsFrameChangedNotifications: YES];
    [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(resizeView) name: NSViewFrameDidChangeNotification object: pageScrollView];
    [pageController addObserver: self forKeyPath: @"selectionIndex" options: 0 context: nil];
    [pageController addObserver: self forKeyPath: @"arrangedObjects.@count" options: 0 context: nil];
    
    [progressBar addObserver: self forKeyPath: @"currentValue" options: 0 context: nil];
    [progressBar bind: @"currentValue" toObject: pageController withKeyPath: @"selectionIndex" options: nil];
    [progressBar bind: @"maxValue" toObject: pageController withKeyPath: @"arrangedObjects.@count" options: nil];
    [progressBar bind: @"leftToRight" toObject: session withKeyPath: TSSTPageOrder options: nil];
	   
    [pageView bind: TSSTViewRotation toObject: session withKeyPath: TSSTViewRotation options: nil];
	NSTrackingArea * newArea = [[NSTrackingArea alloc] initWithRect: [progressBar progressRect]
															options: NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveInKeyWindow | NSTrackingActiveInActiveApp 
															  owner: self
														   userInfo: @{@"purpose": @"normalProgress"}];
	[progressBar addTrackingArea: newArea];
	[newArea release];
	[jumpField setDelegate: self];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleMouseDragged:) name:@"SCMouseDragNotification" object:nil];
    

    [self restoreSession];
}



- (void)dealloc
{
	[(TSSTThumbnailView *)exposeView setDataSource: nil];
    NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
	
    [defaults removeObserver: self forKeyPath: TSSTStatusbarVisible];
    [defaults removeObserver: self forKeyPath: TSSTScrollersVisible];
	[defaults removeObserver: self forKeyPath: TSSTBackgroundColor];
    [defaults removeObserver: self forKeyPath: TSSTConstrainScale];
	[defaults removeObserver: self forKeyPath: TSSTLoupeDiameter];
	[defaults removeObserver: self forKeyPath: TSSTLoupePower];
	[defaults removeObserver: self forKeyPath: TSSTWebtoonMode];
	[webtoonView setSessionController: nil];
	[webtoonView release];
	[pageView release];
	[pagedImageCache release];
	[pagedPrefetching release];
    [pageController removeObserver: self forKeyPath: @"selectionIndex"];
    [pageController removeObserver: self forKeyPath: @"arrangedObjects.@count"];
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    
    [progressBar removeObserver: self forKeyPath: @"currentValue"];
    [progressBar unbind: @"currentValue"];
    [progressBar unbind: @"maxValue"];
    [progressBar unbind: @"leftToRight"];
    
    [pageView setSessionController: nil];
	[pageSortDescriptor release];
	[pageNames release];
	[pendingFolderDeletes release];
	[pendingArchiveDeletes release];
	[pendingFolderRotations release];
	[pendingArchiveRotations release];
	[pendingFolderReorders release];
	[pendingArchiveReorders release];
    [session release];
    [super dealloc];
}



/*  Observes changes to the page controller.  Changes are reflected by the 
    page view.  */
- (void)observeValueForKeyPath:(NSString *)keyPath
					  ofObject:(id)object 
						change:(NSDictionary *)change 
					   context:(void *)context
{
    if([[pageController arrangedObjects] count] <= 0)
    {
        [self close];
//		[[NSNotificationCenter defaultCenter] postNotificationName: TSSTSessionEndNotification object: self];
        return;
    }
	
	NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];

    if([keyPath isEqualToString: TSSTScrollersVisible])
    {
        [self scaleToWindow];
    }
    else if([keyPath isEqualToString: @"currentValue"])
    {
		if(object == progressBar)
		{
			[pageController setSelectionIndex: [progressBar currentValue]];
		}
    }
    else if([keyPath isEqualToString: @"arrangedObjects.@count"])
    {
        [NSThread detachNewThreadSelector: @selector(processThumbs) toTarget: exposeView withObject: nil];
        [self clearPagedCache];
        [self rebaseOrdinalsToCurrentOrder];
        if([self isWebtoonMode] && webtoonView)
        {
            [webtoonView setPages: [NSArray arrayWithArray: [pageController arrangedObjects]]];
        }
        [self changeViewImages];
    }
    else if([keyPath isEqualToString: TSSTPageOrder])
	{
		[defaults setValue: [session valueForKey: TSSTPageOrder] forKey: TSSTPageOrder];
		[(TSSTThumbnailView *)exposeView setNeedsDisplay: YES];
		[(TSSTThumbnailView *)exposeView buildTrackingRects];
        [self changeViewImages];
	}
	else if([keyPath isEqualToString: TSSTPageScaleOptions])
	{
		[defaults setValue: [session valueForKey: TSSTPageScaleOptions] forKey: TSSTPageScaleOptions];
        [self scaleToWindow];
	}
	else if([keyPath isEqualToString: TSSTTwoPageSpread])
	{
		[defaults setValue: [session valueForKey: TSSTTwoPageSpread] forKey: TSSTTwoPageSpread];
		[self changeViewImages];
	}
	else if([keyPath isEqualToString: TSSTBackgroundColor])
	{
		NSColor * color = [NSUnarchiver unarchiveObjectWithData: [defaults valueForKey: TSSTBackgroundColor]];
		[pageScrollView setBackgroundColor: color];
	}
    else if([keyPath isEqualToString: TSSTStatusbarVisible])
    {
        [self adjustStatusBar];
    }
	else if([keyPath isEqualToString: TSSTLoupeDiameter])
    {
		int loupeDiameter = [[defaults valueForKey: TSSTLoupeDiameter] intValue];
		[loupeWindow resizeToDiameter: loupeDiameter];
	}
	else if([keyPath isEqualToString: @"loupe"])
    {
		[self refreshLoupePanel];
	}
	else if([keyPath isEqualToString: TSSTLoupePower])
	{
		[self refreshLoupePanel];
	}
	else if([keyPath isEqualToString: TSSTWebtoonMode])
	{
		[self applyLayoutMode];
	}
	else
	{
        [self changeViewImages];
    }
}



#pragma mark -
#pragma mark Progress Bar



- (NSImage *)imageForPageAtIndex:(int)index
{
    return [[pageController arrangedObjects][index] valueForKey: @"thumbnail"];
}


- (NSImage *)thumbnailForPageIndex:(NSInteger)index
{
    NSArray * pages = [pageController arrangedObjects];
    if(index < 0 || index >= (NSInteger)[pages count])
    {
        return nil;
    }
    return [pages[index] valueForKey: @"thumbnail"];
}



- (NSString *)nameForPageAtIndex:(int)index
{
    return [[pageController arrangedObjects][index] valueForKey: @"name"];
}



#pragma mark -
#pragma mark Event handling



- (void)mouseMoved:(NSEvent *)theEvent
{
	NSRect progressRect;
	NSPoint windowLocation = [theEvent locationInWindow];
    progressRect = [progressBar convertRect: [progressBar progressRect] toView: nil];
    if(NSMouseInRect(windowLocation, progressRect, [progressBar isFlipped]))
    {
        [self infoPanelSetupAtPoint: windowLocation];
    }
	
    [self refreshLoupePanel];
}



- (void)mouseEntered:(NSEvent *)theEvent
{
	NSString * purpose = [(NSDictionary *)[theEvent userData] valueForKey: @"purpose"];
    if([purpose isEqualToString: @"normalProgress"])
    {
        [self infoPanelSetupAtPoint: [theEvent locationInWindow]];
		[[self window] addChildWindow: infoWindow ordered: NSWindowAbove];
    }
}



- (void)mouseExited:(NSEvent *)theEvent
{
    if([theEvent trackingArea])
    {
        [[infoWindow parentWindow] removeChildWindow: infoWindow];
        [infoWindow orderOut: self];
    }
}



/* Handles mouse drag notifications relayed from progressbar */
- (void)handleMouseDragged:(NSNotification*)notification {
    [infoWindow orderOut:self];
}


- (void)refreshLoupePanel
{
    BOOL loupe = [[session valueForKey: @"loupe"] boolValue];
    NSPoint mouse = [NSEvent mouseLocation];

    BOOL webtoon = [self isWebtoonMode] && webtoonView;
    NSView * loupeSourceView = webtoon ? (NSView *)webtoonView : (NSView *)pageView;

    NSRect point = NSMakeRect(mouse.x, mouse.y, 0, 0);
    NSPoint localPoint = [loupeSourceView convertPoint: [[self window] convertRectFromScreen: point].origin fromView: nil];
    NSPoint scrollPoint = [pageScrollView convertPoint: [[self window] convertRectFromScreen: point].origin fromView: nil];
    if(NSMouseInRect(scrollPoint, [pageScrollView bounds], [pageScrollView isFlipped])
	   && loupe
	   && [[self window] isKeyWindow]
	   && pageSelectionInProgress == None)
    {
		if(![loupeWindow isVisible])
		{
			[[self window] addChildWindow: loupeWindow ordered: NSWindowAbove];
			[NSCursor hide];
		}

		NSRect zoomRect = [zoomView frame];
		[loupeWindow centerAtPoint: mouse];
		zoomRect.origin = localPoint;
		if(webtoon)
		{
			[zoomView setImage: [webtoonView imageInRect: zoomRect]];
		}
		else
		{
			[zoomView setImage: [pageView imageInRect: zoomRect]];
		}
    }
    else
	{
		if([loupeWindow isVisible])
        {
            [[loupeWindow parentWindow] removeChildWindow: loupeWindow];
            [loupeWindow orderOut: self];
        }
		
		[NSCursor unhide];
	}
}



- (void)infoPanelSetupAtPoint:(NSPoint)point
{
	NSPoint cursorPoint;
	int index;
	DTPolishedProgressBar * bar;

    bar = progressBar;
    [[infoWindow contentView] setBordered: NO];
    point.y = (NSMaxY([bar frame]) - 6);
	
	cursorPoint = [bar convertPoint: point fromView: nil];
	index = [bar indexForPoint: cursorPoint];

    NSImage * thumb = [self imageForPageAtIndex: index];
    NSSize thumbSize = sizeConstrainedByDimension([thumb size], 128);
	
    [infoPicture setFrameSize: thumbSize];
    [infoPicture setImage: thumb];

    NSRect area = NSMakeRect(point.x, point.y, 0, 0);
    cursorPoint = [[self window] convertRectToScreen: area].origin;
	
    [infoWindow caretAtPoint: cursorPoint size: NSMakeSize(thumbSize.width, thumbSize.height)
			   withLimitLeft: NSMinX([[bar window] frame]) 
					   right: NSMaxX([[bar window] frame])];
}



#pragma mark -
#pragma mark Actions



- (IBAction)changeTwoPage:(id)sender
{
    BOOL spread = ![[session valueForKey: TSSTTwoPageSpread] boolValue];

    [session setValue: @(spread) forKey: TSSTTwoPageSpread];
}



- (IBAction)changePageOrder:(id)sender
{
    BOOL pageOrder = ![[session valueForKey: TSSTPageOrder] boolValue];
    [session setValue: @(pageOrder) forKey: TSSTPageOrder];
}



- (IBAction)changeScaling:(id)sender
{
    int scaleType = [sender tag] % 400;
    [session setValue: @(scaleType) forKey: TSSTPageScaleOptions];
}


- (IBAction)toggleWebtoonMode:(id)sender
{
    layoutModeOverride = [self isWebtoonMode] ? 0 : 1;
    [self applyLayoutMode];
    [self persistProgress];
}


- (BOOL)isWebtoonMode
{
    if(layoutModeOverride >= 0)
    {
        return layoutModeOverride == 1;
    }
    return [[[NSUserDefaults standardUserDefaults] valueForKey: TSSTWebtoonMode] boolValue];
}


- (IBAction)changeWebtoonGap:(id)sender
{
    [[NSUserDefaults standardUserDefaults] setInteger: [sender tag] forKey: TSSTWebtoonGap];
    if([self isWebtoonMode] && webtoonView)
    {
        [webtoonView relayoutPreservingAnchor];
    }
}


- (IBAction)changeWebtoonWidth:(id)sender
{
    [[NSUserDefaults standardUserDefaults] setInteger: [sender tag] forKey: TSSTWebtoonMaxWidth];
    if([self isWebtoonMode] && webtoonView)
    {
        [webtoonView relayoutPreservingAnchor];
    }
}


- (NSString *)workIdentifier
{
    if([[pageController arrangedObjects] count] <= 0)
    {
        return nil;
    }
    TSSTPage * page = [pageController arrangedObjects][0];
    NSString * path = [page valueForKey: @"group"] ?
        [page valueForKeyPath: @"group.topLevelGroup.path"] :
        [page valueForKeyPath: @"imagePath"];
    return path;
}


- (void)persistProgress
{
    if(!progressRestored)
    {
        return;
    }
    NSString * key = [self workIdentifier];
    if([key length] == 0)
    {
        return;
    }
    NSInteger page = [pageController selectionIndex];
    CGFloat scrollY = ([self isWebtoonMode] && webtoonView) ? NSMinY([webtoonView visibleRect]) : 0.0f;
    [[SCProgressStore sharedStore] setLastPage: page
                                       scrollY: scrollY
                                    layoutMode: ([self isWebtoonMode] ? 1 : 0)
                                        forKey: key];
}


- (void)restoreProgress
{
    NSString * key = [self workIdentifier];
    NSDictionary * record = [key length] ? [[SCProgressStore sharedStore] recordForKey: key] : nil;

    if(record)
    {
        id modeVal = [record objectForKey: @"layoutMode"];
        if(modeVal)
        {
            layoutModeOverride = [modeVal intValue] == 1 ? 1 : 0;
        }

        NSInteger count = [[pageController arrangedObjects] count];
        id pageVal = [record objectForKey: @"lastPage"];
        if(pageVal && count > 0)
        {
            NSInteger p = [pageVal integerValue];
            if(p < 0)
            {
                p = 0;
            }
            if(p >= count)
            {
                p = count - 1;
            }
            [pageController setSelectionIndex: p];
        }

        [self applyLayoutMode];

        if([self isWebtoonMode] && webtoonView)
        {
            id yVal = [record objectForKey: @"scrollY"];
            if(yVal && [yVal doubleValue] > 0.0)
            {
                [webtoonView scrollPoint: NSMakePoint(0.0, [yVal doubleValue])];
            }
        }
    }
    else if([self isWebtoonMode])
    {
        [self applyLayoutMode];
    }

    progressRestored = YES;
}


- (void)jumpToPageIndex:(NSInteger)index
{
    NSInteger count = [[pageController arrangedObjects] count];
    if(count <= 0)
    {
        return;
    }
    if(index < 0)
    {
        index = 0;
    }
    if(index >= count)
    {
        index = count - 1;
    }
    [pageController setSelectionIndex: index];
}


- (IBAction)addBookmark:(id)sender
{
    NSString * key = [self workIdentifier];
    if([key length] == 0)
    {
        return;
    }
    NSInteger page = [pageController selectionIndex];
    NSString * suggested = [NSString stringWithFormat: NSLocalizedString(@"Page %ld", @"Default bookmark name"), (long)(page + 1)];

    NSAlert * alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText: NSLocalizedString(@"Add Bookmark", @"Add bookmark alert title")];
    [alert setInformativeText: NSLocalizedString(@"Name this bookmark:", @"Add bookmark prompt")];
    [alert addButtonWithTitle: NSLocalizedString(@"Add", @"Add bookmark confirm")];
    [alert addButtonWithTitle: NSLocalizedString(@"Cancel", @"Cancel")];

    NSTextField * field = [[[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 240, 24)] autorelease];
    [field setStringValue: suggested];
    [alert setAccessoryView: field];

    if([alert runModal] == NSAlertFirstButtonReturn)
    {
        NSString * name = [field stringValue];
        if([name length] == 0)
        {
            name = suggested;
        }
        [[SCProgressStore sharedStore] addBookmarkName: name page: page forKey: key];
    }
}


- (IBAction)removeAllBookmarks:(id)sender
{
    NSString * key = [self workIdentifier];
    if([key length] == 0)
    {
        return;
    }
    [[SCProgressStore sharedStore] removeAllBookmarksForKey: key];
}


- (void)renameBookmarkAtIndex:(NSInteger)index
{
    NSString * key = [self workIdentifier];
    if([key length] == 0)
    {
        return;
    }
    NSArray * bookmarks = [[SCProgressStore sharedStore] bookmarksForKey: key];
    if(index < 0 || index >= (NSInteger)[bookmarks count])
    {
        return;
    }
    NSString * current = [[bookmarks objectAtIndex: index] objectForKey: @"name"];

    NSAlert * alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText: NSLocalizedString(@"Rename Bookmark", @"Rename bookmark alert title")];
    [alert setInformativeText: NSLocalizedString(@"New name:", @"Rename bookmark prompt")];
    [alert addButtonWithTitle: NSLocalizedString(@"Rename", @"Rename bookmark confirm")];
    [alert addButtonWithTitle: NSLocalizedString(@"Cancel", @"Cancel")];

    NSTextField * field = [[[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 240, 24)] autorelease];
    [field setStringValue: current ? current : @""];
    [alert setAccessoryView: field];

    if([alert runModal] == NSAlertFirstButtonReturn)
    {
        NSString * name = [field stringValue];
        if([name length] > 0)
        {
            [[SCProgressStore sharedStore] renameBookmarkAtIndex: index toName: name forKey: key];
        }
    }
}


- (void)deleteBookmarkAtIndex:(NSInteger)index
{
    NSString * key = [self workIdentifier];
    if([key length] == 0)
    {
        return;
    }
    [[SCProgressStore sharedStore] removeBookmarkAtIndex: index forKey: key];
}


/*  Installs the document view that matches the current reading mode.  In
    webtoon mode the whole session is presented as one continuous vertical
    strip; otherwise the original paged compositor is restored. */
- (void)applyLayoutMode
{
    if([[pageController arrangedObjects] count] <= 0)
    {
        return;
    }

    if([self isWebtoonMode])
    {
        if(!webtoonView)
        {
            webtoonView = [[SCWebtoonView alloc] initWithFrame: [pageScrollView bounds]];
            [webtoonView setSessionController: self];
            [webtoonView setAutoresizingMask: NSViewWidthSizable];
        }
        [pageScrollView setHasVerticalScroller: YES];
        [pageScrollView setHasHorizontalScroller: NO];
        [pageScrollView setDocumentView: webtoonView];
        [webtoonView setPages: [NSArray arrayWithArray: [pageController arrangedObjects]]];
        [webtoonView relayoutPreservingAnchor];
        [webtoonView scrollToPageIndex: [pageController selectionIndex]];
        [self setValue: [[pageController arrangedObjects][[pageController selectionIndex]] valueForKey: @"name"]
                forKey: @"pageNames"];
        [[self window] makeFirstResponder: webtoonView];
    }
    else
    {
        [pageScrollView setDocumentView: pageView];
        [self scaleToWindow];
        [self changeViewImages];
        [pageView correctViewPoint];
        [[self window] makeFirstResponder: pageView];
    }
}


/*  Called by the webtoon view as it scrolls so that the progress bar and
    saved selection track the page currently on screen. */
- (void)webtoonScrolledToPageIndex:(NSInteger)index
{
    int count = [[pageController arrangedObjects] count];
    if(index < 0 || index >= count)
    {
        return;
    }
    if((NSInteger)[pageController selectionIndex] == index)
    {
        return;
    }
    webtoonSyncingSelection = YES;
    [pageController setSelectionIndex: index];
    webtoonSyncingSelection = NO;
}


- (IBAction)turnPage:(id)sender
{
    int segmentTag = [[sender cell] tagForSegment: [sender selectedSegment]];
    if(segmentTag == 701)
    {
        [self pageLeft: self];
    }
    else if(segmentTag == 702)
    {
        [self pageRight: self];
    }
}


/*! Method flips the page to the right calling nextPage or previousPage
	depending on the prefered page ordering.
*/
- (IBAction)pageRight:(id)sender
{
    [self setPageTurn: 2];
    if([[session valueForKey: TSSTPageOrder] boolValue])
    {
        [self nextPage];
    }
    else
    {
        [self previousPage];
    }
}



/*! Method flips the page to the left calling nextPage or previousPage
    depending on the prefered page ordering.
*/
- (IBAction)pageLeft:(id)sender
{
    [self setPageTurn: 1];
	
    if([[session valueForKey: TSSTPageOrder] boolValue])
    {
        [self previousPage];
    }
    else
    {
        [self nextPage];
    }
}



- (IBAction)shiftPageRight:(id)sender
{
    if([[session valueForKey: TSSTPageOrder] boolValue])
    {
        [pageController selectNext: sender];
    }
    else
    {
        [pageController selectPrevious: sender];
    }
}



- (IBAction)shiftPageLeft:(id)sender
{
    if([[session valueForKey: TSSTPageOrder] boolValue])
    {
        [pageController selectPrevious: sender];
    }
    else
    {
        [pageController selectNext: sender];
    }
}



- (IBAction)skipRight:(id)sender
{
    int index;
    if([[session valueForKey: TSSTPageOrder] boolValue])
    {
        index = ([pageController selectionIndex] + 10);
        index = index < [[pageController content] count] ? index : [[pageController content] count] - 1;
    }
    else
    {
        index = ([pageController selectionIndex] - 10);
        index = index > 0 ? index : 0;
    }
    
    [pageController setSelectionIndex: index];
}



- (IBAction)skipLeft:(id)sender
{
    int index;
    if(![[session valueForKey: TSSTPageOrder] boolValue])
    {
        index = ([pageController selectionIndex] + 10);
        index = index < [[pageController content] count] ? index : [[pageController content] count] - 1;
    }
    else
    {
        index = ([pageController selectionIndex] - 10);
        index = index > 0 ? index : 0;
    }
    [pageController setSelectionIndex: index];
}



- (IBAction)firstPage:(id)sender
{
    [pageController setSelectionIndex: 0];
}



- (IBAction)lastPage:(id)sender
{
    [pageController setSelectionIndex: [[pageController content] count] - 1];
}



/* Zoom method for the zoom segmented control. Each segment has its own tag. */
- (IBAction)zoom:(id)sender
{
    int segmentTag = [[sender cell] tagForSegment: [sender selectedSegment]];
    if(segmentTag == 801)
    {
        [self zoomIn: self];
    }
    else if(segmentTag == 802)
    {
        [self zoomOut: self];
    }
	else if(segmentTag == 803)
    {
        [self zoomReset: self];
    }
}



- (IBAction)zoomIn:(id)sender
{
    int scalingOption = [[session valueForKey: TSSTPageScaleOptions] intValue];
    float previousZoom = [[session valueForKey: TSSTZoomLevel] floatValue];
    if(scalingOption != 0)
    {
        previousZoom = NSWidth([pageView imageBounds]) / [pageView combinedImageSizeForZoom: 1].width;
    }
	
	previousZoom += 0.1;
    [session setValue: @(previousZoom) forKey: TSSTZoomLevel];
	[session setValue: @0 forKey: TSSTPageScaleOptions];
	
    [pageView resizeView];
    [self refreshLoupePanel];
}



- (IBAction)zoomOut:(id)sender
{
    int scalingOption = [[session valueForKey: TSSTPageScaleOptions] intValue];
    float previousZoom = [[session valueForKey: TSSTZoomLevel] floatValue];
    if(scalingOption != 0)
    {
        previousZoom = NSWidth([pageView imageBounds]) / [pageView combinedImageSizeForZoom: 1].width;
    }
    
	previousZoom -= 0.1;
	previousZoom = previousZoom < 0.1 ? 0.1 : previousZoom;
    [session setValue: @(previousZoom) forKey: TSSTZoomLevel];
	[session setValue: @0 forKey: TSSTPageScaleOptions];
	
    [pageView resizeView];
    [self refreshLoupePanel];
}


- (IBAction)zoomReset:(id)sender
{
	[session setValue: @0 forKey: TSSTPageScaleOptions];
    [session setValue: @1.0f forKey: TSSTZoomLevel];
	[pageView resizeView];
    [self refreshLoupePanel];
}


- (IBAction)rotate:(id)sender
{
    int segmentTag = [[sender cell] tagForSegment: [sender selectedSegment]];
    if(segmentTag == 901)
    {
        [self rotateLeft: self];
    }
    else if(segmentTag == 902)
    {
        [self rotateRight: self];
    }
}


- (IBAction)rotateRight:(id)sender
{
    int currentRotation = [[session valueForKey: TSSTViewRotation] intValue];
    currentRotation = currentRotation + 1 > 3 ? 0 : currentRotation + 1;
    [session setValue: @(currentRotation) forKey: TSSTViewRotation];
    [self resizeWindow];
    [self refreshLoupePanel];
}


- (IBAction)rotateLeft:(id)sender
{
    int currentRotation = [[session valueForKey: TSSTViewRotation] intValue];
    currentRotation = currentRotation - 1 < 0 ? 3 : currentRotation - 1;
    [session setValue: @(currentRotation) forKey: TSSTViewRotation];
    [self resizeWindow];
    [self refreshLoupePanel];
}


- (IBAction)noRotation:(id)sender
{
    [session setValue: @0 forKey: TSSTViewRotation];
    [self resizeWindow];
    [self refreshLoupePanel];
}


- (IBAction)toggleLoupe:(id)sender
{
    BOOL loupe = [[session valueForKey: @"loupe"] boolValue];
    loupe = !loupe;
    [session setValue: @(loupe) forKey: @"loupe"];
}


- (IBAction)togglePageExpose:(id)sender
{
    if([exposeBezel isVisible])
    {
        [[thumbnailPanel parentWindow] removeChildWindow: thumbnailPanel];
        [thumbnailPanel orderOut: self];
        [exposeBezel orderOut: self];
		[[self window] makeKeyAndOrderFront: self];
		[[self window] makeFirstResponder: pageView];
    }
    else
    {
        [NSCursor unhide];
        [(TSSTThumbnailView *)exposeView buildTrackingRects];
        [exposeBezel setFrame: [[[self window] screen] frame] display: NO];
        [exposeBezel makeKeyAndOrderFront: self];
        [NSThread detachNewThreadSelector: @selector(processThumbs) toTarget: exposeView withObject: nil];
    }
}


- (IBAction)launchJumpPanel:(id)sender
{
	[jumpField setIntValue: [pageController selectionIndex] + 1];
    [self.window beginSheet: jumpPanel completionHandler:^(NSModalResponse returnCode) { }];
}


- (IBAction)cancelJumpPanel:(id)sender
{
	[self.window endSheet: jumpPanel returnCode: NSModalResponseAbort];
}


- (IBAction)goToPage:(id)sender
{
    if([jumpField integerValue] != NSNotFound)
    {
        int index = [jumpField intValue] < 1 ? 0 : [jumpField intValue] - 1;
        [pageController setSelectionIndex: index];
    }
	
	[self.window endSheet: jumpPanel returnCode: NSModalResponseContinue];
}


- (IBAction)removePages:(id)sender
{
	pageSelectionInProgress = Delete;
	[self changeViewForSelection];
}


/*  Method that allows the user to select an icon for comic archives.
	Calls pageView and verifies that the images selected are from an
	archive. */
- (IBAction)setArchiveIcon:(id)sender
{
	pageSelectionInProgress = Icon;
	[self changeViewForSelection];
}


/*	Saves the selected page to a user specified location. */
- (IBAction)extractPage:(id)sender
{
	pageSelectionInProgress = Extract;
	[self changeViewForSelection];
}


- (BOOL)pageSelectionCanCrop
{
	return (pageSelectionInProgress == Icon);
}


/* Used by all of the page selection methods to make both pages visible.  Also adds a small
	gutter around the images for cropping. */
- (void)changeViewForSelection
{
	savedZoom = [[session valueForKey: TSSTZoomLevel] floatValue];
	[pageScrollView setHasVerticalScroller: NO];
    [pageScrollView setHasHorizontalScroller: NO];
	[self refreshLoupePanel];
	NSSize imageSize = [pageView combinedImageSizeForZoom: 1];
	NSSize scrollerBounds = [[pageView enclosingScrollView] bounds].size;
	scrollerBounds.height -= 20;
	scrollerBounds.width -= 20;
	float factor;
	if(imageSize.width / imageSize.height > scrollerBounds.width / scrollerBounds.height)
	{
		factor = scrollerBounds.width / imageSize.width;
	}
	else
	{		
		factor = scrollerBounds.height / imageSize.height;
	}
	
	[session setValue: @(factor) forKey: TSSTZoomLevel];
	[pageView resizeView];
}


- (BOOL)canSelectPageIndex:(NSInteger)selection
{
	NSInteger index = [pageController selectionIndex] + selection;
	NSArray * arranged = [pageController arrangedObjects];
	if(index < 0 || (NSUInteger)index >= [arranged count]) return NO;
	TSSTPage * selectedPage = arranged[index];
	if([[selectedPage valueForKey: @"text"] boolValue]) return NO;

	TSSTManagedGroup * selectedGroup = [selectedPage valueForKey: @"group"];
	BOOL isTopLevelArchive = [selectedGroup class] == [TSSTManagedArchive class] &&
	                         selectedGroup == [selectedGroup topLevelGroup];

	if(pageSelectionInProgress == Delete)
	{
		/* Move to Trash: CBZ archive page or loose folder image. */
		if(isTopLevelArchive)
		{
			NSString * ext = [[[selectedGroup valueForKey: @"path"] pathExtension] lowercaseString];
			return [ext isEqualToString: @"cbz"] || [ext isEqualToString: @"zip"];
		}
		if(selectedGroup && ![selectedGroup isKindOfClass: [TSSTManagedArchive class]])
		{
			NSString * imagePath = [selectedPage valueForKey: @"imagePath"];
			return imagePath && [imagePath isAbsolutePath] &&
			       [[NSFileManager defaultManager] fileExistsAtPath: imagePath];
		}
		return NO;
	}

	/* Icon / Extract: any top-level archive (original behavior). */
	return isTopLevelArchive;
}


- (BOOL)pageSelectionInProgress
{
	return (pageSelectionInProgress != None);
}


- (void)cancelPageSelection
{
	[session setValue: @(savedZoom) forKey: TSSTZoomLevel];
	pageSelectionInProgress = None;
	[self scaleToWindow];
}


- (void)selectedPage:(NSInteger)selection withCropRect:(NSRect)cropRect
{
	switch (pageSelectionInProgress)
	{
		case Icon:
			[self setIconWithSelection: selection andCropRect: cropRect];
			break;
		case Delete:
			[self deletePageWithSelection: selection];
			break;
		case Extract:
			[self extractPageWithSelection: selection];
			break;
		default:
			break;
	}
	
	[session setValue: @(savedZoom) forKey: TSSTZoomLevel];
	pageSelectionInProgress = None;
	[self scaleToWindow];
}


- (void)deletePageWithSelection:(NSInteger)selection
{
	if(selection == -1) return;

	NSInteger index = [pageController selectionIndex] + selection;
	TSSTPage * selectedPage = [pageController arrangedObjects][index];
	TSSTManagedGroup * group = [selectedPage valueForKey: @"group"];
	NSString * imagePath = [selectedPage valueForKey: @"imagePath"];

	if([group isKindOfClass: [TSSTManagedArchive class]])
	{
		NSString * archivePath = [group valueForKey: @"path"];
		if(archivePath && imagePath)
		{
			NSMutableArray * entries = pendingArchiveDeletes[archivePath];
			if(!entries)
			{
				entries = [NSMutableArray array];
				pendingArchiveDeletes[archivePath] = entries;
			}
			[entries addObject: imagePath];
		}
		[pendingArchiveRotations[archivePath] removeObjectForKey: imagePath];
		[(NSMutableArray *)pendingArchiveReorders[archivePath] removeObject: imagePath];
	}
	else if(imagePath && [imagePath isAbsolutePath])
	{
		[pendingFolderDeletes addObject: imagePath];
		[pendingFolderRotations removeObjectForKey: imagePath];
		NSString * folderKey = [[selectedPage valueForKeyPath: @"group.path"] copy];
		[(NSMutableArray *)pendingFolderReorders[folderKey] removeObject: imagePath];
		[folderKey release];
	}

	[pageController removeObject: selectedPage];
	[[self managedObjectContext] deleteObject: selectedPage];
}


- (void)extractPageWithSelection:(NSInteger)selection
{
	/*	selectpage returns prompts the user for which page they wish to use.
	 If there is only one page or the user selects the first page 0 is returned,
	 otherwise 1. */
	if(selection != -1)
	{
		int index = [pageController selectionIndex];
		index += selection;
		TSSTPage * selectedPage = [pageController arrangedObjects][index];
		
		NSSavePanel * savePanel = [NSSavePanel savePanel];
		[savePanel setTitle: @"Extract Page"];
		[savePanel setPrompt: @"Extract"];
        [savePanel setNameFieldStringValue:[selectedPage name]];
		if(NSModalResponseOK == [savePanel runModal])
		{
			[[selectedPage pageData] writeToFile: [[savePanel URL] path] atomically: YES];
		}
	}
}


- (void)setIconWithSelection:(NSInteger)selection andCropRect:(NSRect)cropRect
{
	if(selection != -1)
	{
		int index = [pageController selectionIndex];
		index += selection;
		TSSTPage * selectedPage = [pageController arrangedObjects][index];
		TSSTManagedGroup * selectedGroup = [selectedPage valueForKey: @"group"];
		/* Makes sure that the group is both an archive and not nested */
		if([selectedGroup class] == [TSSTManagedArchive class] && 
		   selectedGroup == [selectedGroup topLevelGroup] &&
		   ![[selectedPage valueForKey: @"text"] boolValue])
		{
			NSString * archivePath = [[selectedGroup valueForKey: @"path"] stringByStandardizingPath];
			if([(TSSTManagedArchive *)selectedGroup quicklookCompatible])
			{
				int coverIndex = [[selectedPage valueForKey: @"index"] intValue];
				XADPath * coverName = [(XADArchive *)[selectedGroup instance] rawNameOfEntry: coverIndex];
				[UKXattrMetadataStore setString: [coverName stringWithEncoding: NSNonLossyASCIIStringEncoding]
										 forKey: @"QCCoverName" 
										 atPath: archivePath 
								   traverseLink: NO];
				[UKXattrMetadataStore setString: NSStringFromRect(cropRect)
										 forKey: @"QCCoverRect" 
										 atPath: archivePath 
								   traverseLink: NO];
				
				[NSTask launchedTaskWithLaunchPath: @"/usr/bin/touch" 
										 arguments: @[archivePath]];
			}
			else
			{
				NSRect drawRect = NSMakeRect(0, 0, 496, 496);
				NSImage * iconImage = [[NSImage alloc] initWithSize: drawRect.size];
				cropRect.size = NSEqualSizes(cropRect.size, NSZeroSize) ? NSMakeSize([[selectedPage valueForKey: @"width"] floatValue], [[selectedPage valueForKey: @"height"] floatValue]) : cropRect.size;
				drawRect = rectWithSizeCenteredInRect( cropRect.size, drawRect);
				
				[iconImage lockFocus];
				[[NSGraphicsContext currentContext] setImageInterpolation: NSImageInterpolationHigh];
				[[selectedPage pageImage] drawInRect: drawRect fromRect: cropRect operation: NSCompositeSourceOver fraction: 1];
				[iconImage unlockFocus];
				
				NSImage * shadowImage = [[NSImage alloc] initWithSize: NSMakeSize(512, 512)];
				
				NSShadow * thumbShadow = [NSShadow new];
				[thumbShadow setShadowOffset: NSMakeSize(0.0, -8.0)];
				[thumbShadow setShadowBlurRadius: 25.0];
				[thumbShadow setShadowColor: [NSColor colorWithCalibratedWhite: 0.2 alpha: 1.0]];				
				
				[shadowImage lockFocus];
				[thumbShadow set];
				[iconImage drawInRect: NSMakeRect(16, 16, 496, 496) fromRect: NSZeroRect operation: NSCompositeSourceOver fraction: 1];
				[shadowImage unlockFocus];
				
				[[NSWorkspace sharedWorkspace] setIcon: shadowImage forFile: archivePath options: 0];
				
				[thumbShadow release];
				[iconImage release];
				[shadowImage release];
			}
		}
	}
	
	[session setValue: @(savedZoom) forKey: TSSTZoomLevel];
}



#pragma mark -
#pragma mark Convenience Methods


- (void)hideCursor
{
	mouseMovedTimer = nil;

	if([[self window] isFullscreen])
	{
		[NSCursor setHiddenUntilMouseMoves: YES];
	}
}


/*  When a session is launched this method is called.  It checks to see if the 
    session was a saved session or one that is brand new.  If it was a saved 
    session then all of the saved session information is passed to the window
    and view. */
- (void)restoreSession
{
    [self changeViewImages];
    [self scaleToWindow];
	[self adjustStatusBar];
    NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
    int loupeDiameter = [[defaults valueForKey: TSSTLoupeDiameter] intValue];
    loupeDiameter = 1000;
    [loupeWindow setFrame:NSMakeRect(0,0, loupeDiameter, loupeDiameter) display: NO];
    NSColor * color = [NSUnarchiver unarchiveObjectWithData: [defaults valueForKey: TSSTBackgroundColor]];
	[pageScrollView setBackgroundColor: color];
    [pageView setRotation: [[session valueForKey: TSSTViewRotation] intValue]];
    NSValue * positionValue;
    NSData * posData = [session valueForKey: @"position"];
	
    if(posData)
    {
        positionValue = [NSUnarchiver unarchiveObjectWithData: posData];
        [[self window] setFrame: [positionValue rectValue] display: NO];
		NSData * scrollData = [session valueForKey: TSSTScrollPosition];
		if(scrollData)
		{
			[self setShouldCascadeWindows: NO];
			positionValue = [NSUnarchiver unarchiveObjectWithData: scrollData];
			[pageView scrollPoint: [positionValue pointValue]];
		}
    }
	else
    {
		newSession = YES;
		[self setShouldCascadeWindows: YES];
		[[self window] zoom: self];
        [pageView correctViewPoint];
    }

    [self rebaseOrdinalsToCurrentOrder];
    [self restoreProgress];
}


/*  This method figures out which pages should be displayed in the view.
    To do so it looks at which page is currently selected as well as its aspect ratio
    and that of the next image */
- (void)changeViewImages
{
    if([self isWebtoonMode])
    {
        int pageNumberCount = [[pageController arrangedObjects] count];
        if(pageNumberCount <= 0)
        {
            return;
        }
        int selected = [pageController selectionIndex];
        if(selected < 0)
        {
            selected = 0;
        }
        if(selected >= pageNumberCount)
        {
            selected = pageNumberCount - 1;
        }
        TSSTPage * selectedPage = [pageController arrangedObjects][selected];
        [self setValue: [selectedPage valueForKey: @"name"] forKey: @"pageNames"];
        NSString * reprPath = [selectedPage valueForKey: @"group"] ?
            [selectedPage valueForKeyPath: @"group.topLevelGroup.path"] :
            [selectedPage valueForKeyPath: @"imagePath"];
        [[self window] setRepresentedFilename: reprPath ? reprPath : @""];
        if(!webtoonSyncingSelection)
        {
            [webtoonView scrollToPageIndex: selected];
        }
        return;
    }

    int count = [[pageController arrangedObjects] count];
    int index = [pageController selectionIndex];
    TSSTPage * pageOne = [pageController arrangedObjects][index];
    TSSTPage * pageTwo = (index + 1) < count ? [pageController arrangedObjects][(index + 1)] : nil;
    NSString * titleString = [pageOne valueForKey: @"name"];
	NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
	NSString * representationPath;
	
    BOOL currentAllowed = ![pageOne shouldDisplayAlone] && 
        !(index == 0 && [[defaults valueForKey: TSSTLonelyFirstPage] boolValue]);
    
    if(currentAllowed && [[session valueForKey: TSSTTwoPageSpread] boolValue] && pageTwo && ![pageTwo shouldDisplayAlone])
    {
        if([[session valueForKey: TSSTPageOrder] boolValue])
        {
            titleString = [NSString stringWithFormat:@"%@ %@", titleString, [pageTwo valueForKey: @"name"]];
        }
        else
        {
            titleString = [NSString stringWithFormat:@"%@ %@", [pageTwo valueForKey: @"name"], titleString];
        }
    }
    else
    {
        pageTwo = nil;
    }
	
	representationPath = [pageOne valueForKey: @"group"] ? [pageOne valueForKeyPath: @"group.topLevelGroup.path"] : [pageOne valueForKeyPath: @"imagePath"];
	[[self window] setRepresentedFilename: representationPath];

    [self setValue: titleString forKey: @"pageNames"];
    NSImage * firstImage = [self displayImageForPageAtIndex: index];
    NSImage * secondImage = pageTwo ? [self displayImageForPageAtIndex: (index + 1)] : nil;
    [pageView setFirstPage: firstImage secondPageImage: secondImage];

    [self scaleToWindow];
	[pageView correctViewPoint];
    [self refreshLoupePanel];

    [self prefetchPagesAroundIndex: index];
}


/*  Returns the full image for a page, using the warm cache when possible
    so a page turn does not block on a decode.  Text pages are rendered
    directly (cheap, and not a decodable image format). */
- (NSImage *)displayImageForPageAtIndex:(int)index
{
    NSArray * pages = [pageController arrangedObjects];
    if(index < 0 || index >= (int)[pages count])
    {
        return nil;
    }
    TSSTPage * page = pages[index];
    if([[page valueForKey: @"text"] boolValue])
    {
        return [page valueForKey: @"pageImage"];
    }

    NSImage * image = [pagedImageCache objectForKey: @(index)];
    if(!image)
    {
        image = [page valueForKey: @"pageImage"];
        if(image)
        {
            [pagedImageCache setObject: image forKey: @(index)];
        }
    }

    NSInteger rotation = [self pendingRotationForPage: page];
    if(rotation && image)
    {
        return SCRotatedImage(image, rotation);
    }
    return image;
}


/*  Decodes a small window of pages around the current one on a background
    queue.  Only -pageData (guarded by the archive's groupLock) and image
    decoding happen off the main thread; no managed-object writes. */
- (void)prefetchPagesAroundIndex:(int)index
{
    NSArray * pages = [pageController arrangedObjects];
    int count = (int)[pages count];
    for(int i = index - 1; i <= index + 4; ++i)
    {
        if(i < 0 || i >= count || i == index)
        {
            continue;
        }
        if([pagedImageCache objectForKey: @(i)] || [pagedPrefetching containsIndex: i])
        {
            continue;
        }
        TSSTPage * page = pages[i];
        if([[page valueForKey: @"text"] boolValue])
        {
            continue;
        }

        int pageIndex = i;
        [pagedPrefetching addIndex: pageIndex];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            @autoreleasepool
            {
                NSData * data = [page pageData];
                NSImage * image = nil;
                if(data)
                {
                    image = [[NSImage alloc] initWithData: data];
                    NSArray * reps = [image representations];
                    NSImageRep * rep = [reps count] ? [reps objectAtIndex: 0] : nil;
                    NSInteger pw = rep ? [rep pixelsWide] : 0;
                    NSInteger ph = rep ? [rep pixelsHigh] : 0;
                    if(image && pw > 0 && ph > 0)
                    {
                        [image setCacheMode: NSImageCacheNever];
                        [image setSize: NSMakeSize(pw, ph)];
                    }
                    else
                    {
                        [image release];
                        image = nil;
                    }
                }

                dispatch_async(dispatch_get_main_queue(), ^{
                    [pagedPrefetching removeIndex: pageIndex];
                    NSArray * current = [pageController arrangedObjects];
                    if(image
                       && pageIndex < (int)[current count]
                       && current[pageIndex] == page)
                    {
                        [pagedImageCache setObject: image forKey: @(pageIndex)];
                    }
                    [image release];
                });
            }
        });
    }
}


- (void)clearPagedCache
{
    [pagedImageCache removeAllObjects];
    [pagedPrefetching removeAllIndexes];
}


- (void)resizeWindow
{
    NSRect allowedRect;
    NSRect zoomFrame;
    NSRect frame;
    if([[self window] isFullscreen])
    {
        allowedRect = [[[self window] screen] frame];
        [[self window] setFrame: allowedRect display: YES animate: NO];
    }
    else if([[[NSUserDefaults standardUserDefaults] valueForKey: TSSTWindowAutoResize] boolValue])
    {
        allowedRect = [[[self window] screen] visibleFrame];
		frame = [[self window] frame];
		allowedRect = NSMakeRect(frame.origin.x, NSMinY(allowedRect), 
								 NSMaxX(allowedRect) - NSMinX(frame), 
								 NSMaxY(frame) - NSMinY(allowedRect));
        zoomFrame = [self optimalPageViewRectForRect: allowedRect];
        [[self window] setFrame: zoomFrame display: YES animate: NO];
    }
}


- (void)scaleToWindow
{
    if([self isWebtoonMode])
    {
        [pageScrollView setHasVerticalScroller: YES];
        [pageScrollView setHasHorizontalScroller: NO];
        [webtoonView relayoutPreservingAnchor];
        return;
    }

    BOOL hasVert = NO;
    BOOL hasHor = NO;
	int scaling = [[session valueForKey: TSSTPageScaleOptions] intValue];
	
	if(pageSelectionInProgress || ![[[NSUserDefaults standardUserDefaults] valueForKey: TSSTScrollersVisible] boolValue])
	{
		scaling = 1;
	}
	else if([self currentPageIsText])
	{
		scaling = 2;
	}

	switch (scaling)
	{
	case  0:
		hasVert = YES;
		hasHor = YES;
		break;
	case  2:
		[session setValue: @1.0f forKey: TSSTZoomLevel];
		if([pageView rotation] == 1 || [pageView rotation] == 3)
		{
			hasHor = YES;
		}
		else
		{
			hasVert = YES;
		}
		break;
	default:	
		[session setValue: @1.0f forKey: TSSTZoomLevel];
		break;
	}
    
    [pageScrollView setHasVerticalScroller: hasVert];
    [pageScrollView setHasHorizontalScroller: hasHor];
	
	if(pageSelectionInProgress == None)
	{
		[self resizeWindow];
	}
	
    [pageView resizeView];
    [self refreshLoupePanel];
}


- (void)adjustStatusBar
{
    NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
    NSRect scrollViewRect;
    BOOL statusBar = [[defaults valueForKey: TSSTStatusbarVisible] boolValue];
    if(statusBar)
    {
        scrollViewRect = [[[self window] contentView] frame];
        scrollViewRect = NSMakeRect(NSMinX(scrollViewRect), 
                                    NSMinY(scrollViewRect) + 23,
                                    NSWidth(scrollViewRect),
                                    NSHeight(scrollViewRect) - 23);
        [[self window] setContentBorderThickness: 23 forEdge: NSMinYEdge];
        [pageScrollView setFrame: scrollViewRect];
        [progressBar setHidden: NO];
        [self resizeWindow];
    }
    else
    {
        scrollViewRect = [[[self window] contentView] frame];
        [progressBar setHidden: YES];
        [pageScrollView setFrame: scrollViewRect];
        [[self window] setContentBorderThickness: 0 forEdge: NSMinYEdge];
        [self resizeWindow];
    }
}


/*! Selects the next non visible page.  Logic looks figures out which 
images are currently visible and then skips over them.
*/
- (void)nextPage
{
    if(![[session valueForKey: TSSTTwoPageSpread] boolValue])
    {
        [pageController selectNext: self];
        return;
    }
    
    int numberOfImages = [[pageController arrangedObjects] count];
	int selectionIndex = [pageController selectionIndex];
	if((selectionIndex + 1) >= numberOfImages)
	{
		return;
	}
    
	NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
	BOOL current = ![[pageController arrangedObjects][selectionIndex] shouldDisplayAlone] &&
        !(selectionIndex == 0 &&[[defaults valueForKey: TSSTLonelyFirstPage] boolValue]);
	BOOL next = ![[pageController arrangedObjects][(selectionIndex + 1)] shouldDisplayAlone];
	
	if((!current || !next) && ((selectionIndex + 1) < numberOfImages))
	{
		[pageController setSelectionIndex: (selectionIndex + 1)];
	}
	else if((selectionIndex + 2) < numberOfImages)
	{
		[pageController setSelectionIndex: (selectionIndex + 2)];
	}
	else if(((selectionIndex + 1) < numberOfImages) && !next)
	{
		[pageController setSelectionIndex: (selectionIndex + 1)];
	}
}


/*! Selects the previous non visible page.  Logic looks figures out which 
images are currently visible and then skips over them.
*/
- (void)previousPage
{
    if(![[session valueForKey: TSSTTwoPageSpread] boolValue])
    {
        [pageController selectPrevious: self];
        return;
    }
    
	int selectionIndex = [pageController selectionIndex];
	if((selectionIndex - 2) >= 0)
	{
        NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];

        BOOL previousPage = ![[pageController arrangedObjects][(selectionIndex - 1)] shouldDisplayAlone];
		BOOL pageBeforeLast = ![[pageController arrangedObjects][(selectionIndex - 2)] shouldDisplayAlone] && 
            !((selectionIndex - 2) == 0 && [[defaults valueForKey: TSSTLonelyFirstPage] boolValue]);	
        
        if(!previousPage || !pageBeforeLast)
		{
			[pageController setSelectionIndex: (selectionIndex - 1)];
			return;
		}
		[pageController setSelectionIndex: (selectionIndex - 2)];
		return;
	}
	
	if((selectionIndex - 1) >= 0)
	{
		[pageController setSelectionIndex: (selectionIndex - 1)];
	}
}


/*! This method is called in preparation for saving. */
- (void)updateSessionObject
{
    if(![[self window] isFullscreen])
    {
        NSValue * postionValue = [NSValue valueWithRect: [[self window] frame]];
        NSData * posData = [NSArchiver archivedDataWithRootObject: postionValue];
        [session setValue: posData forKey: @"position" ];
        
        postionValue = [NSValue valueWithPoint: [[pageView enclosingScrollView] documentVisibleRect].origin];
        posData = [NSArchiver archivedDataWithRootObject: postionValue];
        [session setValue: posData forKey: TSSTScrollPosition ];
    }
    else
    {
        [session setValue: nil forKey: TSSTScrollPosition ];
    }

    [self persistProgress];
}


- (void)killTopOptionalUIElement
{
	if([exposeBezel isVisible])
	{
		[exposeBezel removeChildWindow: thumbnailPanel];
        [thumbnailPanel orderOut: self];
		[exposeBezel orderOut: self];
	}
    else if([[self window] isFullscreen])
    {
        [[self window] toggleFullScreen: self];
    }
	else if([[session valueForKey: @"loupe"] boolValue])
	{
		[session setValue: @NO forKey: @"loupe"];
	}
}


- (void)killAllOptionalUIElements
{
    if([[self window] isFullscreen])
    {
        [[self window] toggleFullScreen: self];
    }
    [session setValue: @NO forKey: @"loupe"];
    [self refreshLoupePanel];
	[exposeBezel removeChildWindow: thumbnailPanel];
	[thumbnailPanel orderOut: self];
	[exposeBezel orderOut: self];
}


#pragma mark -
#pragma mark Binding Methods


- (TSSTManagedSession *)session
{
    return session;
}


- (NSManagedObjectContext *)managedObjectContext
{
    return [(SimpleComicAppDelegate *)[NSApp delegate] managedObjectContext];
}


- (BOOL)canTurnPageLeft
{
	if([[session valueForKey: TSSTPageOrder] boolValue])
    {
        return [self canTurnPreviousPage];
    }
    else
    {
        return [self canTurnPageNext];
    }
}


- (BOOL)canTurnPageRight
{
	if([[session valueForKey: TSSTPageOrder] boolValue])
    {
        return [self canTurnPageNext];
    }
    else
    {
        return [self canTurnPreviousPage];
    }
}


/*	TODO: make the following a bit smarter.  Also the next/previous page turn logic
	ie. Should not be able to turn the page if 2 pages from the end */
- (BOOL)canTurnPreviousPage
{
	return !([pageController selectionIndex] <= 0);
}


- (BOOL)canTurnPageNext
{
	int selectionIndex = [pageController selectionIndex];
	if([pageController selectionIndex] >= ([[pageController content] count] - 1))
	{
		return NO;
	}
	
	if((selectionIndex + 1) == ([[pageController content] count] - 1) && [[session valueForKey: TSSTTwoPageSpread] boolValue])
	{
		NSArray * arrangedPages = [pageController arrangedObjects];
		BOOL displayCurrentAlone = [arrangedPages[selectionIndex] shouldDisplayAlone];
		BOOL displayNextAlone = [arrangedPages[selectionIndex + 1] shouldDisplayAlone];

		if (!displayCurrentAlone && !displayNextAlone) {
			return NO;
		}
	}
	
	return YES;	
}


#pragma mark Menus


- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	if(pageSelectionInProgress)
	{
		return NO;
	}
	
	BOOL valid = YES;
    int state;
    if([menuItem action] == @selector(toggleFullScreen:))
    {
        state = [[self window] isFullscreen] ? NSOnState : NSOffState;
        [menuItem setState: state];
    }
    else if([menuItem action] == @selector(changeTwoPage:))
    {
        state = [[session valueForKey: TSSTTwoPageSpread] boolValue] ? NSOnState : NSOffState;
        [menuItem setState: state];
    }
    else if([menuItem action] == @selector(toggleWebtoonMode:))
    {
        state = [self isWebtoonMode] ? NSOnState : NSOffState;
        [menuItem setState: state];
    }
    else if([menuItem action] == @selector(changeWebtoonGap:))
    {
        state = ([[NSUserDefaults standardUserDefaults] integerForKey: TSSTWebtoonGap] == [menuItem tag]) ? NSOnState : NSOffState;
        [menuItem setState: state];
    }
    else if([menuItem action] == @selector(changeWebtoonWidth:))
    {
        state = ([[NSUserDefaults standardUserDefaults] integerForKey: TSSTWebtoonMaxWidth] == [menuItem tag]) ? NSOnState : NSOffState;
        [menuItem setState: state];
    }
    else if([menuItem action] == @selector(changePageOrder:))
    {
        if([[session valueForKey: TSSTPageOrder] boolValue])
        {
            [menuItem setTitle: NSLocalizedString(@"Right To Left", @"Right to left page order menu item text")];
        }
        else
        {
            [menuItem setTitle: NSLocalizedString(@"Left To Right", @"Left to right page order menu item text")];
        }
    }
	else if([menuItem action] == @selector(pageRight:))
	{
		valid = [self canTurnPageRight];
	}
	else if([menuItem action] == @selector(pageLeft:))
	{
		valid = [self canTurnPageLeft];
	}
	else if ([menuItem action] == @selector(firstPage:))
	{
		valid = !([pageController selectionIndex] <= 0);
	}
	else if ([menuItem action] == @selector(lastPage:))
	{
		valid = !([pageController selectionIndex] >= ([[pageController content] count] - 1));
	}
	else if ([menuItem action] == @selector(shiftPageRight:))
	{
		valid = [self canTurnPageRight];
	}
	else if ([menuItem action] == @selector(shiftPageLeft:))
	{
		valid = [self canTurnPageLeft];
	}
	else if ([menuItem action] == @selector(skipRight:))
	{
		valid = [self canTurnPageRight];
	}
	else if ([menuItem action] == @selector(skipLeft:))
	{
		valid = [self canTurnPageLeft];
	}
	else if ([menuItem action] == @selector(setArchiveIcon:))
	{
		valid = ![[session valueForKey: TSSTViewRotation] intValue];
	}
	else if ([menuItem action] == @selector(extractPage:))
	{
		valid = ![[session valueForKey: TSSTViewRotation] intValue];
	}
	else if ([menuItem action] == @selector(removePages:))
	{
		valid = ![[session valueForKey: TSSTViewRotation] intValue];
	}
	else if ([menuItem action] == @selector(rotateSavePageRight:)
		  || [menuItem action] == @selector(rotateSavePageLeft:))
	{
		valid = ![[session valueForKey: TSSTViewRotation] intValue]
			&& [[pageController arrangedObjects] count] > 0;
	}
	else if ([menuItem action] == @selector(convertToCBZ:))
	{
		NSString * ext = [[[self workIdentifier] pathExtension] lowercaseString];
		valid = !convertingToCBZ
			&& [[TSSTManagedArchive archiveExtensions] containsObject: ext]
			&& ![ext isEqualToString: @"zip"] && ![ext isEqualToString: @"cbz"];
	}
    else if([menuItem tag] == 400)
    {
        state = [[session valueForKey: TSSTPageScaleOptions] intValue] == 0 ? NSOnState : NSOffState;
        [menuItem setState: state];
    }
    else if([menuItem tag] == 401)
    {
        state = [[session valueForKey: TSSTPageScaleOptions] intValue] == 1 ? NSOnState : NSOffState;
        [menuItem setState: state];
    }
    else if([menuItem tag] == 402)
    {
        state = [[session valueForKey: TSSTPageScaleOptions] intValue] == 2 ? NSOnState : NSOffState;
        [menuItem setState: state];
    }
	
    return valid;
}


#pragma mark -
#pragma mark Delegates


- (BOOL)control:(NSTextField *)control didFailToFormatString:(NSString *)string errorDescription:(NSString *)error
{
	int pageNumber = [string intValue];
	if(pageNumber > [[pageController arrangedObjects] count])
	{
		[jumpField setIntValue: [[pageController arrangedObjects] count]];
	}
	else
	{
		NSBeep();
		[jumpField setIntValue: [pageController selectionIndex] + 1];
	}
	
	return YES;
}


- (void)prepareToEnd
{
	[self persistProgress];
	[[self window] setAcceptsMouseMovedEvents: NO];
	[mouseMovedTimer invalidate];
	mouseMovedTimer = nil;
    [NSCursor unhide];
    [NSApp setPresentationOptions: NSApplicationPresentationDefault];
	
    [session removeObserver: self forKeyPath: TSSTPageOrder];
    [session removeObserver: self forKeyPath: TSSTPageScaleOptions];
    [session removeObserver: self forKeyPath: TSSTTwoPageSpread];
	[session removeObserver: self forKeyPath: @"loupe"];
    [session unbind: TSSTViewRotation];
    [session unbind: @"selection"];
}


- (BOOL)windowShouldClose:(id)sender
{
	if([self hasPendingArchiveEdits])
	{
		NSInteger delTotal = [pendingFolderDeletes count];
		for(NSArray * entries in [pendingArchiveDeletes allValues]) delTotal += [entries count];
		NSInteger rotTotal = [pendingFolderRotations count];
		for(NSDictionary * m in [pendingArchiveRotations allValues]) rotTotal += [m count];
		NSInteger reordTotal = [pendingFolderReorders count] + [pendingArchiveReorders count];

		NSMutableArray * parts = [NSMutableArray array];
		if(delTotal > 0) [parts addObject: [NSString stringWithFormat: @"%ld개 페이지 제거", (long)delTotal]];
		if(rotTotal > 0) [parts addObject: [NSString stringWithFormat: @"%ld개 페이지 회전", (long)rotTotal]];
		if(reordTotal > 0) [parts addObject: [NSString stringWithFormat: @"%ld개 묶음 재정렬", (long)reordTotal]];

		NSAlert * alert = [[[NSAlert alloc] init] autorelease];
		[alert setMessageText: @"변경 사항을 원본에 반영할까요?"];
		[alert setInformativeText: [NSString stringWithFormat:
			@"이 세션에서 %@했습니다. 원본 파일/아카이브에 반영하면 되돌릴 수 없습니다.",
			[parts componentsJoinedByString: @", "]]];
		[alert addButtonWithTitle: @"반영"];
		[alert addButtonWithTitle: @"되돌리기"];
		[alert addButtonWithTitle: @"취소"];
		[[alert buttons][0] setKeyEquivalent: @"\r"];
		[[alert buttons][2] setKeyEquivalent: @"\033"];

		NSModalResponse response = [alert runModal];
		if(response == NSAlertThirdButtonReturn)
		{
			return NO;
		}
		else if(response == NSAlertFirstButtonReturn)
		{
			[self commitPendingDeletions];
			[self commitPendingRotations];
			[self commitPendingReorders];
		}
		else
		{
			[self discardPendingDeletions];
		}
	}

	[self prepareToEnd];
	[[NSNotificationCenter defaultCenter] postNotificationName: TSSTSessionEndNotification object: self];

    return YES;
}


#pragma mark - Page rotation (deferred save)


static NSBitmapImageFileType SCBitmapFileType(NSString * ext)
{
	ext = [ext lowercaseString];
	if([ext isEqualToString: @"png"])  return NSBitmapImageFileTypePNG;
	if([ext isEqualToString: @"gif"])  return NSBitmapImageFileTypeGIF;
	if([ext isEqualToString: @"bmp"])  return NSBitmapImageFileTypeBMP;
	if([ext isEqualToString: @"tif"] || [ext isEqualToString: @"tiff"]) return NSBitmapImageFileTypeTIFF;
	return NSBitmapImageFileTypeJPEG;
}


/* Returns src rotated clockwise by `cw` degrees as a displayable image. */
static NSImage * SCRotatedImage(NSImage * src, NSInteger cw)
{
	cw = ((cw % 360) + 360) % 360;
	if(cw == 0 || !src)
	{
		return src;
	}
	NSSize s = [src size];
	NSSize ts = (cw == 90 || cw == 270) ? NSMakeSize(s.height, s.width) : s;
	NSImage * out = [[[NSImage alloc] initWithSize: ts] autorelease];
	[out lockFocus];
	[[NSGraphicsContext currentContext] setImageInterpolation: NSImageInterpolationHigh];
	NSAffineTransform * t = [NSAffineTransform transform];
	[t translateXBy: ts.width / 2.0 yBy: ts.height / 2.0];
	[t rotateByDegrees: -cw];
	[t concat];
	[src drawInRect: NSMakeRect(-s.width / 2.0, -s.height / 2.0, s.width, s.height)
		   fromRect: NSZeroRect
		  operation: NSCompositingOperationSourceOver
		   fraction: 1.0];
	[out unlockFocus];
	return out;
}


/* Returns src image data rotated clockwise by `cw`, re-encoded in the
   image format implied by `ext` (so the file/entry keeps its type). */
static NSData * SCRotatedImageData(NSData * src, NSInteger cw, NSString * ext)
{
	cw = ((cw % 360) + 360) % 360;
	if(!src || cw == 0)
	{
		return src;
	}
	NSBitmapImageRep * rep = [NSBitmapImageRep imageRepWithData: src];
	if(!rep)
	{
		return nil;
	}
	NSInteger w = [rep pixelsWide];
	NSInteger h = [rep pixelsHigh];
	NSSize ts = (cw == 90 || cw == 270) ? NSMakeSize(h, w) : NSMakeSize(w, h);
	NSImage * img = [[[NSImage alloc] initWithSize: ts] autorelease];
	[img lockFocus];
	[[NSGraphicsContext currentContext] setImageInterpolation: NSImageInterpolationHigh];
	NSAffineTransform * t = [NSAffineTransform transform];
	[t translateXBy: ts.width / 2.0 yBy: ts.height / 2.0];
	[t rotateByDegrees: -cw];
	[t concat];
	[rep drawInRect: NSMakeRect(-w / 2.0, -h / 2.0, w, h)];
	NSBitmapImageRep * outRep = [[[NSBitmapImageRep alloc]
		initWithFocusedViewRect: NSMakeRect(0, 0, ts.width, ts.height)] autorelease];
	[img unlockFocus];
	if(!outRep)
	{
		return nil;
	}
	NSBitmapImageFileType ft = SCBitmapFileType(ext);
	NSDictionary * props = (ft == NSBitmapImageFileTypeJPEG)
		? @{ NSImageCompressionFactor: @0.9 } : @{};
	return [outRep representationUsingType: ft properties: props];
}


- (NSInteger)pendingRotationForPage:(TSSTPage *)page
{
	TSSTManagedGroup * group = [page valueForKey: @"group"];
	NSString * entry = [page valueForKey: @"imagePath"];
	if([group isKindOfClass: [TSSTManagedArchive class]])
	{
		NSString * ap = [group valueForKey: @"path"];
		return ap && entry ? [pendingArchiveRotations[ap][entry] integerValue] : 0;
	}
	return entry ? [pendingFolderRotations[entry] integerValue] : 0;
}


- (NSImage *)rotatedImageIfNeeded:(NSImage *)image forPage:(TSSTPage *)page
{
	if(!image)
	{
		return image;
	}
	NSInteger r = [self pendingRotationForPage: page];
	return r ? SCRotatedImage(image, r) : image;
}


- (void)recordRotationDelta:(NSInteger)delta
{
	NSArray * pages = [pageController arrangedObjects];
	NSInteger idx = [pageController selectionIndex];
	if(idx < 0 || idx >= (NSInteger)[pages count])
	{
		NSBeep();
		return;
	}
	TSSTPage * page = pages[idx];
	if([[page valueForKey: @"text"] boolValue])
	{
		NSBeep();
		return;
	}

	TSSTManagedGroup * group = [page valueForKey: @"group"];
	NSString * entry = [page valueForKey: @"imagePath"];

	if([group isKindOfClass: [TSSTManagedArchive class]])
	{
		NSString * ap = [group valueForKey: @"path"];
		NSString * ext = [[ap pathExtension] lowercaseString];
		if(!([ext isEqualToString: @"zip"] || [ext isEqualToString: @"cbz"]))
		{
			NSAlert * a = [[[NSAlert alloc] init] autorelease];
			[a setMessageText: @"회전 저장을 지원하지 않는 형식"];
			[a setInformativeText: @"페이지 회전 저장은 CBZ/ZIP 아카이브와 폴더에서만 가능합니다."];
			[a addButtonWithTitle: @"확인"];
			[a runModal];
			return;
		}
		if(!ap || !entry)
		{
			NSBeep();
			return;
		}
		NSMutableDictionary * m = pendingArchiveRotations[ap];
		if(!m)
		{
			m = [NSMutableDictionary dictionary];
			pendingArchiveRotations[ap] = m;
		}
		NSInteger nv = (([m[entry] integerValue] + delta) % 360 + 360) % 360;
		if(nv == 0) { [m removeObjectForKey: entry]; }
		else        { m[entry] = @(nv); }
		if([m count] == 0) { [pendingArchiveRotations removeObjectForKey: ap]; }
	}
	else if(entry && [entry isAbsolutePath])
	{
		NSInteger nv = (([pendingFolderRotations[entry] integerValue] + delta) % 360 + 360) % 360;
		if(nv == 0) { [pendingFolderRotations removeObjectForKey: entry]; }
		else        { pendingFolderRotations[entry] = @(nv); }
	}
	else
	{
		NSBeep();
		return;
	}

	[pagedImageCache removeObjectForKey: @(idx)];
	[self changeViewImages];
	if([self isWebtoonMode] && webtoonView)
	{
		[webtoonView relayoutPreservingAnchor];
	}
}


- (IBAction)convertToCBZ:(id)sender
{
	NSString * path = [self workIdentifier];
	NSString * ext = [[path pathExtension] lowercaseString];
	if([path length] == 0
	   || ![[TSSTManagedArchive archiveExtensions] containsObject: ext]
	   || [ext isEqualToString: @"zip"] || [ext isEqualToString: @"cbz"]
	   || ![[NSFileManager defaultManager] fileExistsAtPath: path]
	   || convertingToCBZ)
	{
		NSBeep();
		return;
	}
	convertingToCBZ = YES;

	NSString * pathCopy = [[path copy] autorelease];
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		NSString * result = nil;
		NSString * errMsg = nil;
		@autoreleasepool
		{
			result = [[self convertArchiveToCBZ: pathCopy error: &errMsg] retain];
			[errMsg retain];
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			convertingToCBZ = NO;
			if(result)
			{
				[(SimpleComicAppDelegate *)[NSApp delegate] openWorkAtPath: result];
			}
			else
			{
				NSAlert * a = [[[NSAlert alloc] init] autorelease];
				[a setMessageText: @"CBZ 변환 실패"];
				[a setInformativeText: errMsg ? errMsg : @"아카이브를 추출하지 못했습니다."];
				[a addButtonWithTitle: @"확인"];
				[a runModal];
			}
			[result release];
			[errMsg release];
		});
	});
}


/*  Extracts a non-zip archive into a temp folder and repackages it as a
    sibling .cbz (original kept).  Returns the new path, or nil + errMsg.
    Runs off the main thread. */
- (NSString *)convertArchiveToCBZ:(NSString *)archivePath error:(NSString **)errMsg
{
	NSFileManager * fm = [NSFileManager defaultManager];
	NSString * dir = [archivePath stringByDeletingLastPathComponent];
	NSString * base = [[archivePath lastPathComponent] stringByDeletingPathExtension];
	NSString * uid = [[NSProcessInfo processInfo] globallyUniqueString];
	NSString * staging = [dir stringByAppendingPathComponent:
		[NSString stringWithFormat: @".sc-convert-%@", uid]];
	[fm createDirectoryAtPath: staging withIntermediateDirectories: YES attributes: nil error: NULL];

	XADArchive * ar = [[[XADArchive alloc] initWithFile: archivePath delegate: nil error: NULL] autorelease];
	if(!ar || ![ar extractTo: staging])
	{
		[fm removeItemAtPath: staging error: NULL];
		if(errMsg) *errMsg = @"아카이브 추출 실패 (지원되지 않거나 암호 보호된 형식).";
		return nil;
	}

	NSString * target = [dir stringByAppendingPathComponent: [base stringByAppendingPathExtension: @"cbz"]];
	NSInteger dedupe = 1;
	while([fm fileExistsAtPath: target])
	{
		target = [dir stringByAppendingPathComponent:
			[NSString stringWithFormat: @"%@ (%ld).cbz", base, (long)(++dedupe)]];
	}
	NSString * tmpZip = [dir stringByAppendingPathComponent:
		[NSString stringWithFormat: @".sc-convert-%@.zip", uid]];

	NSTask * zip = [[[NSTask alloc] init] autorelease];
	[zip setLaunchPath: @"/usr/bin/zip"];
	[zip setCurrentDirectoryPath: staging];
	[zip setArguments: @[@"-X", @"-r", @"-q", tmpZip, @"."]];
	[zip setStandardOutput: [NSPipe pipe]];
	[zip setStandardError: [NSPipe pipe]];
	int status = -1;
	@try { [zip launch]; [zip waitUntilExit]; status = [zip terminationStatus]; }
	@catch(NSException * e) { NSLog(@"convert zip %@: %@", archivePath, e); }

	NSString * result = nil;
	if(status == 0 && [fm fileExistsAtPath: tmpZip] && [fm moveItemAtPath: tmpZip toPath: target error: NULL])
	{
		result = target;
	}
	else
	{
		[fm removeItemAtPath: tmpZip error: NULL];
		if(errMsg) *errMsg = @"CBZ 생성 실패.";
	}
	[fm removeItemAtPath: staging error: NULL];
	return result;
}


- (IBAction)rotateSavePageRight:(id)sender
{
	[self recordRotationDelta: 90];
}


- (IBAction)rotateSavePageLeft:(id)sender
{
	[self recordRotationDelta: -90];
}


- (BOOL)hasPendingArchiveEdits
{
	return [pendingArchiveDeletes count] > 0 || [pendingFolderDeletes count] > 0
		|| [pendingArchiveRotations count] > 0 || [pendingFolderRotations count] > 0
		|| [pendingArchiveReorders count] > 0 || [pendingFolderReorders count] > 0;
}


- (void)rebaseOrdinalsToCurrentOrder
{
	NSArray * pages = [pageController arrangedObjects];
	NSUInteger n = [pages count];
	for(NSUInteger i = 0; i < n; ++i)
	{
		SCSetOrdinalForPage(pages[i], (double)i);
	}
}


/*  Called by the thumbnail expose when the user drag-reorders.  Both
    indices are positions in the controller's current arrangedObjects.
    Cross-group moves are rejected; the new order is materialised by
    rebasing ordinals so the array controller resorts instantly. */
- (void)thumbnailView:(id)view didMovePageFromIndex:(NSInteger)from toIndex:(NSInteger)to
{
	NSArray * pages = [pageController arrangedObjects];
	NSInteger n = (NSInteger)[pages count];
	if(from < 0 || from >= n || to < 0 || to >= n || from == to)
	{
		return;
	}

	TSSTPage * src = pages[from];
	TSSTPage * dst = pages[to];
	TSSTManagedGroup * group = [src valueForKey: @"group"];
	if(group != [dst valueForKey: @"group"])
	{
		NSBeep();
		return;
	}

	if([group isKindOfClass: [TSSTManagedArchive class]])
	{
		NSString * ap = [group valueForKey: @"path"];
		NSString * ext = [[ap pathExtension] lowercaseString];
		if(!([ext isEqualToString: @"zip"] || [ext isEqualToString: @"cbz"]))
		{
			NSAlert * a = [[[NSAlert alloc] init] autorelease];
			[a setMessageText: @"재정렬을 지원하지 않는 형식"];
			[a setInformativeText: @"페이지 재정렬은 CBZ/ZIP 아카이브와 폴더에서만 가능합니다."];
			[a addButtonWithTitle: @"확인"];
			[a runModal];
			return;
		}
	}

	NSMutableArray * mutable = [NSMutableArray arrayWithArray: pages];
	TSSTPage * moving = [[mutable[from] retain] autorelease];
	[mutable removeObjectAtIndex: from];
	[mutable insertObject: moving atIndex: to];

	for(NSUInteger i = 0; i < [mutable count]; ++i)
	{
		SCSetOrdinalForPage(mutable[i], (double)i);
	}
	[pageController rearrangeObjects];

	/* Capture the within-group ordered names / paths for the commit step. */
	NSMutableArray * groupOrder = [NSMutableArray array];
	for(TSSTPage * p in [pageController arrangedObjects])
	{
		if([p valueForKey: @"group"] != group)
		{
			continue;
		}
		NSString * key = [p valueForKey: @"imagePath"];
		if(key) [groupOrder addObject: key];
	}

	if([group isKindOfClass: [TSSTManagedArchive class]])
	{
		NSString * ap = [group valueForKey: @"path"];
		if(ap) pendingArchiveReorders[ap] = groupOrder;
	}
	else
	{
		NSString * fp = [group valueForKey: @"path"];
		if(fp) pendingFolderReorders[fp] = groupOrder;
	}

	[(TSSTThumbnailView *)exposeView setNeedsDisplay: YES];
	[(TSSTThumbnailView *)exposeView buildTrackingRects];
}


- (void)commitPendingRotations
{
	NSFileManager * fm = [NSFileManager defaultManager];

	for(NSString * path in [pendingFolderRotations allKeys])
	{
		NSInteger deg = [pendingFolderRotations[path] integerValue];
		if(deg == 0 || ![fm fileExistsAtPath: path]) continue;
		NSData * rotated = SCRotatedImageData([NSData dataWithContentsOfFile: path],
											  deg, [path pathExtension]);
		if(rotated) [rotated writeToFile: path atomically: YES];
	}
	[pendingFolderRotations removeAllObjects];

	if([pendingArchiveRotations count] == 0)
	{
		return;
	}

	NSMutableDictionary * pathToGroup = [NSMutableDictionary dictionary];
	for(TSSTPage * p in [pageController arrangedObjects])
	{
		TSSTManagedGroup * g = [p valueForKey: @"group"];
		if([g isKindOfClass: [TSSTManagedArchive class]])
		{
			NSString * gp = [g valueForKey: @"path"];
			if(gp && !pathToGroup[gp]) pathToGroup[gp] = g;
		}
	}

	for(NSString * archivePath in [pendingArchiveRotations allKeys])
	{
		NSDictionary * entries = pendingArchiveRotations[archivePath];
		if(![entries count] || ![fm fileExistsAtPath: archivePath]) continue;

		NSString * tmpRoot = [NSTemporaryDirectory()
			stringByAppendingPathComponent: [[NSProcessInfo processInfo] globallyUniqueString]];
		[fm createDirectoryAtPath: tmpRoot withIntermediateDirectories: YES attributes: nil error: NULL];

		XADArchive * ar = [[[XADArchive alloc] initWithFile: archivePath delegate: nil error: NULL] autorelease];
		NSInteger n = ar ? [ar numberOfEntries] : 0;
		NSMutableArray * written = [NSMutableArray array];
		for(NSInteger i = 0; i < n; i++)
		{
			if([ar entryIsDirectory: (int)i]) continue;
			NSString * name = [ar nameOfEntry: (int)i];
			NSNumber * degN = name ? entries[name] : nil;
			if(!degN) continue;
			NSData * rotated = SCRotatedImageData([ar contentsOfEntry: (int)i],
												  [degN integerValue], [name pathExtension]);
			if(!rotated) continue;
			NSString * dest = [tmpRoot stringByAppendingPathComponent: name];
			[fm createDirectoryAtPath: [dest stringByDeletingLastPathComponent]
		  withIntermediateDirectories: YES attributes: nil error: NULL];
			if([rotated writeToFile: dest atomically: YES]) [written addObject: name];
		}

		if([written count] > 0)
		{
			NSTask * task = [[[NSTask alloc] init] autorelease];
			[task setLaunchPath: @"/usr/bin/zip"];
			[task setCurrentDirectoryPath: tmpRoot];
			NSMutableArray * args = [NSMutableArray arrayWithObjects: @"-X", archivePath, nil];
			[args addObjectsFromArray: written];
			[task setArguments: args];
			[task setStandardOutput: [NSPipe pipe]];
			[task setStandardError: [NSPipe pipe]];
			@try { [task launch]; [task waitUntilExit]; }
			@catch(NSException * e) { NSLog(@"zip rotate task for %@: %@", archivePath, e); }

			TSSTManagedArchive * group = pathToGroup[archivePath];
			if(group) [group invalidateInstance];
		}

		[fm removeItemAtPath: tmpRoot error: NULL];
	}
	[pendingArchiveRotations removeAllObjects];
	[self clearPagedCache];
}


- (void)commitPendingReorders
{
	NSFileManager * fm = [NSFileManager defaultManager];

	/* Folder reorder: 2-step rename so cycles (A wants B's slot and vice
	   versa) cannot collide. */
	for(NSString * folderPath in [pendingFolderReorders allKeys])
	{
		NSArray * order = pendingFolderReorders[folderPath];
		if(![order count]) continue;

		NSMutableArray * tmpPaths = [NSMutableArray array];
		for(NSString * orig in order)
		{
			NSString * ext = [[orig pathExtension] lowercaseString];
			NSString * tmp = [folderPath stringByAppendingPathComponent:
				[NSString stringWithFormat: @".sc-reorder-%@.%@",
					[[NSProcessInfo processInfo] globallyUniqueString],
					[ext length] ? ext : @"bin"]];
			if([fm moveItemAtPath: orig toPath: tmp error: NULL])
			{
				[tmpPaths addObject: tmp];
			}
			else
			{
				[tmpPaths addObject: [NSNull null]];
			}
		}

		for(NSUInteger i = 0; i < [tmpPaths count]; ++i)
		{
			id tmp = tmpPaths[i];
			if(tmp == [NSNull null]) continue;
			NSString * ext = [[tmp pathExtension] lowercaseString];
			NSString * finalPath = [folderPath stringByAppendingPathComponent:
				[NSString stringWithFormat: @"page%04lu.%@", (unsigned long)(i + 1),
					[ext length] ? ext : @"bin"]];
			if([fm fileExistsAtPath: finalPath])
			{
				[fm removeItemAtPath: finalPath error: NULL];
			}
			[fm moveItemAtPath: tmp toPath: finalPath error: NULL];
		}
	}
	[pendingFolderReorders removeAllObjects];

	if([pendingArchiveReorders count] == 0)
	{
		return;
	}

	NSMutableDictionary * pathToGroup = [NSMutableDictionary dictionary];
	for(TSSTPage * p in [pageController arrangedObjects])
	{
		TSSTManagedGroup * g = [p valueForKey: @"group"];
		if([g isKindOfClass: [TSSTManagedArchive class]])
		{
			NSString * gp = [g valueForKey: @"path"];
			if(gp && !pathToGroup[gp]) pathToGroup[gp] = g;
		}
	}

	/* Archive reorder: extract -> rename to pageNNNN.<ext> flat -> rezip
	   -> atomically replace the original.  Original subdirectory layout
	   and any non-image entries are dropped, which is the cost of getting
	   a clean reading order. */
	for(NSString * archivePath in [pendingArchiveReorders allKeys])
	{
		NSArray * order = pendingArchiveReorders[archivePath];
		if(![order count] || ![fm fileExistsAtPath: archivePath]) continue;

		NSString * dir = [archivePath stringByDeletingLastPathComponent];
		NSString * uid = [[NSProcessInfo processInfo] globallyUniqueString];
		NSString * extractDir = [dir stringByAppendingPathComponent:
			[NSString stringWithFormat: @".sc-reorder-x-%@", uid]];
		NSString * stagingDir = [dir stringByAppendingPathComponent:
			[NSString stringWithFormat: @".sc-reorder-s-%@", uid]];
		NSString * tmpZip = [dir stringByAppendingPathComponent:
			[NSString stringWithFormat: @".sc-reorder-%@.zip", uid]];

		[fm createDirectoryAtPath: extractDir withIntermediateDirectories: YES attributes: nil error: NULL];
		[fm createDirectoryAtPath: stagingDir withIntermediateDirectories: YES attributes: nil error: NULL];

		NSTask * unzip = [[[NSTask alloc] init] autorelease];
		[unzip setLaunchPath: @"/usr/bin/unzip"];
		[unzip setArguments: @[@"-qq", @"-o", archivePath, @"-d", extractDir]];
		[unzip setStandardOutput: [NSPipe pipe]];
		[unzip setStandardError: [NSPipe pipe]];
		int ustatus = -1;
		@try { [unzip launch]; [unzip waitUntilExit]; ustatus = [unzip terminationStatus]; }
		@catch(NSException * e) { NSLog(@"unzip reorder %@: %@", archivePath, e); }

		if(ustatus > 2)
		{
			NSLog(@"unzip failed (%d) for reorder of %@", ustatus, archivePath);
			[fm removeItemAtPath: extractDir error: NULL];
			[fm removeItemAtPath: stagingDir error: NULL];
			continue;
		}

		for(NSUInteger i = 0; i < [order count]; ++i)
		{
			NSString * orig = order[i];
			NSString * src = [extractDir stringByAppendingPathComponent: orig];
			if(![fm fileExistsAtPath: src]) continue;
			NSString * ext = [[orig pathExtension] lowercaseString];
			NSString * dst = [stagingDir stringByAppendingPathComponent:
				[NSString stringWithFormat: @"page%04lu.%@", (unsigned long)(i + 1),
					[ext length] ? ext : @"bin"]];
			[fm moveItemAtPath: src toPath: dst error: NULL];
		}

		NSTask * zip = [[[NSTask alloc] init] autorelease];
		[zip setLaunchPath: @"/usr/bin/zip"];
		[zip setCurrentDirectoryPath: stagingDir];
		[zip setArguments: @[@"-X", @"-r", @"-q", tmpZip, @"."]];
		[zip setStandardOutput: [NSPipe pipe]];
		[zip setStandardError: [NSPipe pipe]];
		int zstatus = -1;
		@try { [zip launch]; [zip waitUntilExit]; zstatus = [zip terminationStatus]; }
		@catch(NSException * e) { NSLog(@"zip rebuild %@: %@", archivePath, e); }

		if(zstatus == 0 && [fm fileExistsAtPath: tmpZip])
		{
			NSURL * resulting = nil;
			NSError * err = nil;
			if(![fm replaceItemAtURL: [NSURL fileURLWithPath: archivePath]
					   withItemAtURL: [NSURL fileURLWithPath: tmpZip]
					  backupItemName: nil
							 options: 0
					resultingItemURL: &resulting
							   error: &err])
			{
				NSLog(@"replace failed for %@: %@", archivePath, err);
				[fm removeItemAtPath: tmpZip error: NULL];
			}
			TSSTManagedArchive * group = pathToGroup[archivePath];
			if(group) [group invalidateInstance];
		}
		else
		{
			NSLog(@"zip rebuild failed (%d) for %@", zstatus, archivePath);
			[fm removeItemAtPath: tmpZip error: NULL];
		}

		[fm removeItemAtPath: extractDir error: NULL];
		[fm removeItemAtPath: stagingDir error: NULL];
	}
	[pendingArchiveReorders removeAllObjects];
	[self clearPagedCache];
}


- (void)commitPendingDeletions
{
	NSFileManager * fm = [NSFileManager defaultManager];

	/* Remove loose folder image files. */
	for(NSString * path in pendingFolderDeletes)
	{
		NSError * err = nil;
		if(![fm removeItemAtPath: path error: &err])
		{
			NSLog(@"removeItem %@: %@", path, err);
		}
	}
	[pendingFolderDeletes removeAllObjects];

	if([pendingArchiveDeletes count] == 0)
	{
		[(SimpleComicAppDelegate *)[NSApp delegate] saveContext];
		return;
	}

	/* Resolve archive groups by path so we can update indices and invalidate
	   the cached XADArchive instance after the zip is rewritten. */
	NSMutableDictionary * pathToGroup = [NSMutableDictionary dictionary];
	for(TSSTPage * p in [pageController arrangedObjects])
	{
		TSSTManagedGroup * g = [p valueForKey: @"group"];
		if([g isKindOfClass: [TSSTManagedArchive class]])
		{
			NSString * gp = [g valueForKey: @"path"];
			if(gp && !pathToGroup[gp]) pathToGroup[gp] = g;
		}
	}

	for(NSString * archivePath in [pendingArchiveDeletes allKeys])
	{
		NSArray * entries = pendingArchiveDeletes[archivePath];
		if(![entries count]) continue;
		if(![fm fileExistsAtPath: archivePath]) continue;

		/* Delete the entries AND their paired __MACOSX AppleDouble metadata
		   to keep XADArchive from promoting orphan metadata into ghost
		   pages on the next open. */
		NSMutableArray * deleteList = [NSMutableArray arrayWithArray: entries];
		for(NSString * entry in entries)
		{
			NSString * dir = [entry stringByDeletingLastPathComponent];
			NSString * base = [entry lastPathComponent];
			NSString * appleDouble = [dir length]
				? [NSString stringWithFormat: @"__MACOSX/%@/._%@", dir, base]
				: [NSString stringWithFormat: @"__MACOSX/._%@", base];
			[deleteList addObject: appleDouble];
		}

		NSTask * task = [[[NSTask alloc] init] autorelease];
		[task setLaunchPath: @"/usr/bin/zip"];
		NSMutableArray * args = [NSMutableArray arrayWithObjects: @"-d", archivePath, nil];
		[args addObjectsFromArray: deleteList];
		[task setArguments: args];
		[task setStandardOutput: [NSPipe pipe]];
		[task setStandardError: [NSPipe pipe]];

		int status = -1;
		@try
		{
			[task launch];
			[task waitUntilExit];
			status = [task terminationStatus];
		}
		@catch(NSException * e)
		{
			NSLog(@"zip task exception for %@: %@", archivePath, e);
			continue;
		}

		/* zip -d returns 12 if some named entries weren't found (the
		   AppleDouble partners often aren't); that's fine as long as the
		   actual entries were deleted. We only bail on more serious errors. */
		if(status != 0 && status != 12)
		{
			NSLog(@"zip -d failed (status %d) for %@", status, archivePath);
			continue;
		}

		/* Re-read the modified archive and update each surviving page's
		   stored `index` so it matches the new entry positions. Apply the
		   same data-fork filter so orphan AppleDouble entries don't
		   pollute the map. */
		TSSTManagedArchive * group = pathToGroup[archivePath];
		if(!group) continue;

		XADArchive * fresh = [[XADArchive alloc] initWithFile: archivePath delegate: nil error: NULL];
		if(fresh)
		{
			NSMutableDictionary * nameToIndex = [NSMutableDictionary dictionary];
			NSInteger n = [fresh numberOfEntries];
			for(NSInteger i = 0; i < n; i++)
			{
				if(![fresh dataForkParserDictionaryForEntry: (int)i]) continue;
				NSString * name = [fresh nameOfEntry: (int)i];
				if(name) nameToIndex[name] = @(i);
			}
			[fresh release];

			for(TSSTPage * p in [pageController arrangedObjects])
			{
				if([p valueForKey: @"group"] != group) continue;
				NSString * entryName = [p valueForKey: @"imagePath"];
				NSNumber * newIdx = entryName ? nameToIndex[entryName] : nil;
				if(newIdx) [p setValue: newIdx forKey: @"index"];
			}
		}

		[group invalidateInstance];
	}
	[pendingArchiveDeletes removeAllObjects];

	[(SimpleComicAppDelegate *)[NSApp delegate] saveContext];
}


- (void)discardPendingDeletions
{
	[pendingFolderDeletes removeAllObjects];
	[pendingArchiveDeletes removeAllObjects];
	[pendingFolderRotations removeAllObjects];
	[pendingArchiveRotations removeAllObjects];
	[pendingFolderReorders removeAllObjects];
	[pendingArchiveReorders removeAllObjects];
	[[self managedObjectContext] rollback];
}


- (void)windowDidBecomeKey:(NSNotification *)aNotification
{
    if([aNotification object] == [self window])
    {
        [NSApp setPresentationOptions: NSApplicationPresentationDefault];
		if([[session valueForKey: @"loupe"] boolValue])
		{
			[NSCursor hide];
		}
		[self refreshLoupePanel];
    }
}


- (void)windowDidResignKey:(NSNotification *)aNotification
{
    if([aNotification object] == exposeBezel)
    {
        [exposeBezel orderOut: self];
    }
	
	if([aNotification object] == [self window])
	{
		[NSCursor unhide];
		[self refreshLoupePanel];
		[[infoWindow parentWindow] removeChildWindow: infoWindow];
		[infoWindow orderOut: self];
	}
}


- (void)windowDidResize:(NSNotification *)aNotification
{
	BOOL statusBar;
    if([aNotification object] == [self window])
    {
		[[infoWindow parentWindow] removeChildWindow: infoWindow];
        [infoWindow orderOut: self];

        statusBar = [[[NSUserDefaults standardUserDefaults] valueForKey: TSSTStatusbarVisible] boolValue];

		
        if(statusBar)
        {
            NSPoint mouse = [NSEvent mouseLocation];
            NSRect point = NSMakeRect(mouse.x, mouse.y, 0, 0);
            NSPoint mouseLocation = [[self window] convertRectFromScreen: point].origin;

            NSRect progressRect = [[[self window] contentView] convertRect: [progressBar progressRect] fromView: progressBar];
			BOOL cursorInside = NSMouseInRect(mouseLocation, progressRect, [[[self window] contentView] isFlipped]);
			if(cursorInside && ![pageView inLiveResize])
			{
				[self infoPanelSetupAtPoint: mouseLocation];
				[[self window] addChildWindow: infoWindow ordered: NSWindowAbove];
			}
        }
	}
}


/*	This method deals with window resizing.  It is called every time the user clicks 
	the nice little plus button in the upper left of the window. */
- (NSRect)windowWillUseStandardFrame:(NSWindow *)sender defaultFrame:(NSRect)defaultFrame
{
    if(sender == [self window])
    {
        defaultFrame = [self optimalPageViewRectForRect: defaultFrame];
    }
	
    return defaultFrame;
}


- (NSRect)optimalPageViewRectForRect:(NSRect)boundingRect
{
	NSSize maxImageSize = [pageView combinedImageSizeForZoom: [[session valueForKey: TSSTZoomLevel] floatValue]];
	float vertOffset = [[self window] contentBorderThicknessForEdge: NSMinYEdge] + [[self window] toolbarHeight];
	if([pageScrollView hasHorizontalScroller])
	{
		vertOffset += NSHeight([[pageScrollView horizontalScroller] frame]);
	}
	float horOffset = [pageScrollView hasVerticalScroller] ? NSWidth([[pageScrollView verticalScroller] frame]) : 0;
	NSSize minSize = [[self window] minSize];
	NSRect correctedFrame = boundingRect;
	correctedFrame.size.width = NSWidth(correctedFrame) < minSize.width ? minSize.width : NSWidth(correctedFrame);
	correctedFrame.size.height = NSHeight(correctedFrame) < minSize.height ? minSize.height : NSHeight(correctedFrame);
	correctedFrame.size.width -= horOffset;
	correctedFrame.size.height -= vertOffset;
	NSSize newSize;
	if([[session valueForKey: TSSTPageScaleOptions] intValue] == 1 && ![self currentPageIsText])
	{
		float scale;
		if( maxImageSize.width < NSWidth(correctedFrame) && maxImageSize.height < NSHeight(correctedFrame))
		{
			scale = 1;
		}
		else if( NSWidth(correctedFrame) / NSHeight(correctedFrame) < maxImageSize.width / maxImageSize.height)
		{
			scale = NSWidth(correctedFrame) / maxImageSize.width;
		}
		else
		{
			scale = NSHeight(correctedFrame) / maxImageSize.height;
		}
		newSize = scaleSize(maxImageSize, scale);
	}
	else
	{
		newSize.width = maxImageSize.width < NSWidth(correctedFrame) ? maxImageSize.width : NSWidth(correctedFrame);
		newSize.height = maxImageSize.height < NSHeight(correctedFrame) ? maxImageSize.height : NSHeight(correctedFrame);
	}
	
	newSize.width += horOffset;
	newSize.height += vertOffset;
	
	newSize.width = newSize.width < minSize.width ? minSize.width : newSize.width;
	newSize.height = newSize.height < minSize.height ? minSize.height : newSize.height;
	
	NSRect windowFrame = NSMakeRect(NSMinX(boundingRect), NSMaxY(boundingRect) - newSize.height, newSize.width, newSize.height);
	return windowFrame;
}

- (void)resizeView
{
    if([self isWebtoonMode])
    {
        [webtoonView relayoutPreservingAnchor];
        return;
    }
    [pageView resizeView];
}


- (BOOL)currentPageIsText
{
    NSArray* selectedObjects = [pageController selectedObjects];
    if (selectedObjects.count == 0) return false;
    
	TSSTPage * page = selectedObjects[0];
	return [[page valueForKey: @"text"] boolValue];
}


- (void)toolbarWillAddItem:(NSNotification *)notification
{
	NSToolbarItem * item = [notification userInfo][@"item"];
	
	if([[item label] isEqualToString: @"Page Scaling"])
	{
		[[item view] bind: @"selectedIndex" toObject: self withKeyPath: @"session.scaleOptions" options: nil];
	}
	else if([[item label] isEqualToString: @"Page Order"])
	{
		[[item view] bind: @"selectedIndex" toObject: self withKeyPath: @"session.pageOrder" options: nil];
	}
	else if([[item label] isEqualToString: @"Page Layout"])
	{
		[[item view] bind: @"selectedIndex" toObject: self withKeyPath: @"session.twoPageSpread" options: nil];
	}
	else if([[item label] isEqualToString: @"Loupe"])
	{
		[[item view] bind: @"value" toObject: self withKeyPath: @"session.loupe" options: nil];
	}
}


#pragma Fullscreen Delegate Methods

- (NSApplicationPresentationOptions)window:(NSWindow *)window willUseFullScreenPresentationOptions:(NSApplicationPresentationOptions)proposedOptions
{
    if([[self window] isEqual: window])
    {
        return NSApplicationPresentationHideDock |
        NSApplicationPresentationAutoHideToolbar |
        NSApplicationPresentationAutoHideMenuBar |
        NSApplicationPresentationFullScreen;
    }
    
    return NSApplicationPresentationDefault;
}

- (void)windowWillEnterFullScreen:(NSNotification *)notification
{
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification
{
//    [self resizeWindow];
    [self refreshLoupePanel];
}

- (void)windowDidExitFullScreen:(NSNotification *)notification
{
    [self resizeWindow];
}

- (void)window:(NSWindow *)window startCustomAnimationToEnterFullScreenWithDuration:(NSTimeInterval)duration
{
//    NSRect startingFrame = [window frame];
    [self invalidateRestorableState];
    
    NSRect screenFrame = [[[self window] screen] visibleFrame];
    
    NSRect proposedFrame = screenFrame;
    
    
    // The center frame for each window is used during the 1st half of the fullscreen animation and is
    // the window at its original size but moved to the center of its eventual full screen frame.
//    NSRect centerWindowFrame = rectWithSizeCenteredInRect(startingFrame.size, screenFrame);
    
    // Our animation will be broken into two stages.
    // First, we'll move the window to the center of the primary screen and then we'll enlarge
    // it its full screen size.
    //
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        
        [context setDuration:duration/4];
        [[window animator] setFrame:proposedFrame display:YES];
        
    } completionHandler:^{
        
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            
            [context setDuration:duration/4];
            [[window animator] setFrame:proposedFrame display:YES];
            
        } completionHandler:^{
            
        }];
    }];
}


- (NSArray *)customWindowsToEnterFullScreenForWindow:(NSWindow *)window
{
    return @[[self window]];
}




@end

