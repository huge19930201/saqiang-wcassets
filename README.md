# SaoqiangWCAssets（源码复刻版）

基于对 `SaoqiangWCAssets.dylib`（470,624 字节，ARM64 iOS dylib，filetype=MH_DYLIB，Objective-C）的二进制分析重建的 WeChat 资源发现 / 提取 / 主题 DIY 工具。

> 本项目仅用于个人学习与安全研究。修改第三方 App 运行时可能违反其用户协议，请勿用于非法用途。

---

## 一、原插件逆向结论

| 项目 | 结论 |
| --- | --- |
|  Mach-O  | 64-bit ARM64，`MH_MAGIC_64` / `MH_DYLIB`，未加壳 |
|  标识符  | `@rpath/SaoqiangWCAssets.dylib`，bundle id `com.saoqiang.wcassets.page` / `.theme-diy`，标签 `Saoqiang-WeChat-Assets-2` |
|  依赖  | Foundation / UIKit / ImageIO / CoreGraphics / QuartzCore / CoreFoundation / libobjc / libSystem |
|  注入方式  | **无 CydiaSubstrate / Substitute 依赖**，用 `method_setImplementation` + `dlsym` 直接改 ObjC 运行时，带 UUID 校验（`class/IMP origin or sample UUID mismatch`）防止重复 hook |
|  递归抑制  | 大量 thread-local 深度计数（`SVGScope` / `SourceScope` / `HookDepth` / `BubbleDepth`） |

### 源码文件名（二进制内嵌）
`SaoqiangWCAssetsHooks.m`、`SaoqiangWCAssetsBubbles.m`、`SaoqiangWCAssetsThemePack.m`

### 核心类
`SaoqiangWCAssetsRecord`（资源记录）、`Store`（仓库）、`SVGScope` / `SourceScope`（作用域）、`ImageInfo`、`DataName`、`Backing`、`BubbleLayerImage`、`DIYXML`、`Cell` / `Controller` / `RecordController`（UI）、`Launcher`（悬浮按钮）、`SVGBytes`、`PaddedButton`

### 捕获的 Hook 点
- `UIImage`：`imageNamed:`、`imageWithContentsOfFile:`、`initWithContentsOfFile:`、`imageWithData:`、`initWithData:`（含 `scale:` 变体）
- SVG：`WCSVGImage` 的 `imageNamed:`、`imageNamed:fromConfig:`、`adaptedWeSVGImageWithName:data:config:`；`svgImageNamed:size:color:alpha:` / `:angle:`
- 气泡：`-[CommonMessageCellView getBgImageView]`、`initBgImageView`、`updateBgImageView:`、`-[BubbleBoxAssets getImageWithName:]`
- 主题：`ThemeBoxImageLoader` 的 `themeImageNamed:`、`mapsImageNamed:`、`svgImageNamed:config:`、`imageWithName:`；`backgroundImageOffers`、`headimage`
- 页面：`viewDidAppear:` 抓取当前可见图片；`flutter_assets` / DIY XML 资源

### 原插件功能
悬浮按钮 + 应用内浏览器（列表 / 搜索 / 筛选 / 预览 / 复制名称 / 导出文件）、主题包导入导出（ZIP）、气泡替换、诊断反馈生成。

---

## 二、本复刻版的对应关系

| 原 dylib | 本工程 | 说明 |
| --- | --- | --- |
| `SaoqiangWCAssetsRecord` | `SaoqiangWCAssetsRecord.h/.m` | 同名同 ivar 语义，新增 `sha256` / `metadata` |
| `SaoqiangWCAssetsStore` | `SaoqiangWCAssetsStore.h/.m` | 去重、线程安全、持久化、observer |
| `SaoqiangWCAssetsHooks.m` | `SaoqiangWCAssetsHooks.m` | `UIImage` 全系 hook |
| `SaoqiangWCAssetsBubbles.m` | 同上 `installWeChatHooks` | 气泡 + SVG + 主题 hook |
| `SaoqiangWCAssetsThemePack.m` | `SaoqiangWCAssetsFeatures.m` | 主题校验 / 备份 / 回滚 |
| `SaoqiangWCAssetsController` | `SaoqiangWCAssetsController.m` | 浏览器 UI |
| `SaoqiangWCAssetsLauncher` | `SaoqiangWCAssetsEntry.m` | 悬浮按钮 + constructor 入口 |

## 三、新增功能（原版没有）

1. **SHA-256 内容去重 + 清单**：每条资源计算哈希，导出 `manifest.json` 与 `manifest.csv`。
2. **SVG 源码查看 / 改色 / 改尺寸**：`SaoqiangWCAssetsSVGEditor` 支持替换 `fill` / `stroke` 颜色、改写 `width/height`、合法性校验。
3. **主题包校验 + 一键备份回滚**：导入前校验 `theme.plist` / `info.plist`，自动备份到 `Documents/SaoqiangWCAssets/Backups`，可回滚。
4. **批量导出与 ZIP 打包**：按筛选结果批量导出，内置无依赖的 stored ZIP 写入器（zlib CRC32）。
5. **诊断报告**：捕获统计、来源分布、备份数量。

---

## 四、编译（Mac + Theos）

```bash
# 1. 安装 Theos（若已有跳过）
export THEOS=~/theos

# 2. 进入工程目录
cd SaoqiangWCAssets

# 3. 编译 release dylib
make package DEBUG=0

# 产物在 .theos/obj/SaoqiangWCAssets.dylib
```

工程配置要点：
- `ARCHS = arm64`，`TARGET = 13:0`
- ARC：`-fobjc-arc`
- 框架：Foundation / UIKit / CoreGraphics / QuartzCore / ImageIO / CoreFoundation / UniformTypeIdentifiers
- 库：`libz`（ZIP CRC32）、`libobjc`
- ` Depend ` 为空，**不依赖 mobilesubstrate**

---

## 五、用 TrollStore 注入（非越狱）

1. 获取**解密后的** WeChat IPA（App Store 版本需先脱壳；只能用你自己账号下载的副本）。
2. 把 dylib 放进 IPA：
   ```bash
   # 建 Frameworks 目录
   mkdir -p Payload/WeChat.app/Frameworks
   cp .theos/obj/SaoqiangWCAssets.dylib Payload/WeChat.app/Frameworks/

   # 注入 load command
   insert_dylib --strip-codesig --inplace \
     @executable_path/Frameworks/SaoqiangWCAssets.dylib \
     Payload/WeChat.app/WeChat

   # 用 ldid 签名整个 App（TrollStore 所需 entitlements）
   ldid -Sentitlements.plist Payload/WeChat.app/WeChat
   ```
3. 重新打包 IPA：`zip -qr WeChat_tweaked.ipa Payload`
4. 用 **TrollStore** 安装该 IPA。
5. 打开微信，屏幕上出现可拖动的「资源」悬浮按钮，点击打开浏览器。

> entitlements 见 `entitlements.plist`（含 `get-task-allow`、`platform-application`、`com.apple.private.skip-library-validation`）。

---

## 五之二、GitHub Actions 云端编译（无需本地 Mac）

工程已内置 `.github/workflows/build.yml`，用 GitHub 的 macOS runner + Theos 在云端编译，产出可直接注入的 dylib。

**步骤：**

1. 把本目录推到你的 GitHub 仓库：
   ```bash
   cd SaoqiangWCAssets
   git init
   git add .
   git commit -m "init"
   git remote add origin https://github.com/<你的用户名>/<仓库名>.git
   git branch -M main
   git push -u origin main
   ```
2. 打开仓库 → **Actions** 标签页 → 允许 workflows（首次需要）。`Build SaoqiangWCAssets` 会自动跑起来；也可以在Actions 里点 **Run workflow** 手动触发，或随便 push 一个 commit 触发。
3. 构建完成后，进入该次运行 → 页面底部 **Artifacts** → 下载 `SaoqiangWCAssets-build`。
4. 解压后：
   - `SaoqiangWCAssets.dylib` —— 裸动态库，按上面「第五节」注入微信 IPA 用（TrollStore 走这个）。
   - `com.saoqiang.wcassets.rebuilt_1.0.0.deb` —— deb 包，越狱环境备用。

**workflow 做了什么：**
- `waruhachi/theos-action@v2.6.6`：克隆 Theos + iPhoneOS16.5 SDK，装 `ldid` 和 GNU make，导出 `$THEOS`。
- `brew install dpkg`：让 `make package` 能生成 deb。
- `make clean && make package FINALPACKAGE=1`：编译 release 版 dylib 并打包。
- 收集 `.theos/obj` 里的 dylib 与 `packages/` 里的 deb，作为 artifact 上传（保留 30 天）。

> 注意：GitHub Actions 免费额度里 macOS runner 按分钟数计费（私有仓库有月度免费时长，公开仓库免费）。SDK 与 Theos 会被 action 缓存，后续构建会更快。此环境同样无法真机验证运行时行为，只保证能编译出 dylib。

---

## 六、文件结构

```
SaoqiangWCAssets/
├── Makefile                      Theos 构建配置
├── control                       包元数据
├── SaoqiangWCAssets.plist        微信 bundle filter
├── entitlements.plist            TrollStore 签名权限
├── .github/workflows/build.yml   GitHub Actions 云端编译
├── .gitignore
├── Sources/
│   ├── SaoqiangWCAssetsRecord.h/.m    资源记录模型
│   ├── SaoqiangWCAssetsCommon.h/.m    工具 + Hook 运行时（无 Substrate）
│   ├── SaoqiangWCAssetsStore.h/.m     仓库 / 去重 / 持久化
│   ├── SaoqiangWCAssetsHooks.h/.m     UIImage / SVG / 气泡 / 主题 / 页面 Hook
│   ├── SaoqiangWCAssetsFeatures.h/.m  SVG 编辑 / 主题回滚 / ZIP 导出 / 诊断
│   ├── SaoqiangWCAssetsController.h/.m 浏览器 UI
│   └── SaoqiangWCAssetsEntry.h/.m     入口 + constructor + 悬浮按钮
└── README.md
```

## 七、已知限制

- 这是**源码级重建**，不是字节码级还原；从二进制只能恢复类名 / 方法名 / ivar / 字符串 / hook 点，具体算法按语义重写。
- WeChat 内部类名（`WCSVGImage`、`BubbleBoxAssets`、`CommonMessageCellView`、`ThemeBoxImageLoader`）按版本可能变化，代码用 `NSClassFromString` 动态检测，缺失时自动跳过对应 hook。
- `UIImage` 是类簇，`initWithData:` 等实例方法 hook 对具体子类可能不总是生效；`imageNamed:` 类方法 hook 最稳定。
- ZIP 写入采用 stored（不压缩）方式，文件会比原图大；如需压缩可接入 minizip。
- 当前环境（Windows）无法编译 iOS 代码，本工程未经真机编译验证。请在 Mac + Theos 环境下编译并按需修正编译告警。
