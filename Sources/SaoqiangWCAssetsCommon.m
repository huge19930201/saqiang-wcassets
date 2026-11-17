//
//  SaoqiangWCAssetsCommon.m
//

#import "SaoqiangWCAssetsCommon.h"
#import <objc/message.h>

#pragma mark - 会话 / 工具

NSString *SaoqiangWCAssetsSharedSessionID(void) {
    static NSString *sid = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ sid = [NSUUID UUID].UUIDString; });
    return sid;
}

NSString *SaoqiangWCAssetsSourceName(SaoqiangWCAssetsSource source) {
    switch (source) {
        case SaoqiangWCAssetsSourceImageNamed:     return @"imageNamed";
        case SaoqiangWCAssetsSourceContentsOfFile: return @"文件";
        case SaoqiangWCAssetsSourceData:           return @"数据";
        case SaoqiangWCAssetsSourceSVG:            return @"SVG";
        case SaoqiangWCAssetsSourceBubble:         return @"气泡";
        case SaoqiangWCAssetsSourceTheme:          return @"主题";
        case SaoqiangWCAssetsSourcePage:           return @"页面";
        case SaoqiangWCAssetsSourceXML:            return @"XML";
    }
    return @"未知";
}

UIImage *SaoqiangWCAssetsThumbnail(UIImage *image, CGSize size) {
    if (!image) return nil;
    CGSize src = image.size;
    if (src.width <= 0 || src.height <= 0) return nil;
    CGFloat scale = MIN(size.width / src.width, size.height / src.height);
    scale = MIN(scale, 1.0);
    CGSize dst = CGSizeMake(floor(src.width * scale), floor(src.height * scale));
    if (dst.width < 1) dst.width = 1;
    if (dst.height < 1) dst.height = 1;
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.opaque = NO;
    fmt.scale = 1.0;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:dst format:fmt];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [image drawInRect:CGRectMake(0, 0, dst.width, dst.height)];
    }];
}

NSArray<UIImage *> *SaoqiangWCAssetsVisibleImages(UIView *root, NSInteger maxCount) {
    NSMutableArray<UIImage *> *out = [NSMutableArray array];
    if (!root || maxCount <= 0) return out;
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count && out.count < maxCount) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if (v.hidden || v.alpha < 0.05 || CGRectIsEmpty(v.frame)) continue;
        if ([v isKindOfClass:[UIImageView class]]) {
            UIImage *img = ((UIImageView *)v).image;
            if (img) [out addObject:img];
        }
        if ([v isKindOfClass:[UIButton class]]) {
            UIImage *img = [(UIButton *)v imageForState:UIControlStateNormal];
            if (img) [out addObject:img];
        }
        [stack addObjectsFromArray:v.subviews];
    }
    return out;
}

UIViewController *SaoqiangWCAssetsTopController(void) {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]] &&
            scene.activationState == UISceneActivationStateForegroundActive) {
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) { window = w; break; }
            }
            if (!window && ((UIWindowScene *)scene).windows.firstObject) {
                window = ((UIWindowScene *)scene).windows.firstObject;
            }
            break;
        }
    }
    if (!window) window = UIApplication.sharedApplication.keyWindow;
    UIViewController *top = window.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    if ([top isKindOfClass:[UINavigationController class]]) {
        top = ((UINavigationController *)top).visibleViewController ?: top;
    } else if ([top isKindOfClass:[UITabBarController class]]) {
        top = ((UITabBarController *)top).selectedViewController ?: top;
    }
    return top;
}

void SaoqiangWCAssetsToast(NSString *text) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = SaoqiangWCAssetsTopController();
        UIView *host = top.view ?: UIApplication.sharedApplication.keyWindow;
        if (!host) return;
        UILabel *label = [UILabel new];
        label.text = text;
        label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        label.textColor = [UIColor whiteColor];
        label.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.78];
        label.textAlignment = NSTextAlignmentCenter;
        label.numberOfLines = 0;
        label.layer.cornerRadius = 10;
        label.clipsToBounds = YES;
        CGSize max = CGSizeMake(host.bounds.size.width - 60, 160);
        CGRect rect = [text boundingRectWithSize:max
                                         options:NSStringDrawingUsesLineFragmentOrigin
                                      attributes:@{NSFontAttributeName: label.font}
                                         context:nil];
        label.frame = CGRectMake((host.bounds.size.width - (rect.size.width + 32)) / 2,
                                 host.bounds.size.height - 140,
                                 rect.size.width + 32,
                                 rect.size.height + 20);
        [host addSubview:label];
        [UIView animateWithDuration:0.25 delay:1.8 options:UIViewAnimationOptionCurveEaseIn
                         animations:^{ label.alpha = 0; }
                         completion:^(BOOL finished){ [label removeFromSuperview]; }];
    });
}

NSString *SaoqiangWCAssetsSafePath(NSURL *url) {
    if (!url.isFileURL) return nil;
    return url.path;
}

NSURL *SaoqiangWCAssetsDocumentsURL(void) {
    return [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory
                                               inDomains:NSUserDomainMask].firstObject;
}

#pragma mark - Hook 运行时（无 Substrate，直接 method_setImplementation）

typedef NS_ENUM(NSInteger, SQHookEntryKind) { SQHookEntryKindInstance = 0, SQHookEntryKindClass };

@interface SQHookEntry : NSObject
@property (nonatomic, assign) IMP originalIMP;
@property (nonatomic, assign) SQHookEntryKind kind;
@property (nonatomic, assign) Class cls;
@property (nonatomic, assign) SEL sel;
@end
@implementation SQHookEntry
@end

static NSMutableDictionary<NSString *, SQHookEntry *> *SQHooks = nil;
static NSMutableDictionary<NSString *, NSNumber *> *SQGuards = nil;
static NSLock *SQHookLock = nil;
static dispatch_once_t sqHookOnce;

static void SQHookBootstrap(void) {
    dispatch_once(&sqHookOnce, ^{
        SQHooks = [NSMutableDictionary dictionary];
        SQGuards = [NSMutableDictionary dictionary];
        SQHookLock = [NSLock new];
    });
}

IMP SQHook(Class cls, SEL sel, BOOL instanceMethod, IMP replacement, NSString *token) {
    if (!cls || !sel || !replacement || token.length == 0) return NULL;
    SQHookBootstrap();
    [SQHookLock lock];
    IMP result = NULL;
    do {
        SQHookEntry *existing = SQHooks[token];
        if (existing) { result = existing.originalIMP; break; }  // 幂等

        Class target = instanceMethod ? cls : object_getClass(cls);
        Method m = instanceMethod ? class_getInstanceMethod(cls, sel) : class_getClassMethod(cls, sel);
        if (!m) {
            SQWLog(@"跳过 hook：%@ %@ 方法不存在", NSStringFromClass(cls), NSStringFromSelector(sel));
            break;
        }
        const char *types = method_getTypeEncoding(m);
        IMP original = method_getImplementation(m);

        // 若方法来自父类，class_addMethod 就地添加，避免污染父类
        if (class_addMethod(target, sel, replacement, types ?: "v@:")) {
            result = original;
        } else {
            IMP prev = method_setImplementation(m, replacement);
            result = prev ?: original;
        }
        if (!result) {
            SQWLog(@"警告：%@ %@ 未取到原始 IMP", NSStringFromClass(cls), NSStringFromSelector(sel));
            break;
        }

        SQHookEntry *entry = [SQHookEntry new];
        entry.originalIMP = result;
        entry.kind = instanceMethod ? SQHookEntryKindInstance : SQHookEntryKindClass;
        entry.cls = cls;
        entry.sel = sel;
        SQHooks[token] = entry;
    } while (0);
    [SQHookLock unlock];
    return result;
}

IMP SQOriginalIMP(NSString *token) {
    SQHookBootstrap();
    [SQHookLock lock];
    IMP imp = SQHooks[token].originalIMP;
    [SQHookLock unlock];
    return imp;
}

BOOL SQUnhook(NSString *token) {
    SQHookBootstrap();
    [SQHookLock lock];
    SQHookEntry *entry = SQHooks[token];
    BOOL ok = NO;
    if (entry) {
        Class target = entry.kind == SQHookEntryKindInstance ? entry.cls : object_getClass(entry.cls);
        Method m = class_getInstanceMethod(target, entry.sel);
        if (m) { method_setImplementation(m, entry.originalIMP); ok = YES; }
        [SQHooks removeObjectForKey:token];
    }
    [SQHookLock unlock];
    return ok;
}

BOOL SQClassExists(NSString *name) {
    return NSClassFromString(name) != nil;
}

// 用已注册的 selector 作为稳定的关联键（UTF8String 指针随对象释放会悬空）
static const void *SQAssocKey(NSString *key) {
    SEL sel = NSSelectorFromString([@"sq_assoc_" stringByAppendingString:key ?: @""]);
    return (const void *)sel;
}

void SQSetAssoc(id object, NSString *key, id value) {
    if (!object) return;
    objc_setAssociatedObject(object, SQAssocKey(key), value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

id SQGetAssoc(id object, NSString *key) {
    if (!object) return nil;
    return objc_getAssociatedObject(object, SQAssocKey(key));
}

BOOL SQEnterGuard(NSString *key) {
    if (!key) return YES;
    SQHookBootstrap();
    [SQHookLock lock];
    NSInteger depth = SQGuards[key].integerValue;
    BOOL allowed = (depth == 0);
    if (allowed) SQGuards[key] = @1;
    [SQHookLock unlock];
    return allowed;
}

void SQExitGuard(NSString *key) {
    if (!key) return;
    [SQHookLock lock];
    [SQGuards removeObjectForKey:key];
    [SQHookLock unlock];
}

BOOL SQIsGuarded(NSString *key) {
    [SQHookLock lock];
    BOOL g = SQGuards[key] != nil;
    [SQHookLock unlock];
    return g;
}
