/*
    SCCoverCache.m
 */

#import "SCCoverCache.h"
#import "TSSTPage.h"
#import "TSSTManagedGroup.h"
#import <XADMaster/XADArchive.h>

NSString * SCCoverReadyNotification = @"SCCoverReadyNotification";

static const CGFloat SCCoverMaxDimension = 320.0f;


static NSString * SCHashKey(NSString * key)
{
    const char * bytes = [key UTF8String];
    unsigned long long hash = 1469598103934665603ULL;     /* FNV-1a 64 */
    while(bytes && *bytes)
    {
        hash ^= (unsigned char)(*bytes++);
        hash *= 1099511628211ULL;
    }
    return [NSString stringWithFormat: @"%016llx.tiff", hash];
}


@implementation SCCoverCache


+ (SCCoverCache *)sharedCache
{
    static SCCoverCache * shared = nil;
    if(!shared)
    {
        shared = [[SCCoverCache alloc] init];
    }
    return shared;
}


- (id)init
{
    self = [super init];
    if(self)
    {
        memoryCache = [[NSCache alloc] init];
        [memoryCache setCountLimit: 120];
        inFlight = [[NSMutableSet alloc] init];
        throttle = dispatch_semaphore_create(3);

        NSArray * paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
        NSString * base = [paths count] > 0 ? paths[0] : NSTemporaryDirectory();
        coverDirectory = [[[base stringByAppendingPathComponent: @"Simple Comic"]
                           stringByAppendingPathComponent: @"covers"] retain];
        [[NSFileManager defaultManager] createDirectoryAtPath: coverDirectory
                                  withIntermediateDirectories: YES
                                                   attributes: nil
                                                        error: NULL];
    }
    return self;
}


- (void)dealloc
{
    [memoryCache release];
    [inFlight release];
    [coverDirectory release];
    [super dealloc];
}


- (NSString *)diskPathForKey:(NSString *)key
{
    return [coverDirectory stringByAppendingPathComponent: SCHashKey(key)];
}


- (NSImage *)coverForKey:(NSString *)key path:(NSString *)path
{
    if([key length] == 0)
    {
        return nil;
    }

    NSImage * cached = [memoryCache objectForKey: key];
    if(cached)
    {
        return cached;
    }

    NSString * diskPath = [self diskPathForKey: key];
    if([[NSFileManager defaultManager] fileExistsAtPath: diskPath])
    {
        NSImage * fromDisk = [[[NSImage alloc] initWithContentsOfFile: diskPath] autorelease];
        if(fromDisk)
        {
            [memoryCache setObject: fromDisk forKey: key];
            return fromDisk;
        }
    }

    if([inFlight containsObject: key] || [path length] == 0)
    {
        return nil;
    }
    [inFlight addObject: key];

    NSString * keyCopy = [[key copy] autorelease];
    NSString * pathCopy = [[path copy] autorelease];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        dispatch_semaphore_wait(throttle, DISPATCH_TIME_FOREVER);
        NSImage * cover = nil;
        @autoreleasepool
        {
            cover = [[self generateCoverForPath: pathCopy] retain];
            if(cover)
            {
                NSData * tiff = [cover TIFFRepresentation];
                [tiff writeToFile: [self diskPathForKey: keyCopy] atomically: YES];
            }
        }
        dispatch_semaphore_signal(throttle);

        dispatch_async(dispatch_get_main_queue(), ^{
            [inFlight removeObject: keyCopy];
            if(cover)
            {
                [memoryCache setObject: cover forKey: keyCopy];
                [[NSNotificationCenter defaultCenter] postNotificationName: SCCoverReadyNotification
                                                                    object: self
                                                                  userInfo: @{ @"key": keyCopy }];
            }
            [cover release];
        });
    });

    return nil;
}


- (void)removeCoverForKey:(NSString *)key
{
    if([key length] == 0)
    {
        return;
    }
    [memoryCache removeObjectForKey: key];
    [[NSFileManager defaultManager] removeItemAtPath: [self diskPathForKey: key] error: NULL];
}


#pragma mark - Generation (background)


- (BOOL)isImageName:(NSString *)name
{
    NSString * last = [name lastPathComponent];
    if([last hasPrefix: @"."] || [name rangeOfString: @"__MACOSX/"].location != NSNotFound)
    {
        return NO;
    }
    NSString * ext = [[name pathExtension] lowercaseString];
    return [ext length] > 0 && [[TSSTPage imageExtensions] containsObject: ext];
}


- (NSImage *)scaledCover:(NSImage *)source
{
    if(![source isValid])
    {
        return nil;
    }
    NSSize size = [source size];
    if(size.width < 1.0f || size.height < 1.0f)
    {
        return nil;
    }
    CGFloat scale = SCCoverMaxDimension / MAX(size.width, size.height);
    if(scale > 1.0f)
    {
        scale = 1.0f;
    }
    NSSize target = NSMakeSize(round(size.width * scale), round(size.height * scale));
    if(target.width < 1.0f || target.height < 1.0f)
    {
        return nil;
    }

    NSImage * thumb = [[[NSImage alloc] initWithSize: target] autorelease];
    [thumb lockFocus];
    [[NSGraphicsContext currentContext] setImageInterpolation: NSImageInterpolationHigh];
    [source drawInRect: NSMakeRect(0, 0, target.width, target.height)
              fromRect: NSZeroRect
             operation: NSCompositingOperationSourceOver
              fraction: 1.0];
    [thumb unlockFocus];
    return thumb;
}


- (NSImage *)generateCoverForPath:(NSString *)path
{
    NSFileManager * fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if(![fm fileExistsAtPath: path isDirectory: &isDir])
    {
        return nil;
    }

    NSImage * raw = nil;

    if(isDir)
    {
        NSArray * contents = [fm contentsOfDirectoryAtPath: path error: NULL];
        contents = [contents sortedArrayUsingSelector: @selector(localizedStandardCompare:)];
        for(NSString * name in contents)
        {
            if([self isImageName: name])
            {
                raw = [[[NSImage alloc] initWithContentsOfFile:
                        [path stringByAppendingPathComponent: name]] autorelease];
                if([raw isValid])
                {
                    break;
                }
                raw = nil;
            }
        }
    }
    else
    {
        NSString * ext = [[path pathExtension] lowercaseString];
        if([[TSSTManagedArchive archiveExtensions] containsObject: ext])
        {
            XADArchive * archive = [[[XADArchive alloc] initWithFile: path delegate: nil error: NULL] autorelease];
            int count = archive ? [archive numberOfEntries] : 0;
            NSMutableArray * entries = [NSMutableArray array];
            for(int i = 0; i < count; ++i)
            {
                if([archive entryIsDirectory: i])
                {
                    continue;
                }
                NSString * name = [archive nameOfEntry: i];
                if([self isImageName: name])
                {
                    [entries addObject: @{ @"i": @(i), @"name": name }];
                }
            }
            [entries sortUsingComparator: ^NSComparisonResult(id a, id b) {
                return [[a objectForKey: @"name"] localizedStandardCompare: [b objectForKey: @"name"]];
            }];
            if([entries count] > 0)
            {
                int idx = [[[entries objectAtIndex: 0] objectForKey: @"i"] intValue];
                NSData * data = [archive contentsOfEntry: idx];
                if(data)
                {
                    raw = [[[NSImage alloc] initWithData: data] autorelease];
                }
            }
        }
        else
        {
            raw = [[[NSImage alloc] initWithContentsOfFile: path] autorelease];
        }
    }

    return [self scaledCover: raw];
}


@end
