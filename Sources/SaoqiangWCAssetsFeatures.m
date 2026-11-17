//
//  SaoqiangWCAssetsFeatures.m
//

#import "SaoqiangWCAssetsFeatures.h"
#import "SaoqiangWCAssetsCommon.h"
#import "SaoqiangWCAssetsStore.h"
#import <zlib.h>

#pragma mark - SVG 编辑

@implementation SaoqiangWCAssetsSVGEditor

+ (BOOL)validateSVG:(NSData *)svg error:(NSError **)error {
    NSString *s = [[NSString alloc] initWithData:svg encoding:NSUTF8StringEncoding];
    BOOL ok = s.length > 0 &&
              ([s containsString:@"<svg"] || [s containsString:@"<SVG"]) &&
              [s containsString:@">"];
    if (!ok && error) {
        *error = [NSError errorWithDomain:@"SaoqiangWCAssets.SVG" code:1
                                userInfo:@{NSLocalizedDescriptionKey: @"不是有效的 SVG 文本"}];
    }
    return ok;
}

+ (NSData *)recolorSVG:(NSData *)svg from:(NSString *)fromColor to:(NSString *)toColor error:(NSError **)error {
    if (![self validateSVG:svg error:error]) return nil;
    NSMutableString *s = [[NSMutableString alloc] initWithData:svg encoding:NSUTF8StringEncoding];
    // 同时替换 fill 与 stroke 中出现的颜色值（十六进制 / 关键字）
    NSArray *patterns = @[
        @"(fill|stroke)\\s*[:=]\\s*[\"']?(#[0-9a-fA-F]{3,8}|[a-zA-Z]+)[\"']?",
    ];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:patterns.firstObject
                                                                       options:NSRegularExpressionCaseInsensitive
                                                                         error:error];
    if (!re) return nil;
    NSUInteger total = s.length;
    NSArray *matches = [re matchesInString:s options:0 range:NSMakeRange(0, total)];
    NSInteger offset = 0;
    for (NSTextCheckingResult *m in matches) {
        NSRange r = NSMakeRange(m.range.location + offset, m.range.length);
        if (r.location + r.length > s.length) break;
        NSString *full = [s substringWithRange:r];
        if ([full rangeOfString:fromColor options:NSCaseInsensitiveSearch].location != NSNotFound) {
            NSString *replaced = [full stringByReplacingOccurrencesOfString:fromColor
                                                                  withString:toColor
                                                                     options:NSCaseInsensitiveSearch
                                                                       range:NSMakeRange(0, full.length)];
            [s replaceCharactersInRange:r withString:replaced];
            offset += (NSInteger)replaced.length - (NSInteger)full.length;
        }
    }
    return [s dataUsingEncoding:NSUTF8StringEncoding];
}

+ (NSData *)resizeSVG:(NSData *)svg width:(CGFloat)w height:(CGFloat)h error:(NSError **)error {
    if (![self validateSVG:svg error:error]) return nil;
    NSMutableString *s = [[NSMutableString alloc] initWithData:svg encoding:NSUTF8StringEncoding];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"<svg[^>]*>"
                                                                       options:NSRegularExpressionCaseInsensitive
                                                                         error:error];
    if (!re) return nil;
    NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
    if (!m) return nil;
    NSString *tag = [s substringWithRange:m.range];
    NSString *newTag = [tag copy];
    // 替换已有 width / height，否则插入
    NSRegularExpression *wr = [NSRegularExpression regularExpressionWithPattern:@"width\\s*=\\s*[\"'][^\"']*[\"']"
                                                                       options:NSRegularExpressionCaseInsensitive error:nil];
    NSRegularExpression *hr = [NSRegularExpression regularExpressionWithPattern:@"height\\s*=\\s*[\"'][^\"']*[\"']"
                                                                       options:NSRegularExpressionCaseInsensitive error:nil];
    NSString *wv = [NSString stringWithFormat:@"width=\"%.0f\"", w];
    NSString *hv = [NSString stringWithFormat:@"height=\"%.0f\"", h];
    if ([wr firstMatchInString:newTag options:0 range:NSMakeRange(0, newTag.length)]) {
        newTag = [wr stringByReplacingMatchesInString:newTag options:0 range:NSMakeRange(0, newTag.length) withTemplate:wv];
    } else {
        newTag = [newTag stringByReplacingOccurrencesOfString:@"<svg" withString:[NSString stringWithFormat:@"<svg %@", wv]];
    }
    if ([hr firstMatchInString:newTag options:0 range:NSMakeRange(0, newTag.length)]) {
        newTag = [hr stringByReplacingMatchesInString:newTag options:0 range:NSMakeRange(0, newTag.length) withTemplate:hv];
    } else {
        newTag = [newTag stringByReplacingOccurrencesOfString:@"<svg" withString:[NSString stringWithFormat:@"<svg %@", hv]];
    }
    [s replaceCharactersInRange:m.range withString:newTag];
    return [s dataUsingEncoding:NSUTF8StringEncoding];
}

@end

#pragma mark - 主题包

@implementation SaoqiangWCAssetsThemePack

+ (NSURL *)backupRoot {
    NSURL *docs = SaoqiangWCAssetsDocumentsURL();
    return [docs URLByAppendingPathComponent:@"SaoqiangWCAssets/Backups" isDirectory:YES];
}

+ (BOOL)validateThemeFolder:(NSURL *)url errors:(NSArray<NSString *> **)errors {
    NSMutableArray *errs = [NSMutableArray array];
    BOOL isDir = NO;
    [NSFileManager.defaultManager fileExistsAtPath:url.path isDirectory:&isDir];
    if (!isDir) [errs addObject:@"目录不存在"];
    NSArray *required = @[@"theme.plist", @"info.plist"];
    for (NSString *f in required) {
        NSURL *p = [url URLByAppendingPathComponent:f];
        if (![NSFileManager.defaultManager fileExistsAtPath:p.path]) {
            [errs addObject:[NSString stringWithFormat:@"缺少 %@", f]];
        }
    }
    if (errors) *errors = [errs copy];
    return errs.count == 0;
}

+ (NSURL *)backupCurrentThemeAt:(NSURL *)current error:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *root = [self backupRoot];
    if (![fm createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.dateFormat = @"yyyyMMdd_HHmmss";
    NSString *stamp = [fmt stringFromDate:[NSDate date]];
    NSURL *dst = [root URLByAppendingPathComponent:[NSString stringWithFormat:@"theme_%@", stamp] isDirectory:YES];
    if (![fm copyItemAtURL:current toURL:dst error:error]) return nil;
    return dst;
}

+ (BOOL)rollbackFrom:(NSURL *)backup to:(NSURL *)current error:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm fileExistsAtPath:backup.path]) {
        if (error) *error = [NSError errorWithDomain:@"SaoqiangWCAssets" code:2
                                           userInfo:@{NSLocalizedDescriptionKey:@"备份不存在"}];
        return NO;
    }
    if ([fm fileExistsAtPath:current.path] && ![fm removeItemAtURL:current error:error]) return NO;
    return [fm copyItemAtURL:backup toURL:current error:error];
}

+ (NSArray<NSURL *> *)listBackups {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray *items = [fm contentsOfDirectoryAtURL:[self backupRoot]
                       includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    return items ?: @[];
}

@end

#pragma mark - 导出

@implementation SaoqiangWCAssetsExporter

+ (NSURL *)exportRecords:(NSArray<SaoqiangWCAssetsRecord *> *)records
                   toDir:(NSURL *)parent
                   error:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.dateFormat = @"yyyyMMdd_HHmmss";
    NSURL *dir = [parent URLByAppendingPathComponent:[NSString stringWithFormat:@"Export_%@", [fmt stringFromDate:[NSDate date]]] isDirectory:YES];
    if (![fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:error]) return nil;

    NSMutableArray *manifest = [NSMutableArray array];
    NSUInteger i = 0;
    for (SaoqiangWCAssetsRecord *r in records) {
        NSString *fname = [NSString stringWithFormat:@"%03lu_%@", (unsigned long)i++, r.suggestedFileName];
        NSData *payload = r.rawSVG ?: r.bytes ?: r.renderedBytes;
        if (payload.length) [payload writeToURL:[dir URLByAppendingPathComponent:fname] options:NSAtomicWrite error:nil];
        [manifest addObject:@{
            @"file": fname,
            @"name": r.name ?: @"",
            @"source": SaoqiangWCAssetsSourceName(r.source),
            @"sha256": r.sha256 ?: @"",
            @"size": NSStringFromCGSize(r.pointSize),
        }];
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:error];
    [json writeToURL:[dir URLByAppendingPathComponent:@"manifest.json"] options:NSAtomicWrite error:nil];
    NSData *csv = [self csvForRecords:records];
    [csv writeToURL:[dir URLByAppendingPathComponent:@"manifest.csv"] options:NSAtomicWrite error:nil];
    return dir;
}

+ (NSData *)csvForRecords:(NSArray<SaoqiangWCAssetsRecord *> *)records {
    NSMutableString *csv = [NSMutableString stringWithString:@"name,source,extension,size,sha256,bubble,svg,path\n"];
    for (SaoqiangWCAssetsRecord *r in records) {
        NSString *esc = ^NSString *(NSString *s) {
            s = s ?: @"";
            return [s containsString:@","] ? [NSString stringWithFormat:@"\"%@\"", [s stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]] : s;
        }(r.name);
        [csv appendFormat:@"%@,%@,%@,%@,%@,%@,%@,%@\n",
         esc,
         SaoqiangWCAssetsSourceName(r.source),
         r.extension ?: @"",
         NSStringFromCGSize(r.pointSize),
         r.sha256 ?: @"",
         r.bubble ? @"1" : @"0",
         r.svgResource ? @"1" : @"0",
         r.sourcePath ?: @""];
    }
    return [csv dataUsingEncoding:NSUTF8StringEncoding];
}

// 极简 ZIP 写入：仅 stored（无压缩），避免引入第三方库
+ (NSData *)zipDirectory:(NSURL *)dir error:(NSError **)error {
    NSMutableData *out = [NSMutableData data];
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray *files = [fm contentsOfDirectoryAtPath:dir.path error:error];
    if (!files) return nil;

    for (NSString *f in files) {
        NSData *data = [NSData dataWithContentsOfURL:[dir URLByAppendingPathComponent:f]];
        if (!data) continue;
        uint32_t crc = (uint32_t)crc32(0, data.bytes, (uInt)data.length);
        uint32_t offset = (uint32_t)out.length;
        NSString *name = f;
        NSData *nameBytes = [name dataUsingEncoding:NSUTF8StringEncoding];

        // 本地文件头
        NSMutableData *lh = [NSMutableData data];
        uint32_t sig = 0x04034b50, ver = 20, flags = 0, method = 0;
        uint32_t csize = (uint32_t)data.length, usize = (uint32_t)data.length;
        uint16_t nlen = (uint16_t)nameBytes.length, elen = 0;
        [lh appendBytes:&sig length:4]; [lh appendBytes:&ver length:2]; [lh appendBytes:&flags length:2];
        [lh appendBytes:&method length:2];
        uint16_t dosTime = 0, dosDate = 0x5821;
        [lh appendBytes:&dosTime length:2]; [lh appendBytes:&dosDate length:2];
        [lh appendBytes:&crc length:4]; [lh appendBytes:&csize length:4]; [lh appendBytes:&usize length:4];
        [lh appendBytes:&nlen length:2]; [lh appendBytes:&elen length:2];
        [lh appendData:nameBytes]; [lh appendData:data];
        [out appendData:lh];

        [entries addObject:@{@"name": nameBytes, @"crc": @(crc), @"size": @(csize), @"offset": @(offset)}];
    }

    uint32_t centralStart = (uint32_t)out.length;
    for (NSDictionary *e in entries) {
        NSData *nb = e[@"name"];
        uint32_t sig = 0x02014b50, made = 0x031E, ver = 20, flags = 0, method = 0;
        uint16_t nlen = (uint16_t)nb.length, elen = 0, clen = 0, disk = 0, iattr = 0;
        uint32_t eattr = 0, offset = [e[@"offset"] unsignedIntValue];
        uint32_t crc = [e[@"crc"] unsignedIntValue], size = [e[@"size"] unsignedIntValue];
        uint16_t dosTime = 0, dosDate = 0x5821;
        NSMutableData *cd = [NSMutableData data];
        [cd appendBytes:&sig length:4]; [cd appendBytes:&made length:2]; [cd appendBytes:&ver length:2];
        [cd appendBytes:&flags length:2]; [cd appendBytes:&method length:2];
        [cd appendBytes:&dosTime length:2]; [cd appendBytes:&dosDate length:2];
        [cd appendBytes:&crc length:4]; [cd appendBytes:&size length:4]; [cd appendBytes:&size length:4];
        [cd appendBytes:&nlen length:2]; [cd appendBytes:&elen length:2]; [cd appendBytes:&clen length:2];
        [cd appendBytes:&disk length:2]; [cd appendBytes:&iattr length:2]; [cd appendBytes:&eattr length:4];
        [cd appendBytes:&offset length:4]; [cd appendData:nb];
        [out appendData:cd];
    }
    uint32_t centralSize = (uint32_t)out.length - centralStart;
    NSMutableData *eocd = [NSMutableData data];
    uint32_t esig = 0x06054b50; uint16_t disk = 0, cdisk = 0, cnt = (uint16_t)entries.count, total = cnt;
    uint32_t csize = centralSize, coff = centralStart; uint16_t clen = 0;
    [eocd appendBytes:&esig length:4]; [eocd appendBytes:&disk length:2]; [eocd appendBytes:&cdisk length:2];
    [eocd appendBytes:&cnt length:2]; [eocd appendBytes:&total length:2];
    [eocd appendBytes:&csize length:4]; [eocd appendBytes:&coff length:4]; [eocd appendBytes:&clen length:2];
    [out appendData:eocd];
    return [out copy];
}

@end

#pragma mark - 诊断

@implementation SaoqiangWCAssetsDiagnostics

+ (NSString *)report {
    SaoqiangWCAssetsStore *store = [SaoqiangWCAssetsStore shared];
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"SaoqiangWCAssets 诊断报告\n"];
    [s appendFormat:@"会话: %@\n", SaoqiangWCAssetsSharedSessionID()];
    [s appendFormat:@"进程: %@\n", NSProcessInfo.processInfo.processName];
    [s appendFormat:@"系统: %@ %@\n", UIDevice.currentDevice.systemName, UIDevice.currentDevice.systemVersion];
    [s appendFormat:@"捕获开启: %@\n", store.enabled ? @"是" : @"否"];
    [s appendFormat:@"累计捕获: %lu\n", (unsigned long)store.total];
    [s appendFormat:@"去重丢弃: %lu\n", (unsigned long)store.dropped];
    [s appendFormat:@"当前记录: %lu\n", (unsigned long)store.allRecords.count];
    [s appendFormat:@"当前页: %@\n", store.pageKey ?: @"(无)"];
    NSCountedSet *bySource = [NSCountedSet set];
    for (SaoqiangWCAssetsRecord *r in store.allRecords) [bySource addObject:SaoqiangWCAssetsSourceName(r.source)];
    [s appendFormat:@"按来源: %@\n", [bySource.allObjects componentsJoinedByString:@", "]];
    [s appendFormat:@"备份数: %lu\n", (unsigned long)[SaoqiangWCAssetsThemePack listBackups].count];
    return s;
}

@end
