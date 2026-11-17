//
//  SaoqiangWCAssetsStore.h
//  资源仓库：对齐原 SaoqiangWCAssetsStore
//

#import <Foundation/Foundation.h>
#import "SaoqiangWCAssetsRecord.h"

NS_ASSUME_NONNULL_BEGIN

@interface SaoqiangWCAssetsStore : NSObject

@property (class, readonly, strong) SaoqiangWCAssetsStore *shared;

@property (nonatomic, assign, readonly) BOOL enabled;         // 捕获开关
@property (nonatomic, assign, readonly) NSUInteger total;     // 累计捕获
@property (nonatomic, assign, readonly) NSUInteger dropped;   // 去重丢弃数
@property (nonatomic, assign, readonly) NSUInteger active;    // 当前页活跃数
@property (nonatomic, copy, nullable) NSString *pageKey;      // 当前页面标识

/// 入队一条资源。返回 nil 表示被禁用 / 去重丢弃；否则返回记录。
- (SaoqiangWCAssetsRecord *)enqueueImage:(nullable UIImage *)image
                                    name:(NSString *)name
                                  source:(SaoqiangWCAssetsSource)source
                                    path:(nullable NSString *)path
                                     svg:(BOOL)isSVG
                                rawBytes:(nullable NSData *)raw
                                 provenance:(nullable NSString *)provenance;

/// 入队原始 SVG 数据（无 UIImage 重编码）
- (SaoqiangWCAssetsRecord *)enqueueSVGData:(NSData *)data
                                       name:(NSString *)name
                                     source:(SaoqiangWCAssetsSource)source
                                provenance:(nullable NSString *)provenance;

- (void)setEnabled:(BOOL)enabled;
- (void)setPageKey:(nullable NSString *)pageKey;
- (void)clear;                                  // 清空全部记录
- (void)beginPage:(NSString *)pageKey;          // 切换页面（重置 active）

- (NSArray<SaoqiangWCAssetsRecord *> *)allRecords;
- (NSArray<SaoqiangWCAssetsRecord *> *)recordsFiltered:(nullable NSString *)keyword
                                                  kind:(nullable NSNumber *)kind
                                                source:(nullable NSNumber *)source
                                               bubbleOnly:(BOOL)bubbleOnly;

/// 持久化到磁盘（JSON 清单 + 二进制归档）
- (BOOL)saveToDirectory:(NSURL *)dir error:(NSError **)error;
- (BOOL)loadFromDirectory:(NSURL *)dir error:(NSError **)error;

/// 注册外部变更回调（每 0.25s 合并一次，回到主线程）
- (void)onChange:(void (^)(void))block token:(NSString *)token;
- (void)removeObserver:(NSString *)token;

@end

NS_ASSUME_NONNULL_END
