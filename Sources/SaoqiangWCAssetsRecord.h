//
//  SaoqiangWCAssetsRecord.h
//  SaoqiangWCAssets — 复刻版
//
//  资源记录模型：对齐原 dylib 中 SaoqiangWCAssetsRecord 的 ivar 布局。
//  每条记录对应一次被 Hook 捕获的图片 / SVG / 气泡 / 主题资源。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SaoqiangWCAssetsKind) {
    SaoqiangWCAssetsKindPNG = 0,
    SaoqiangWCAssetsKindJPEG,
    SaoqiangWCAssetsKindSVG,
    SaoqiangWCAssetsKindPDF,
    SaoqiangWCAssetsKindOther
};

typedef NS_ENUM(NSInteger, SaoqiangWCAssetsSource) {
    SaoqiangWCAssetsSourceImageNamed = 0,   // +[UIImage imageNamed:]
    SaoqiangWCAssetsSourceContentsOfFile,   // +imageWithContentsOfFile: / -initWithContentsOfFile:
    SaoqiangWCAssetsSourceData,             // +imageWithData: / -initWithData:
    SaoqiangWCAssetsSourceSVG,              // WCSVGImage 族
    SaoqiangWCAssetsSourceBubble,           // 聊天气泡
    SaoqiangWCAssetsSourceTheme,            // 主题 / 地图 / 背景
    SaoqiangWCAssetsSourcePage,             // 页面可见区域主动抓取
    SaoqiangWCAssetsSourceXML               // DIY XML / flutter assets
};

@interface SaoqiangWCAssetsRecord : NSObject <NSSecureCoding>

// —— 对齐原始 ivar ——
@property (nonatomic, copy)   NSString *identity;        // 唯一 id（UUID）
@property (nonatomic, copy)   NSString *name;            // 资源名 / imageNamed 的 key
@property (nonatomic, copy)   NSString *sourcePath;      // 磁盘路径（如有）
@property (nonatomic, assign) SaoqiangWCAssetsSource source;
@property (nonatomic, assign) SaoqiangWCAssetsKind kind;
@property (nonatomic, copy)   NSString *provenance;      // 来源描述（Hook 站点）
@property (nonatomic, copy)   NSString *extension;       // png / jpg / svg ...
@property (nonatomic, strong, nullable) NSData *bytes;          // 原始字节
@property (nonatomic, strong, nullable) NSData *renderedBytes;  // 渲染后 PNG 字节
@property (nonatomic, strong, nullable) UIImage *thumbnail;
@property (nonatomic, assign) UIImageResizingMode resizingMode;
@property (nonatomic, copy, nullable) NSString *origin;         // 原始类名+方法
@property (nonatomic, copy)   NSString *collectionID;    // 会话归组
@property (nonatomic, copy)   NSString *sessionID;
@property (nonatomic, copy, nullable) NSString *themeName;
@property (nonatomic, copy)   NSString *captureKey;      // 去重键（SHA256）
@property (nonatomic, assign) CGSize pixelSize;
@property (nonatomic, assign) CGSize pointSize;
@property (nonatomic, assign) UIEdgeInsets capInsets;
@property (nonatomic, assign) BOOL bubble;
@property (nonatomic, assign) BOOL svgResource;
@property (nonatomic, strong, nullable) id original;     // 原始 UIImage / 对象引用（弱语义另存）
@property (nonatomic, strong, nullable) NSData *rawSVG;

// —— 新增字段 ——
@property (nonatomic, copy, nullable) NSString *sha256;          // 内容哈希（去重 / 清单）
@property (nonatomic, strong, nullable) NSDictionary *metadata;  // 扩展元数据

- (instancetype)initWithImage:(UIImage *)image
                         name:(NSString *)name
                       source:(SaoqiangWCAssetsSource)source
                         path:(nullable NSString *)path
                          svg:(BOOL)isSVG NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)c NS_DESIGNATED_INITIALIZER;

/// 计算内容哈希并写入 sha256 / captureKey。返回是否发生了变化。
- (BOOL)refreshHash;

/// 供浏览器展示的副标题
- (NSString *)detailText;

/// 建议的导出文件名（自动补扩展名）
- (NSString *)suggestedFileName;

/// 用于去重：相同来源 + 相同内容哈希视为同一资源
- (NSString *)dedupKey;

@end

NS_ASSUME_NONNULL_END
