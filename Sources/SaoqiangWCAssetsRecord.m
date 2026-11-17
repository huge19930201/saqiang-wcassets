//
//  SaoqiangWCAssetsRecord.m
//

#import "SaoqiangWCAssetsRecord.h"
#import "SaoqiangWCAssetsCommon.h"
#import <ImageIO/ImageIO.h>
#import <CommonCrypto/CommonDigest.h>

@implementation SaoqiangWCAssetsRecord

+ (BOOL)supportsSecureCoding { return YES; }

- (instancetype)initWithImage:(UIImage *)image
                         name:(NSString *)name
                       source:(SaoqiangWCAssetsSource)source
                         path:(NSString *)path
                          svg:(BOOL)isSVG {
    self = [super init];
    if (self) {
        _identity = [NSUUID UUID].UUIDString;
        _name = name ?: @"(unnamed)";
        _sourcePath = path ?: @"";
        _source = source;
        _bubble = NO;
        _svgResource = isSVG;
        _collectionID = [[NSUUID UUID] UUIDString];
        _sessionID = SaoqiangWCAssetsSharedSessionID();
        _themeName = nil;
        _captureKey = @"";
        _resizingMode = UIImageResizingModeStretch;
        _capInsets = UIEdgeInsetsZero;
        _origin = NSStringFromSelector(_cmd);
        _pixelSize = CGSizeZero;
        _pointSize = CGSizeZero;

        if (image) {
            CGSize pt = image.size;
            CGFloat scale = image.scale > 0 ? image.scale : 1.0;
            _pointSize = pt;
            _pixelSize = CGSizeMake(pt.width * scale, pt.height * scale);
            _resizingMode = image.resizingMode;
            _capInsets = image.capInsets;
            // 缩略图限制在 96pt，避免内存暴涨
            _thumbnail = SaoqiangWCAssetsThumbnail(image, CGSizeMake(96, 96));
            _renderedBytes = UIImagePNGRepresentation(image);
        }

        NSString *ext = [[path lastPathComponent] pathExtension] ?: @"";
        if (isSVG) {
            _kind = SaoqiangWCAssetsKindSVG;
            ext = @"svg";
        } else if ([ext caseInsensitiveCompare:@"jpg"] == NSOrderedSame ||
                   [ext caseInsensitiveCompare:@"jpeg"] == NSOrderedSame) {
            _kind = SaoqiangWCAssetsKindJPEG;
        } else if ([ext caseInsensitiveCompare:@"pdf"] == NSOrderedSame) {
            _kind = SaoqiangWCAssetsKindPDF;
        } else if ([ext caseInsensitiveCompare:@"png"] == NSOrderedSame || ext.length == 0) {
            _kind = SaoqiangWCAssetsKindPNG;
            if (ext.length == 0) ext = @"png";
        } else {
            _kind = SaoqiangWCAssetsKindOther;
        }
        _extension = ext.lowercaseString;

        _metadata = @{
            @"capturedAt": [NSDate date].description,
            @"scale": @(image.scale > 0 ? image.scale : 1.0),
            @"pointSize": NSStringFromCGSize(_pointSize),
            @"pixelSize": NSStringFromCGSize(_pixelSize),
        };
    }
    return self;
}

- (BOOL)refreshHash {
    NSData *data = self.rawSVG ?: self.bytes ?: self.renderedBytes;
    if (!data) return NO;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    NSString *newHash = [hex copy];
    BOOL changed = ![newHash isEqualToString:self.sha256];
    self.sha256 = newHash;
    self.captureKey = newHash;
    return changed;
}

- (NSString *)dedupKey {
    NSString *h = self.sha256 ?: self.captureKey ?: @"";
    if (h.length == 0) {
        return [NSString stringWithFormat:@"%@|%@|%@|%@", @(self.source), self.name, self.sourcePath, self.origin];
    }
    // 内容相同即视为同一份资源；来源只做记录，不做区分
    return h;
}

- (NSString *)detailText {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    [parts addObject:SaoqiangWCAssetsSourceName(self.source)];
    if (self.pointSize.width > 0 || self.pointSize.height > 0) {
        [parts addObject:NSStringFromCGSize(self.pointSize)];
    }
    if (self.extension.length) [parts addObject:self.extension.uppercaseString];
    if (self.themeName.length) [parts addObject:self.themeName];
    if (self.bubble) [parts addObject:@"气泡"];
    if (self.sha256.length) [parts addObject:[self.sha256 substringToIndex:MIN(8, self.sha256.length)]];
    return [parts componentsJoinedByString:@" · "];
}

- (NSString *)suggestedFileName {
    NSString *base = self.name ?: @"asset";
    base = [base stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    base = [base stringByReplacingOccurrencesOfString:@":" withString:@"_"];
    if (base.length > 80) base = [base substringToIndex:80];
    NSString *ext = self.extension.length ? self.extension : @"png";
    return [base stringByAppendingPathExtension:ext];
}

#pragma mark - NSSecureCoding

- (void)encodeWithCoder:(NSCoder *)c {
    [c encodeObject:self.identity forKey:@"identity"];
    [c encodeObject:self.name forKey:@"name"];
    [c encodeObject:self.sourcePath forKey:@"sourcePath"];
    [c encodeInteger:self.source forKey:@"source"];
    [c encodeInteger:self.kind forKey:@"kind"];
    [c encodeObject:self.provenance forKey:@"provenance"];
    [c encodeObject:self.extension forKey:@"extension"];
    [c encodeObject:self.bytes forKey:@"bytes"];
    [c encodeObject:self.renderedBytes forKey:@"renderedBytes"];
    [c encodeObject:self.thumbnail forKey:@"thumbnail"];
    [c encodeInteger:self.resizingMode forKey:@"resizingMode"];
    [c encodeObject:self.origin forKey:@"origin"];
    [c encodeObject:self.collectionID forKey:@"collectionID"];
    [c encodeObject:self.sessionID forKey:@"sessionID"];
    [c encodeObject:self.themeName forKey:@"themeName"];
    [c encodeObject:self.captureKey forKey:@"captureKey"];
    [c encodeCGSize:self.pixelSize forKey:@"pixelSize"];
    [c encodeCGSize:self.pointSize forKey:@"pointSize"];
    [c encodeUIEdgeInsets:self.capInsets forKey:@"capInsets"];
    [c encodeBool:self.bubble forKey:@"bubble"];
    [c encodeBool:self.svgResource forKey:@"svgResource"];
    [c encodeObject:self.rawSVG forKey:@"rawSVG"];
    [c encodeObject:self.sha256 forKey:@"sha256"];
    [c encodeObject:self.metadata forKey:@"metadata"];
}

- (instancetype)initWithCoder:(NSCoder *)c {
    self = [super init];
    if (self) {
        _identity = [c decodeObjectOfClass:[NSString class] forKey:@"identity"];
        _name = [c decodeObjectOfClass:[NSString class] forKey:@"name"];
        _sourcePath = [c decodeObjectOfClass:[NSString class] forKey:@"sourcePath"];
        _source = [c decodeIntegerForKey:@"source"];
        _kind = [c decodeIntegerForKey:@"kind"];
        _provenance = [c decodeObjectOfClass:[NSString class] forKey:@"provenance"];
        _extension = [c decodeObjectOfClass:[NSString class] forKey:@"extension"];
        _bytes = [c decodeObjectOfClass:[NSData class] forKey:@"bytes"];
        _renderedBytes = [c decodeObjectOfClass:[NSData class] forKey:@"renderedBytes"];
        _thumbnail = [c decodeObjectOfClass:[UIImage class] forKey:@"thumbnail"];
        _resizingMode = [c decodeIntegerForKey:@"resizingMode"];
        _origin = [c decodeObjectOfClass:[NSString class] forKey:@"origin"];
        _collectionID = [c decodeObjectOfClass:[NSString class] forKey:@"collectionID"];
        _sessionID = [c decodeObjectOfClass:[NSString class] forKey:@"sessionID"];
        _themeName = [c decodeObjectOfClass:[NSString class] forKey:@"themeName"];
        _captureKey = [c decodeObjectOfClass:[NSString class] forKey:@"captureKey"];
        _pixelSize = [c decodeCGSizeForKey:@"pixelSize"];
        _pointSize = [c decodeCGSizeForKey:@"pointSize"];
        _capInsets = [c decodeUIEdgeInsetsForKey:@"capInsets"];
        _bubble = [c decodeBoolForKey:@"bubble"];
        _svgResource = [c decodeBoolForKey:@"svgResource"];
        _rawSVG = [c decodeObjectOfClass:[NSData class] forKey:@"rawSVG"];
        _sha256 = [c decodeObjectOfClass:[NSString class] forKey:@"sha256"];
        _metadata = [c decodeObjectOfClass:[NSDictionary class] forKey:@"metadata"];
    }
    return self;
}

@end
