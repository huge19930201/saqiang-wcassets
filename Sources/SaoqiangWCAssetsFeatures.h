//
//  SaoqiangWCAssetsFeatures.h
//  新增功能：SVG 编辑 / 主题包校验回滚 / 批量 ZIP 导出 / 诊断
//

#import <Foundation/Foundation.h>
#import "SaoqiangWCAssetsRecord.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - SVG 源码编辑

@interface SaoqiangWCAssetsSVGEditor : NSObject
/// 替换 SVG 里的 fill / stroke 颜色（返回新数据，失败返回 nil）
+ (NSData *)recolorSVG:(NSData *)svg from:(NSString *)fromColor to:(NSString *)toColor error:(NSError **)error;
/// 设置 SVG 的 width/height（返回新数据）
+ (NSData *)resizeSVG:(NSData *)svg width:(CGFloat)w height:(CGFloat)h error:(NSError **)error;
/// 基本合法性校验
+ (BOOL)validateSVG:(NSData *)svg error:(NSError **)error;
@end

#pragma mark - 主题包校验 / 备份 / 回滚

@interface SaoqiangWCAssetsThemePack : NSObject
/// 校验目录是否是合法主题包（需含 theme.plist / info.plist）
+ (BOOL)validateThemeFolder:(NSURL *)url errors:(NSArray<NSString *> **)errors;
/// 备份现有主题目录到备份根，返回备份路径
+ (NSURL *)backupCurrentThemeAt:(NSURL *)current error:(NSError **)error;
/// 从备份回滚（先清空 current 再拷贝回来）
+ (BOOL)rollbackFrom:(NSURL *)backup to:(NSURL *)current error:(NSError **)error;
/// 列出所有备份
+ (NSArray<NSURL *> *)listBackups;
+ (NSURL *)backupRoot;
@end

#pragma mark - 批量 ZIP 导出

@interface SaoqiangWCAssetsExporter : NSObject
/// 将记录批量导出到目录（写文件 + manifest.json + CSV），返回导出目录
+ (NSURL *)exportRecords:(NSArray<SaoqiangWCAssetsRecord *> *)records
                   toDir:(NSURL *)parent
                   error:(NSError **)error;
/// 把目录压成 zip（用 system zip 或 NSArchive 兜底；这里用 zlib 自实现在 .m 中）
+ (NSData *)zipDirectory:(NSURL *)dir error:(NSError **)error;
/// CSV 清单
+ (NSData *)csvForRecords:(NSArray<SaoqiangWCAssetsRecord *> *)records;
@end

#pragma mark - 诊断

@interface SaoqiangWCAssetsDiagnostics : NSObject
+ (NSString *)report;
@end

NS_ASSUME_NONNULL_END
