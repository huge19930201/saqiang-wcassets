//
//  SaoqiangWCAssetsHooks.m
//  Hook 安装器：对齐原 dylib 的 SaoqiangWCAssetsHooks.m / Bubbles.m / ThemePack.m / SVG
//
//  说明：原插件用 method_setImplementation + dlsym，不依赖 Substrate。
//  本复刻沿用同一机制；所有 IMP 通过 SQHook() 保存原始实现并用 token 做幂等。
//

#import "SaoqiangWCAssetsHooks.h"
#import "SaoqiangWCAssetsCommon.h"
#import "SaoqiangWCAssetsStore.h"
#import "SaoqiangWCAssetsEntry.h"
#import <objc/message.h>

#pragma mark - 原始 IMP 缓存（函数指针形式，签名与系统方法一致）

typedef UIImage *(*SQImageNamedIMP)(id, SEL, NSString *);
typedef UIImage *(*SQImageFileIMP)(id, SEL, NSString *);
typedef UIImage *(*SQImageInitFileIMP)(id, SEL, NSString *);
typedef UIImage *(*SQImageDataIMP)(id, SEL, NSData *);
typedef UIImage *(*SQImageInitDataIMP)(id, SEL, NSData *);
typedef UIImage *(*SQImageDataScaleIMP)(id, SEL, NSData *, CGFloat);
typedef UIImage *(*SQImageInitDataScaleIMP)(id, SEL, NSData *, CGFloat);
typedef void (*SQVoidIMP)(id, SEL);
typedef id (*SQIdIMP)(id, SEL);
typedef id (*SQIdArgIMP)(id, SEL, id);
typedef id (*SQIdArgArgIMP)(id, SEL, id, id);

static SQImageNamedIMP  sq_orig_imageNamed       = NULL;
static SQImageFileIMP   sq_orig_imageFile        = NULL;
static SQImageInitFileIMP sq_orig_initFile       = NULL;
static SQImageDataIMP   sq_orig_imageData        = NULL;
static SQImageInitDataIMP sq_orig_initData       = NULL;
static SQImageDataScaleIMP sq_orig_imageDataScale = NULL;
static SQImageInitDataScaleIMP sq_orig_initDataScale = NULL;

#pragma mark - 通用捕获入口

static void SQCapture(UIImage *image, NSString *name, SaoqiangWCAssetsSource src,
                      NSString *path, BOOL svg, NSData *raw, NSString *prov) {
    if (!image && raw.length == 0) return;
    // 抑制：捕获流程内若再次触发图片加载（生成缩略图等），直接放行
    if (SQIsGuarded(@"capture")) return;
    SQEnterGuard(@"capture");
    [[SaoqiangWCAssetsStore shared] enqueueImage:image
                                            name:name
                                          source:src
                                            path:path
                                             svg:svg
                                        rawBytes:raw
                                      provenance:prov];
    SQExitGuard(@"capture");
}

#pragma mark - UIImage Hook

static UIImage *SQHook_imageNamed(id self, SEL _cmd, NSString *name) {
    UIImage *img = sq_orig_imageNamed(self, _cmd, name);
    SQCapture(img, name, SaoqiangWCAssetsSourceImageNamed, nil, NO, nil,
              @"+[UIImage imageNamed:]");
    return img;
}

static UIImage *SQHook_imageWithContentsOfFile(id self, SEL _cmd, NSString *path) {
    UIImage *img = sq_orig_imageFile(self, _cmd, path);
    NSData *raw = path.length ? [NSData dataWithContentsOfFile:path] : nil;
    SQCapture(img, path.lastPathComponent, SaoqiangWCAssetsSourceContentsOfFile, path, NO, raw,
              @"+[UIImage imageWithContentsOfFile:]");
    return img;
}

static UIImage *SQHook_initWithContentsOfFile(id self, SEL _cmd, NSString *path) {
    UIImage *img = sq_orig_initFile(self, _cmd, path);
    NSData *raw = path.length ? [NSData dataWithContentsOfFile:path] : nil;
    SQCapture(img, path.lastPathComponent, SaoqiangWCAssetsSourceContentsOfFile, path, NO, raw,
              @"-[UIImage initWithContentsOfFile:]");
    return img;
}

static UIImage *SQHook_imageWithData(id self, SEL _cmd, NSData *data) {
    UIImage *img = sq_orig_imageData(self, _cmd, data);
    SQCapture(img, @"data", SaoqiangWCAssetsSourceData, nil, NO, data,
              @"+[UIImage imageWithData:]");
    return img;
}

static UIImage *SQHook_imageWithDataScale(id self, SEL _cmd, NSData *data, CGFloat scale) {
    UIImage *img = sq_orig_imageDataScale(self, _cmd, data, scale);
    SQCapture(img, @"data@scale", SaoqiangWCAssetsSourceData, nil, NO, data,
              @"+[UIImage imageWithData:scale:]");
    return img;
}

static UIImage *SQHook_initWithData(id self, SEL _cmd, NSData *data) {
    UIImage *img = sq_orig_initData(self, _cmd, data);
    SQCapture(img, @"data", SaoqiangWCAssetsSourceData, nil, NO, data,
              @"-[UIImage initWithData:]");
    return img;
}

static UIImage *SQHook_initWithDataScale(id self, SEL _cmd, NSData *data, CGFloat scale) {
    UIImage *img = sq_orig_initDataScale(self, _cmd, data, scale);
    SQCapture(img, @"data@scale", SaoqiangWCAssetsSourceData, nil, NO, data,
              @"-[UIImage initWithData:scale:]");
    return img;
}

#pragma mark - 聊天气泡 / SVG / 主题（WeChat 内部类，动态检测）

static id SQHook_bubbleGetImage(id self, SEL _cmd, id name) {
    id result = ((SQIdArgIMP)SQOriginalIMP(@"bubble.getImage"))(self, _cmd, name);
    UIImage *img = [result isKindOfClass:[UIImage class]] ? (UIImage *)result : nil;
    SQCapture(img, [name description] ?: @"bubble", SaoqiangWCAssetsSourceBubble, nil, NO, nil,
              @"-[BubbleBoxAssets getImageWithName:]");
    return result;
}

static id SQHook_commonCellBg(id self, SEL _cmd) {
    if (SQIsGuarded(@"bubble")) {
        return ((SQIdIMP)SQOriginalIMP(@"bubble.getBg"))(self, _cmd);
    }
    SQEnterGuard(@"bubble");
    UIView *bg = ((SQIdIMP)SQOriginalIMP(@"bubble.getBg"))(self, _cmd);
    if ([bg isKindOfClass:[UIImageView class]]) {
        UIImage *img = ((UIImageView *)bg).image;
        if (img) {
            SaoqiangWCAssetsRecord *rec = [[SaoqiangWCAssetsStore shared] enqueueImage:img
                                                                                  name:@"bubble.bg"
                                                                                source:SaoqiangWCAssetsSourceBubble
                                                                                  path:nil svg:NO
                                                                              rawBytes:nil
                                                                            provenance:@"-[CommonMessageCellView getBgImageView]"];
            rec.bubble = YES;
        }
    }
    SQExitGuard(@"bubble");
    return bg;
}

// WCSVGImage +imageNamed:fromConfig: —— 捕获 SVG 原始数据
static id SQHook_svgImage(id self, SEL _cmd, id name, id config) {
    id result = ((SQIdArgArgIMP)SQOriginalIMP(@"svg.imageFromConfig"))(self, _cmd, name, config);
    NSString *nm = [name description] ?: @"svg";
    NSString *svgPath = [[NSBundle mainBundle] pathForResource:nm ofType:@"svg"];
    NSData *raw = svgPath.length ? [NSData dataWithContentsOfFile:svgPath] : nil;
    [[SaoqiangWCAssetsStore shared] enqueueSVGData:raw
                                              name:nm
                                            source:SaoqiangWCAssetsSourceSVG
                                       provenance:@"+[WCSVGImage imageNamed:fromConfig:]"];
    return result;
}

// ThemeBoxImageLoader -themeImageNamed: —— 主题资源
static id SQHook_themeImage(id self, SEL _cmd, id name) {
    id result = ((SQIdArgIMP)SQOriginalIMP(@"theme.imageNamed"))(self, _cmd, name);
    UIImage *img = [result isKindOfClass:[UIImage class]] ? (UIImage *)result : nil;
    SaoqiangWCAssetsRecord *rec = [[SaoqiangWCAssetsStore shared] enqueueImage:img
                                                                          name:[name description] ?: @"theme"
                                                                        source:SaoqiangWCAssetsSourceTheme
                                                                          path:nil svg:NO rawBytes:nil
                                                                    provenance:@"-[ThemeBoxImageLoader themeImageNamed:]"];
    rec.themeName = SQGetAssoc(self, @"themeName") ?: @"current";
    return result;
}

#pragma mark - 页面可见资源主动抓取

static void SQHook_viewDidAppear(id self, SEL _cmd) {
    SQVoidIMP orig = (SQVoidIMP)SQOriginalIMP(@"ui.viewDidAppear");
    if (orig) orig(self, _cmd);
    if (![self isKindOfClass:[UIViewController class]]) return;

    // 通知 Entry 注入悬浮按钮（在真正页面出现后）
    [SaoqiangWCAssetsEntry applicationDidRenderController:(UIViewController *)self];

    NSString *key = NSStringFromClass([self class]);
    [[SaoqiangWCAssetsStore shared] beginPage:key];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        UIView *view = ((UIViewController *)self).viewIfLoaded;
        NSArray<UIImage *> *imgs = SaoqiangWCAssetsVisibleImages(view, 40);
        for (UIImage *img in imgs) {
            SQCapture(img, @"visible", SaoqiangWCAssetsSourcePage, nil, NO, nil,
                      @"page capture");
        }
    });
}

#pragma mark - 安装

@implementation SaoqiangWCAssetsHooks

+ (void)installAllHooks {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [self installUIImageHooks];
        [self installWeChatHooks];
        SQWLog(@"Hook 安装完成，enabled=%@", @([SaoqiangWCAssetsStore shared].enabled));
    });
}

+ (void)installUIImageHooks {
    Class uii = [UIImage class];

    sq_orig_imageNamed = (SQImageNamedIMP)SQHook(uii, @selector(imageNamed:), NO,
                                                  (IMP)SQHook_imageNamed, @"ui.imageNamed");
    sq_orig_imageFile = (SQImageFileIMP)SQHook(uii, @selector(imageWithContentsOfFile:), NO,
                                                (IMP)SQHook_imageWithContentsOfFile, @"ui.imageFile");
    sq_orig_initFile = (SQImageInitFileIMP)SQHook(uii, @selector(initWithContentsOfFile:), YES,
                                                   (IMP)SQHook_initWithContentsOfFile, @"ui.initFile");
    sq_orig_imageData = (SQImageDataIMP)SQHook(uii, @selector(imageWithData:), NO,
                                                (IMP)SQHook_imageWithData, @"ui.imageData");
    sq_orig_imageDataScale = (SQImageDataScaleIMP)SQHook(uii, @selector(imageWithData:scale:), NO,
                                                          (IMP)SQHook_imageWithDataScale, @"ui.imageDataScale");
    sq_orig_initData = (SQImageInitDataIMP)SQHook(uii, @selector(initWithData:), YES,
                                                   (IMP)SQHook_initWithData, @"ui.initData");
    sq_orig_initDataScale = (SQImageInitDataScaleIMP)SQHook(uii, @selector(initWithData:scale:), YES,
                                                             (IMP)SQHook_initWithDataScale, @"ui.initDataScale");
}

+ (void)installWeChatHooks {
    // 气泡资源
    Class bubble = NSClassFromString(@"BubbleBoxAssets");
    if (bubble) {
        SQHook(bubble, NSSelectorFromString(@"getImageWithName:"), NO,
               (IMP)SQHook_bubbleGetImage, @"bubble.getImage");
    }
    Class cell = NSClassFromString(@"CommonMessageCellView");
    if (cell) {
        SQHook(cell, NSSelectorFromString(@"getBgImageView"), YES,
               (IMP)SQHook_commonCellBg, @"bubble.getBg");
    }

    // SVG
    Class svg = NSClassFromString(@"WCSVGImage");
    if (svg) {
        SQHook(svg, NSSelectorFromString(@"imageNamed:fromConfig:"), NO,
               (IMP)SQHook_svgImage, @"svg.imageFromConfig");
    }

    // 主题
    Class theme = NSClassFromString(@"ThemeBoxImageLoader");
    if (theme) {
        SQHook(theme, NSSelectorFromString(@"themeImageNamed:"), YES,
               (IMP)SQHook_themeImage, @"theme.imageNamed");
    }

    // 页面 didAppear（在 UIViewController 基类上 hook，覆盖所有页面）
    SQHook([UIViewController class], @selector(viewDidAppear:), YES,
           (IMP)SQHook_viewDidAppear, @"ui.viewDidAppear");
}

+ (void)uninstallAllHooks {
    NSArray *tokens = @[@"ui.imageNamed", @"ui.imageFile", @"ui.initFile", @"ui.imageData",
                        @"ui.imageDataScale", @"ui.initData", @"ui.initDataScale",
                        @"bubble.getImage", @"bubble.getBg", @"svg.imageFromConfig",
                        @"theme.imageNamed", @"ui.viewDidAppear"];
    for (NSString *t in tokens) SQUnhook(t);
}

@end
