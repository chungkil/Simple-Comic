/*
    SCLibraryWindowController.h

    A browse window listing every work the reader has opened (sourced
    from SCProgressStore), with cover thumbnails, reading progress and
    last-opened date.  Double-click opens a work; Delete or the context
    menu removes it from the library.  Built programmatically (no nib).
 */

#import <Cocoa/Cocoa.h>

@interface SCLibraryWindowController : NSWindowController <NSCollectionViewDataSource, NSCollectionViewDelegate, NSWindowDelegate>
{
    NSCollectionView * collectionView;
    NSArray * workKeys;          /* filtered + sorted, displayed */
    NSArray * allKeys;           /* merged opened + scanned, unfiltered */
    NSTextField * folderLabel;
    NSSearchField * searchField;
    NSPopUpButton * sortPopup;
    NSSlider * sizeSlider;
    NSInteger sortMode;

    /* Continue-reading shelf: a horizontal strip of recently read works. */
    NSCollectionView * continueView;
    NSScrollView * continueScroll;
    NSScrollView * gridScroll;
    NSArray * continueKeys;
    NSTextField * continueLabel;
}

- (void)reload;

@end
