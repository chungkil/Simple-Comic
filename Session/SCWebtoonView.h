/*
    SCWebtoonView.h

    Continuous vertical-scroll ("webtoon") document view.  Stitches every
    page of a session into one seamless top-to-bottom strip, each page
    scaled to fit the scroll view width.  Images are decoded lazily on a
    background queue and held in a small LRU cache so that arbitrarily
    long chapters scroll without decoding or holding every page at once.
 */

#import <Cocoa/Cocoa.h>

@class TSSTSessionWindowController;

@interface SCWebtoonView : NSView
{
    NSArray * pages;                                  /* retained: TSSTPage objects, in reading order */
    TSSTSessionWindowController * sessionController;   /* assign (back reference) */

    CGFloat * pageOffsets;                            /* pageCount + 1 cumulative tops */
    CGFloat * pageAspects;                            /* width / height per page (0 = unknown) */
    BOOL    * pageMeasured;                            /* YES once a real image fixed the aspect */
    NSUInteger pageCount;

    NSCache * imageCache;                              /* NSNumber(index) -> NSImage */
    NSMutableIndexSet * loadingPages;                  /* indices with an in-flight decode */

    CGFloat layoutWidth;                               /* width the current offsets were built for */
    BOOL observingClipView;
    NSInteger reportedPageIndex;                       /* last index pushed to the controller */
}

@property (assign) TSSTSessionWindowController * sessionController;

/* Replaces the page set and rebuilds the strip. pageArray holds TSSTPage. */
- (void)setPages:(NSArray *)pageArray;

/* Recomputes the width-fit layout for the current scroll view width while
   keeping the page that is currently at the top of the viewport pinned. */
- (void)relayoutPreservingAnchor;

/* Scrolls so the top of the given page sits at the top of the viewport. */
- (void)scrollToPageIndex:(NSInteger)index;

/* Index of the page currently occupying the top of the viewport. */
- (NSInteger)currentPageIndex;

@end
