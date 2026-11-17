//
//  SaoqiangWCAssetsEntry.h
//  入口：dylib 构造时启动，负责 Hook 安装与悬浮按钮注入
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface SaoqiangWCAssetsEntry : NSObject

/// dylib constructor 调用
+ (void)start;

/// viewDidAppear: Hook 里回调，用于在页面就绪后注入悬浮按钮
+ (void)applicationDidRenderController:(UIViewController *)controller;

/// 显隐主界面
+ (void)togglePanel;
+ (void)showPanel;

@end
