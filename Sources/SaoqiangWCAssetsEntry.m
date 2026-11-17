//
//  SaoqiangWCAssetsEntry.m
//

#import "SaoqiangWCAssetsEntry.h"
#import "SaoqiangWCAssetsCommon.h"
#import "SaoqiangWCAssetsHooks.h"
#import "SaoqiangWCAssetsStore.h"
#import "SaoqiangWCAssetsController.h"
#import <objc/message.h>

static UIButton *sqFloatingButton = nil;
static BOOL sqButtonInstalled = NO;

@implementation SaoqiangWCAssetsEntry

+ (void)start {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SQWLog(@"启动，进程=%@", NSProcessInfo.processInfo.processName);
        [SaoqiangWCAssetsHooks installAllHooks];

        // 监听应用启动完成，注入悬浮按钮
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil queue:[NSOperationQueue mainQueue]
                                                     usingBlock:^(NSNotification *n) {
            [self installFloatingButtonIfNeeded];
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self installFloatingButtonIfNeeded];
        });
    });
}

+ (void)applicationDidRenderController:(UIViewController *)controller {
    [self installFloatingButtonIfNeeded];
}

+ (void)installFloatingButtonIfNeeded {
    if (sqButtonInstalled && sqFloatingButton.superview) return;
    UIWindow *win = UIApplication.sharedApplication.keyWindow;
    if (!win) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                win = ((UIWindowScene *)scene).windows.firstObject;
                if (win) break;
            }
        }
    }
    if (!win) return;

    if (!sqFloatingButton) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        CGFloat size = 50;
        b.frame = CGRectMake(win.bounds.size.width - size - 16,
                             win.bounds.size.height * 0.42, size, size);
        b.backgroundColor = [[UIColor alloc] initWithRed:0.12 green:0.55 blue:0.95 alpha:0.92];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        [b setTitle:@"资源" forState:UIControlStateNormal];
        b.layer.cornerRadius = size / 2;
        b.layer.shadowColor = [UIColor blackColor].CGColor;
        b.layer.shadowOpacity = 0.3;
        b.layer.shadowOffset = CGSizeMake(0, 2);
        [b addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                             action:@selector(onPan:)];
        [b addGestureRecognizer:pan];
        sqFloatingButton = b;
    }
    [win addSubview:sqFloatingButton];
    sqButtonInstalled = YES;
}

+ (void)onPan:(UIPanGestureRecognizer *)pan {
    UIView *b = pan.view;
    CGPoint t = [pan translationInView:b.superview];
    CGPoint c = b.center;
    c.x += t.x; c.y += t.y;
    c.x = MAX(35, MIN(c.x, b.superview.bounds.size.width - 35));
    c.y = MAX(60, MIN(c.y, b.superview.bounds.size.height - 60));
    b.center = c;
    [pan setTranslation:CGPointZero inView:b.superview];
}

+ (void)togglePanel {
    UIViewController *top = SaoqiangWCAssetsTopController();
    if ([top.presentedViewController isKindOfClass:[SaoqiangWCAssetsController class]]) {
        [top dismissViewControllerAnimated:YES completion:nil];
    } else {
        [self showPanel];
    }
}

+ (void)showPanel {
    UIViewController *top = SaoqiangWCAssetsTopController();
    if (!top) return;
    SaoqiangWCAssetsController *vc = [[SaoqiangWCAssetsController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 15.0, *)) {
        if (nav.sheetPresentationController) {
            nav.sheetPresentationController.detents = @[
                UISheetPresentationControllerDetent.mediumDetent,
                UISheetPresentationControllerDetent.largeDetent
            ];
            nav.sheetPresentationController.prefersGrabberVisible = YES;
        }
    }
    [top presentViewController:nav animated:YES completion:nil];
}

@end

#pragma mark - dylib constructor（无 Substrate，注入即执行）

__attribute__((constructor)) static void SaoqiangWCAssetsConstructor(void) {
    @autoreleasepool {
        // 延迟到主线程安全点再安装，避免过早触碰 UIKit
        dispatch_async(dispatch_get_main_queue(), ^{
            [SaoqiangWCAssetsEntry start];
        });
    }
}
