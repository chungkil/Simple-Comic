/*
    SCLibraryWindowController.h

    A browse window listing every work the reader has opened (sourced
    from SCProgressStore), with cover thumbnails, reading progress and
    last-opened date.  Double-click opens a work; Delete or the context
    menu removes it from the library.  Built programmatically (no nib).
 */

#import <Cocoa/Cocoa.h>

@interface SCLibraryWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>
{
    NSTableView * tableView;
    NSArray * workKeys;
}

- (void)reload;

@end
