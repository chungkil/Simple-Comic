//
//  SCExposeWindowController.h
//  Simple Comic
//
//  Modern NSCollectionView-based thumbnail Exposé.  Replaces the legacy
//  TSSTThumbnailView path which no longer renders on current macOS
//  because its background thumbnail generation relied on -lockFocus
//  and Core Data writes off-main.
//

#import <Cocoa/Cocoa.h>

@class SCExposeWindowController;

@protocol SCExposeViewDelegate <NSObject>
- (NSInteger)pageCountForExposeView:(SCExposeWindowController *)c;
- (NSImage *)exposeView:(SCExposeWindowController *)c thumbnailForPageAtIndex:(NSInteger)i;
- (NSImage *)exposeView:(SCExposeWindowController *)c fullImageForPageAtIndex:(NSInteger)i;
- (NSString *)exposeView:(SCExposeWindowController *)c nameForPageAtIndex:(NSInteger)i;
- (NSInteger)currentPageIndexForExposeView:(SCExposeWindowController *)c;
- (void)exposeView:(SCExposeWindowController *)c didSelectPageAtIndex:(NSInteger)i;
- (void)exposeView:(SCExposeWindowController *)c didMovePageFromIndex:(NSInteger)from toIndex:(NSInteger)to;
@optional
/* Queue the pages at the given indexes for deletion.  The delegate
   removes them from its page list; the Expose view reloads after. */
- (void)exposeView:(SCExposeWindowController *)c didRequestDeletePagesAtIndexes:(NSIndexSet *)indexes;
/* Indexes of pages the user has already marked (e.g. with 's' in the paged
   view).  The Exposé pre-selects these on open and after every reload, so a
   selection survives switching between thumbnail and single-view modes. */
- (NSIndexSet *)markedPageIndexesForExposeView:(SCExposeWindowController *)c;
/* Sent when the user changes the grid selection with a modifier (Cmd/Shift)
   so the delegate's shared marked set stays in sync. */
- (void)exposeView:(SCExposeWindowController *)c didChangeMarkedSelection:(NSIndexSet *)indexes;
@end


@interface SCExposeWindowController : NSWindowController

+ (instancetype)sharedController;

@property (readonly, getter=isShown) BOOL shown;

- (void)showForParentWindow:(NSWindow *)parent delegate:(id <SCExposeViewDelegate>)delegate;
- (void)hide;
- (void)reloadData;

@end
