//
//  SaoqiangWCAssetsStore.m
//

#import "SaoqiangWCAssetsStore.h"
#import "SaoqiangWCAssetsCommon.h"

@interface SaoqiangWCAssetsStore ()
@property (nonatomic, strong) NSMutableArray<SaoqiangWCAssetsRecord *> *records;
@property (nonatomic, strong) NSMutableSet<NSString *> *seen;
@property (nonatomic, strong) NSLock *lock;
@property (nonatomic, strong) NSMutableDictionary<NSString *, void (^)(void)> *observers;
@property (nonatomic, strong) dispatch_source_t debounceTimer;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) NSUInteger total;
@property (nonatomic, assign) NSUInteger dropped;
@property (nonatomic, assign) NSUInteger active;
@property (nonatomic, copy) NSString *pageKey;
@end

@implementation SaoqiangWCAssetsStore

+ (instancetype)shared {
    static SaoqiangWCAssetsStore *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[self alloc] initShared];
    });
    return s;
}

- (instancetype)initShared {
    self = [super init];
    if (self) {
        _records = [NSMutableArray array];
        _seen = [NSMutableSet set];
        _lock = [NSLock new];
        _observers = [NSMutableDictionary dictionary];
        _enabled = YES;  // 默认开启捕获，与"安装即抓取"行为一致
        _total = 0;
        _dropped = 0;
        _active = 0;
    }
    return self;
}

#pragma mark - 通知合并

- (void)scheduleNotify {
    // debounce 避免 Hook 高频触发时狂刷 UI
    if (!self.debounceTimer) {
        self.debounceTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                                    dispatch_get_main_queue());
        __weak typeof(self) weakSelf = self;
        dispatch_source_set_event_handler(self.debounceTimer, ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            dispatch_source_cancel(self.debounceTimer);
            self.debounceTimer = nil;
            [self.lock lock];
            NSArray *blocks = [self.observers.allValues copy];
            [self.lock unlock];
            for (void (^b)(void) in blocks) b();
        });
        dispatch_resume(self.debounceTimer);
    }
    dispatch_time_t t = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC));
    dispatch_source_set_timer(self.debounceTimer, t, DISPATCH_TIME_FOREVER, 0);
}

- (void)onChange:(void (^)(void))block token:(NSString *)token {
    if (!block || token.length == 0) return;
    [self.lock lock];
    self.observers[token] = [block copy];
    [self.lock unlock];
}

- (void)removeObserver:(NSString *)token {
    if (!token) return;
    [self.lock lock];
    [self.observers removeObjectForKey:token];
    [self.lock unlock];
}

#pragma mark - 入队

- (SaoqiangWCAssetsRecord *)enqueueImage:(UIImage *)image
                                    name:(NSString *)name
                                  source:(SaoqiangWCAssetsSource)source
                                    path:(NSString *)path
                                     svg:(BOOL)isSVG
                                rawBytes:(NSData *)raw
                              provenance:(NSString *)provenance {
    if (!self.enabled) return nil;
    if (!image && raw.length == 0) return nil;

    SaoqiangWCAssetsRecord *rec = [[SaoqiangWCAssetsRecord alloc] initWithImage:image
                                                                           name:name
                                                                         source:source
                                                                           path:path
                                                                            svg:isSVG];
    if (raw.length) rec.bytes = raw;
    rec.provenance = provenance ?: @"";
    if (self.pageKey) {
        NSMutableDictionary *meta = [rec.metadata mutableCopy] ?: [NSMutableDictionary dictionary];
        meta[@"pageKey"] = self.pageKey;
        rec.metadata = meta;
    }
    [rec refreshHash];

    [self.lock lock];
    NSString *key = rec.dedupKey;
    if ([self.seen containsObject:key]) {
        self.dropped++;
        [self.lock unlock];
        return nil;
    }
    [self.seen addObject:key];
    [self.records addObject:rec];
    self.total++;
    self.active++;
    // 限制内存：最多保留 800 条
    if (self.records.count > 800) {
        [self.records removeObjectsInRange:NSMakeRange(0, self.records.count - 800)];
    }
    [self.lock unlock];

    [self scheduleNotify];
    return rec;
}

- (SaoqiangWCAssetsRecord *)enqueueSVGData:(NSData *)data
                                       name:(NSString *)name
                                     source:(SaoqiangWCAssetsSource)source
                                provenance:(NSString *)provenance {
    if (!self.enabled || data.length == 0) return nil;
    SaoqiangWCAssetsRecord *rec = [self enqueueImage:nil
                                                name:name
                                              source:source
                                                path:nil
                                                 svg:YES
                                            rawBytes:data
                                          provenance:provenance];
    if (rec) rec.rawSVG = data;
    return rec;
}

#pragma mark - 控制

- (void)setEnabled:(BOOL)enabled {
    [self.lock lock];
    _enabled = enabled;
    [self.lock unlock];
    [self scheduleNotify];
}

- (void)setPageKey:(NSString *)pageKey {
    [self.lock lock];
    _pageKey = [pageKey copy];
    [self.lock unlock];
}

- (void)beginPage:(NSString *)pageKey {
    [self.lock lock];
    _pageKey = [pageKey copy];
    _active = 0;
    [self.lock unlock];
}

- (void)clear {
    [self.lock lock];
    [self.records removeAllObjects];
    [self.seen removeAllObjects];
    _total = 0;
    _dropped = 0;
    _active = 0;
    [self.lock unlock];
    [self scheduleNotify];
}

#pragma mark - 查询

- (NSArray<SaoqiangWCAssetsRecord *> *)allRecords {
    [self.lock lock];
    NSArray *copy = [self.records copy];
    [self.lock unlock];
    return copy;
}

- (NSArray<SaoqiangWCAssetsRecord *> *)recordsFiltered:(NSString *)keyword
                                                  kind:(NSNumber *)kind
                                                source:(NSNumber *)source
                                           bubbleOnly:(BOOL)bubbleOnly {
    [self.lock lock];
    NSArray *snapshot = [self.records copy];
    [self.lock unlock];

    NSMutableArray *out = [NSMutableArray array];
    for (SaoqiangWCAssetsRecord *r in snapshot) {
        if (bubbleOnly && !r.bubble) continue;
        if (kind && r.kind != kind.integerValue) continue;
        if (source && r.source != source.integerValue) continue;
        if (keyword.length) {
            NSString *hay = [NSString stringWithFormat:@"%@ %@ %@ %@", r.name, r.sourcePath, r.themeName ?: @"", r.sha256 ?: @""];
            if ([hay rangeOfString:keyword options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
        }
        [out addObject:r];
    }
    return out;
}

#pragma mark - 持久化

- (BOOL)saveToDirectory:(NSURL *)dir error:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:error]) return NO;

    [self.lock lock];
    NSArray *snapshot = [self.records copy];
    [self.lock unlock];

    NSMutableArray *manifest = [NSMutableArray array];
    NSUInteger idx = 0;
    for (SaoqiangWCAssetsRecord *r in snapshot) {
        NSString *fname = [NSString stringWithFormat:@"%03lu_%@", (unsigned long)idx++, r.suggestedFileName];
        NSData *payload = r.rawSVG ?: r.bytes ?: r.renderedBytes;
        if (payload.length) {
            NSURL *furl = [dir URLByAppendingPathComponent:fname];
            [payload writeToURL:furl options:NSAtomicWrite error:nil];
        }
        [manifest addObject:@{
            @"identity": r.identity ?: @"",
            @"name": r.name ?: @"",
            @"file": fname,
            @"source": @(r.source),
            @"sourceName": SaoqiangWCAssetsSourceName(r.source),
            @"kind": @(r.kind),
            @"extension": r.extension ?: @"",
            @"pointSize": NSStringFromCGSize(r.pointSize),
            @"pixelSize": NSStringFromCGSize(r.pixelSize),
            @"sha256": r.sha256 ?: @"",
            @"bubble": @(r.bubble),
            @"svg": @(r.svgResource),
            @"theme": r.themeName ?: @"",
            @"path": r.sourcePath ?: @"",
            @"provenance": r.provenance ?: @"",
        }];
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject:manifest
                                                   options:NSJSONWritingPrettyPrinted error:error];
    if (!json) return NO;
    return [json writeToURL:[dir URLByAppendingPathComponent:@"manifest.json"]
                    options:NSAtomicWrite error:error];
}

- (BOOL)loadFromDirectory:(NSURL *)dir error:(NSError **)error {
    NSData *json = [NSData dataWithContentsOfURL:[dir URLByAppendingPathComponent:@"manifest.json"]];
    if (!json) {
        if (error) *error = [NSError errorWithDomain:@"SaoqiangWCAssets" code:404 userInfo:@{NSLocalizedDescriptionKey: @"manifest.json 不存在"}];
        return NO;
    }
    NSArray *items = [NSJSONSerialization JSONObjectWithData:json options:0 error:error];
    if (![items isKindOfClass:[NSArray class]]) return NO;

    [self.lock lock];
    [self.records removeAllObjects];
    [self.seen removeAllObjects];
    [self.lock unlock];

    for (NSDictionary *d in items) {
        NSData *payload = [NSData dataWithContentsOfURL:[dir URLByAppendingPathComponent:d[@"file"] ?: @""]];
        BOOL isSVG = [d[@"svg"] boolValue];
        UIImage *img = isSVG ? nil : [UIImage imageWithData:payload];
        SaoqiangWCAssetsRecord *r = [[SaoqiangWCAssetsRecord alloc] initWithImage:img
                                                                             name:d[@"name"] ?: @""
                                                                           source:[d[@"source"] integerValue]
                                                                             path:d[@"path"]
                                                                              svg:isSVG];
        r.sha256 = d[@"sha256"] ?: @"";
        r.bubble = [d[@"bubble"] boolValue];
        r.themeName = d[@"theme"];
        r.provenance = d[@"provenance"] ?: @"";
        if (isSVG) r.rawSVG = payload; else r.bytes = payload;
        [self.lock lock];
        [self.records addObject:r];
        if (r.sha256.length) [self.seen addObject:r.sha256];
        [self.lock unlock];
    }
    [self scheduleNotify];
    return YES;
}

@end
