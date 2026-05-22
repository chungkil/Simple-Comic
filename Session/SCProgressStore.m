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


- (NSArray *)allWorkKeys
{
    return [[records allKeys] sortedArrayUsingComparator: ^NSComparisonResult(id a, id b) {
        NSDate * da = [[records objectForKey: a] objectForKey: @"updated"];
        NSDate * db = [[records objectForKey: b] objectForKey: @"updated"];
        if(!da && !db) { return [a compare: b]; }
        if(!da) { return NSOrderedDescending; }
        if(!db) { return NSOrderedAscending; }
        return [db compare: da];
    }];
}


- (void)removeRecordForKey:(NSString *)key
{
    if([key length] && [records objectForKey: key])
    {
        [records removeObjectForKey: key];
        [self synchronize];
    }
}


- (NSString *)statisticsSummary
{
    NSUInteger works = [records count];
    NSUInteger bookmarks = 0;
    NSInteger pages = 0;
    NSUInteger recent7 = 0;
    NSDate * cutoff = [NSDate dateWithTimeIntervalSinceNow: -7 * 24 * 3600];
    NSString * lastName = nil;
    NSDate * lastDate = nil;

    for(NSString * key in records)
    {
        NSDictionary * r = [records objectForKey: key];
        bookmarks += [[r objectForKey: @"bookmarks"] count];
        pages += [[r objectForKey: @"lastPage"] integerValue] + 1;
        NSDate * u = [r objectForKey: @"updated"];
        if(u)
        {
            if([u compare: cutoff] == NSOrderedDescending) recent7++;
            if(!lastDate || [u compare: lastDate] == NSOrderedDescending)
            {
                lastDate = u;
                lastName = [key lastPathComponent];
            }
        }
    }

    NSString * lastLine;
    if(lastName)
    {
        NSDateFormatter * df = [[[NSDateFormatter alloc] init] autorelease];
        [df setDateStyle: NSDateFormatterMediumStyle];
        [df setTimeStyle: NSDateFormatterShortStyle];
        lastLine = [NSString stringWithFormat: @"마지막 읽음: %@ (%@)", lastName, [df stringFromDate: lastDate]];
    }
    else
    {
        lastLine = @"마지막 읽음: 없음";
    }

    return [NSString stringWithFormat:
        @"작품 수: %lu\n도달 페이지 합계: %ld\n북마크: %lu\n최근 7일 읽은 작품: %lu\n%@",
        (unsigned long)works, (long)pages, (unsigned long)bookmarks, (unsigned long)recent7, lastLine];
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
