//
//  SaoqiangWCAssetsCommon.h
//  公共工具 / Hook 运行时基础设施
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "SaoqiangWCAssetsRecord.h"

NS_ASSUME_NONNULL_BEGIN

#define SQWLog(fmt, ...) NSLog(@"[SaoqiangWCAssets] " fmt, ##__VA_ARGS__)

/// 本次进程生命周期的会话 id
NSString *SaoqiangWCAssetsSharedSessionID(void);

NSString *SaoqiangWCAssetsSourceName(SaoqiangWCAssetsSource source);

/// 生成缩略图（不超出 givenSize，保持比例）
UIImage * _Nullable SaoqiangWCAssetsThumbnail(UIImage *image, CGSize size);

/// 从 UIView 层级里抓取可见 UIImageView 的 image
NSArray<UIImage *> *SaoqiangWCAssetsVisibleImages(UIView *root, NSInteger maxCount);

/// 顶层 view controller
UIViewController * _Nullable SaoqiangWCAssetsTopController(void);

/// 轻量 toast（居中黑底提示）
void SaoqiangWCAssetsToast(NSString *text);

/// 把 file URL 转成安全路径
NSString * _Nullable SaoqiangWCAssetsSafePath(NSURL *url);

/// 文档目录（用于导出 / 主题备份）
NSURL *SaoqiangWCAssetsDocumentsURL(void);

#pragma mark - Hook 运行时（无 Substrate）

/// 用 method_setImplementation 替换实现，返回原始 IMP（可能为 NULL）。
/// instanceOrClass YES 表示替换实例方法，NO 表示类方法。
/// 使用 token 做幂等：同一 token 重复 hook 会跳过并复用原始 IMP。
IMP _Nullable SQHook(Class cls,
                     SEL sel,
                     BOOL instanceMethod,
                     IMP replacement,
                     NSString *token);

/// 取回某 token 保存的原始 IMP
IMP _Nullable SQOriginalIMP(NSString *token);

/// 恢复某 token 对应的方法原始实现
BOOL SQUnhook(NSString *token);

/// 判断某个类是否存在（WeChat 内部类名保护）
BOOL SQClassExists(NSString *name);

/// 关联对象读写（带前缀 key，避免污染宿主）
void SQSetAssoc(id object, NSString *key, id _Nullable value);
id _Nullable SQGetAssoc(id object, NSString *key);

/// 线程递归抑制：进入时 YES，离开时自动 NO。用于防止 hook 自己调用自己。
BOOL SQEnterGuard(NSString *key);
void SQExitGuard(NSString *key);
BOOL SQIsGuarded(NSString *key);

NS_ASSUME_NONNULL_END
