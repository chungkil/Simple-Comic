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
@end


@interface SCExposeWindowController : NSWindowController

+ (instancetype)sharedController;

@property (readonly, getter=isShown) BOOL shown;

- (void)showForParentWindow:(NSWindow *)parent delegate:(id <SCExposeViewDelegate>)delegate;
- (void)hide;
- (void)reloadData;

@end
