/*
    SCCoverCache.h

    Cover thumbnails for the library window.  A cover is the first image
    of a work (folder, archive, or single file), scaled down and cached
    both in memory and on disk in Application Support so it survives
    relaunches and is only generated once per work.
 */

#import <Cocoa/Cocoa.h>

/* Posted on the main thread once a cover finishes generating.
   userInfo[@"key"] is the work key that became available. */
extern NSString * SCCoverReadyNotification;

@interface SCCoverCache : NSObject
{
    NSCache * memoryCache;
    NSMutableSet * inFlight;
    NSString * coverDirectory;
    dispatch_semaphore_t throttle;
}

+ (SCCoverCache *)sharedCache;

/* Cached cover if available now, else nil and generation is scheduled
   (SCCoverReadyNotification fires when ready). key identifies the work;
   path is its file-system location. */
- (NSImage *)coverForKey:(NSString *)key path:(NSString *)path;

- (void)removeCoverForKey:(NSString *)key;

@end
