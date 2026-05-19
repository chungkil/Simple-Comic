/*
    SCProgressStore.m
 */

#import "SCProgressStore.h"


@implementation SCProgressStore


+ (SCProgressStore *)sharedStore
{
    static SCProgressStore * shared = nil;
    if(!shared)
    {
        shared = [[SCProgressStore alloc] init];
    }
    return shared;
}


- (id)init
{
    self = [super init];
    if(self)
    {
        NSArray * paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
        NSString * base = [paths count] > 0 ? paths[0] : NSTemporaryDirectory();
        NSString * folder = [base stringByAppendingPathComponent: @"Simple Comic"];
        [[NSFileManager defaultManager] createDirectoryAtPath: folder
                                  withIntermediateDirectories: YES
                                                   attributes: nil
                                                        error: NULL];
        storePath = [[folder stringByAppendingPathComponent: @"progress.plist"] retain];

        records = nil;
        NSData * data = [NSData dataWithContentsOfFile: storePath];
        if(data)
        {
            id plist = [NSPropertyListSerialization propertyListWithData: data
                                                                options: NSPropertyListMutableContainers
                                                                 format: NULL
                                                                  error: NULL];
            if([plist isKindOfClass: [NSMutableDictionary class]])
            {
                records = [plist retain];
            }
        }
        if(!records)
        {
            records = [[NSMutableDictionary alloc] init];
        }
    }
    return self;
}


- (void)dealloc
{
    [records release];
    [storePath release];
    [super dealloc];
}


- (void)synchronize
{
    [records writeToFile: storePath atomically: YES];
}


- (NSMutableDictionary *)mutableRecordForKey:(NSString *)key create:(BOOL)create
{
    if([key length] == 0)
    {
        return nil;
    }
    NSMutableDictionary * record = [records objectForKey: key];
    if(!record && create)
    {
        record = [NSMutableDictionary dictionary];
        [records setObject: record forKey: key];
    }
    return record;
}


- (NSDictionary *)recordForKey:(NSString *)key
{
    return [self mutableRecordForKey: key create: NO];
}


- (void)setLastPage:(NSInteger)page
            scrollY:(CGFloat)scrollY
         layoutMode:(NSInteger)layoutMode
             forKey:(NSString *)key
{
    NSMutableDictionary * record = [self mutableRecordForKey: key create: YES];
    if(!record)
    {
        return;
    }
    [record setObject: @(page) forKey: @"lastPage"];
    [record setObject: @(scrollY) forKey: @"scrollY"];
    [record setObject: @(layoutMode) forKey: @"layoutMode"];
    [record setObject: [NSDate date] forKey: @"updated"];
    [self synchronize];
}


- (NSArray *)bookmarksForKey:(NSString *)key
{
    NSArray * marks = [[self mutableRecordForKey: key create: NO] objectForKey: @"bookmarks"];
    return marks ? marks : @[];
}


- (void)addBookmarkName:(NSString *)name page:(NSInteger)page forKey:(NSString *)key
{
    NSMutableDictionary * record = [self mutableRecordForKey: key create: YES];
    if(!record)
    {
        return;
    }
    NSMutableArray * marks = [record objectForKey: @"bookmarks"];
    if(![marks isKindOfClass: [NSMutableArray class]])
    {
        marks = [NSMutableArray array];
        [record setObject: marks forKey: @"bookmarks"];
    }
    [marks addObject: @{ @"name": name ? name : @"", @"page": @(page) }];
    [self synchronize];
}


- (void)removeAllBookmarksForKey:(NSString *)key
{
    NSMutableDictionary * record = [self mutableRecordForKey: key create: NO];
    if(record)
    {
        [record removeObjectForKey: @"bookmarks"];
        [self synchronize];
    }
}


- (void)removeBookmarkAtIndex:(NSInteger)index forKey:(NSString *)key
{
    NSMutableArray * marks = [[self mutableRecordForKey: key create: NO] objectForKey: @"bookmarks"];
    if([marks isKindOfClass: [NSMutableArray class]] && index >= 0 && index < (NSInteger)[marks count])
    {
        [marks removeObjectAtIndex: index];
        [self synchronize];
    }
}


- (void)renameBookmarkAtIndex:(NSInteger)index toName:(NSString *)name forKey:(NSString *)key
{
    if([name length] == 0)
    {
        return;
    }
    NSMutableArray * marks = [[self mutableRecordForKey: key create: NO] objectForKey: @"bookmarks"];
    if([marks isKindOfClass: [NSMutableArray class]] && index >= 0 && index < (NSInteger)[marks count])
    {
        NSDictionary * old = [marks objectAtIndex: index];
        [marks replaceObjectAtIndex: index
                         withObject: @{ @"name": name, @"page": [old objectForKey: @"page"] }];
        [self synchronize];
    }
}


@end
