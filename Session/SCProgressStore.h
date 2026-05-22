/*
    SCProgressStore.h

    Per-work reading state that must survive closing a work (the Core Data
    session is deleted on close, so it cannot hold this).  Keyed by the
    work's top-level file path and persisted as a property list in
    Application Support.  Stores the last viewed page, the webtoon scroll
    offset, the per-work layout mode, and any named bookmarks.
 */

#import <Foundation/Foundation.h>

@interface SCProgressStore : NSObject
{
    NSMutableDictionary * records;   /* workKey -> mutable record dict */
    NSString * storePath;
}

+ (SCProgressStore *)sharedStore;

/* Immutable snapshot of a work's record, or nil if none. Keys:
   @"lastPage" (NSNumber), @"scrollY" (NSNumber), @"layoutMode" (NSNumber),
   @"bookmarks" (NSArray of @{ @"name": NSString, @"page": NSNumber }). */
- (NSDictionary *)recordForKey:(NSString *)key;

- (void)setLastPage:(NSInteger)page
            scrollY:(CGFloat)scrollY
         layoutMode:(NSInteger)layoutMode
             forKey:(NSString *)key;

/* Array of @{ @"name": NSString, @"page": NSNumber }, insertion order. */
- (NSArray *)bookmarksForKey:(NSString *)key;
- (void)addBookmarkName:(NSString *)name page:(NSInteger)page forKey:(NSString *)key;
- (void)removeAllBookmarksForKey:(NSString *)key;
- (void)removeBookmarkAtIndex:(NSInteger)index forKey:(NSString *)key;
- (void)renameBookmarkAtIndex:(NSInteger)index toName:(NSString *)name forKey:(NSString *)key;

/* All known work keys, most-recently-updated first (for the library). */
- (NSArray *)allWorkKeys;
- (void)removeRecordForKey:(NSString *)key;

/* Human-readable multi-line reading statistics. */
- (NSString *)statisticsSummary;

@end
