//
//  SaoqiangWCAssetsController.m
//

#import "SaoqiangWCAssetsController.h"
#import "SaoqiangWCAssetsCommon.h"
#import "SaoqiangWCAssetsStore.h"
#import "SaoqiangWCAssetsFeatures.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// CI 使用的 SDK 版本较旧，用运行时选择器兼容 UIColor 的动态颜色 API
static UIColor *SQSystemBackground(void) {
    SEL sel = NSSelectorFromString(@"systemBackground");
    if ([UIColor respondsToSelector:sel]) {
        return [UIColor performSelector:sel];
    }
    return [UIColor whiteColor];
}

static UIColor *SQSecondaryLabel(void) {
    SEL sel = NSSelectorFromString(@"secondaryLabelColor");
    if ([UIColor respondsToSelector:sel]) {
        return [UIColor performSelector:sel];
    }
    return [UIColor darkGrayColor];
}

@interface SaoqiangWCAssetsController () <UISearchResultsUpdating, UIDocumentPickerDelegate>
@property (nonatomic, strong) NSArray<SaoqiangWCAssetsRecord *> *rows;
@property (nonatomic, copy) NSString *keyword;
@property (nonatomic, assign) BOOL bubbleOnly;
@property (nonatomic, strong) UISearchController *search;
@property (nonatomic, strong) UISegmentedControl *filter;
@property (nonatomic, strong) UILabel *summary;
@end

@implementation SaoqiangWCAssetsController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"微信资源";
    self.view.backgroundColor = SQSystemBackground();
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"cell"];
    self.tableView.rowHeight = 66;

    // 搜索
    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchResultsUpdater = self;
    self.navigationItem.searchController = self.search;
    self.definesPresentationContext = YES;

    // 顶部 summary + 过滤
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 96)];
    self.summary = [[UILabel alloc] initWithFrame:CGRectMake(16, 6, header.frame.size.width - 32, 22)];
    self.summary.font = [UIFont systemFontOfSize:12];
    self.summary.textColor = SQSecondaryLabel();
    self.summary.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:self.summary];

    self.filter = [[UISegmentedControl alloc] initWithItems:@[@"全部", @"气泡", @"SVG", @"主题"]];
    self.filter.frame = CGRectMake(16, 34, header.frame.size.width - 32, 32);
    self.filter.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.filter.selectedSegmentIndex = 0;
    [self.filter addTarget:self action:@selector(filterChanged) forControlEvents:UIControlEventValueChanged];
    [header addSubview:self.filter];
    self.tableView.tableHeaderView = header;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"关闭"
        style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(batchExport)],
        [[UIBarButtonItem alloc] initWithTitle:@"工具" style:UIBarButtonItemStylePlain target:self action:@selector(tools)]
    ];

    __weak typeof(self) weakSelf = self;
    [[SaoqiangWCAssetsStore shared] onChange:^{
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf refresh]; });
    } token:@"controller"];
    [self buildToolbar];
    [self refresh];
}

- (void)dealloc {
    [[SaoqiangWCAssetsStore shared] removeObserver:@"controller"];
}

- (void)buildToolbar {
    UIBarButtonItem *toggle = [[UIBarButtonItem alloc] initWithTitle:@"暂停捕获"
        style:UIBarButtonItemStylePlain target:self action:@selector(toggleCapture:)];
    UIBarButtonItem *snap = [[UIBarButtonItem alloc] initWithTitle:@"抓当前页"
        style:UIBarButtonItemStylePlain target:self action:@selector(snapshotPage)];
    UIBarButtonItem *clear = [[UIBarButtonItem alloc] initWithTitle:@"清空"
        style:UIBarButtonItemStylePlain target:self action:@selector(clearAll)];
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    self.toolbarItems = @[toggle, flex, snap, flex, clear];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.toolbarHidden = NO;
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)refresh {
    NSNumber *kind = nil, *source = nil;
    switch (self.filter.selectedSegmentIndex) {
        case 2: kind = @(SaoqiangWCAssetsKindSVG); break;
        case 3: source = @(SaoqiangWCAssetsSourceTheme); break;
        default: break;
    }
    BOOL bubble = (self.filter.selectedSegmentIndex == 1);
    self.rows = [[SaoqiangWCAssetsStore shared] recordsFiltered:self.keyword
                                                           kind:kind source:source bubbleOnly:bubble];
    SaoqiangWCAssetsStore *st = [SaoqiangWCAssetsStore shared];
    self.summary.text = [NSString stringWithFormat:@"共 %lu 条 · 累计 %lu · 去重丢弃 %lu · %@",
                         (unsigned long)self.rows.count, (unsigned long)st.total,
                         (unsigned long)st.dropped, st.enabled ? @"捕获中" : @"已暂停"];
    [self.tableView reloadData];
}

- (void)filterChanged { [self refresh]; }

- (void)toggleCapture:(id)sender {
    SaoqiangWCAssetsStore *st = [SaoqiangWCAssetsStore shared];
    [st setEnabled:!st.enabled];
    [sender setTitle:st.enabled ? @"暂停捕获" : @"恢复捕获"];
    [self refresh];
}

- (void)snapshotPage {
    UIViewController *top = SaoqiangWCAssetsTopController();
    NSArray<UIImage *> *imgs = SaoqiangWCAssetsVisibleImages(top.view, 60);
    for (UIImage *img in imgs) {
        [[SaoqiangWCAssetsStore shared] enqueueImage:img name:@"visible-snapshot"
                                              source:SaoqiangWCAssetsSourcePage path:nil svg:NO
                                           rawBytes:nil provenance:@"manual snapshot"];
    }
    SaoqiangWCAssetsToast([NSString stringWithFormat:@"抓取 %lu 张", (unsigned long)imgs.count]);
}

- (void)clearAll {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"清空所有资源？"
        message:@"此操作不可撤销" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        [[SaoqiangWCAssetsStore shared] clear];
        [self refresh];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - 工具栏：批量导出 / 主题 / 诊断

- (void)batchExport {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"批量导出"
        message:@"把当前列表导出到「文件」App 的 SaoqiangWCAssets 目录"
        preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"导出为文件夹 + CSV" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSError *err = nil;
        NSURL *docs = SaoqiangWCAssetsDocumentsURL();
        NSURL *out = [SaoqiangWCAssetsExporter exportRecords:self.rows toDir:docs error:&err];
        SaoqiangWCAssetsToast(out ? [NSString stringWithFormat:@"已导出到 %@", out.lastPathComponent] : @"导出失败");
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"打包为 ZIP" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSError *err = nil;
        NSURL *docs = SaoqiangWCAssetsDocumentsURL();
        NSURL *dir = [SaoqiangWCAssetsExporter exportRecords:self.rows toDir:docs error:&err];
        NSData *zip = [SaoqiangWCAssetsExporter zipDirectory:dir error:&err];
        NSURL *zurl = [[docs URLByAppendingPathComponent:@"SaoqiangWCAssets"] URLByAppendingPathComponent:@"export.zip"];
        [NSFileManager.defaultManager createDirectoryAtURL:zurl.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        [zip writeToURL:zurl options:NSAtomicWrite error:nil];
        SaoqiangWCAssetsToast(zip ? @"ZIP 已生成" : @"打包失败");
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.firstObject;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)tools {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"工具箱"
        message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"导入主题包（校验 + 备份 + 回滚）" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        UIDocumentPickerViewController *picker = nil;
        if (@available(iOS 14.0, *)) {
            picker = [[UIDocumentPickerViewController alloc]
                initForOpeningContentTypes:@[[UTType typeWithIdentifier:@"public.folder"]] asCopy:YES];
        } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            picker = [[UIDocumentPickerViewController alloc]
                initWithDocumentTypes:@[@"public.folder"] inMode:UIDocumentPickerModeOpen];
#pragma clang diagnostic pop
        }
        picker.delegate = self;
        picker.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:picker animated:YES completion:nil];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"查看诊断报告" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [self showText:[SaoqiangWCAssetsDiagnostics report] title:@"诊断"];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"列出主题备份" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSArray<NSURL *> *backs = [SaoqiangWCAssetsThemePack listBackups];
        NSString *s = backs.count ? [backs componentsJoinedByString:@"\n"] : @"暂无备份";
        [self showText:s title:@"备份"];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.lastObject;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    BOOL accessing = [url startAccessingSecurityScopedResource];
    NSArray<NSString *> *errs = nil;
    BOOL ok = [SaoqiangWCAssetsThemePack validateThemeFolder:url errors:&errs];
    if (!ok) {
        SaoqiangWCAssetsToast([NSString stringWithFormat:@"主题包无效：%@", [errs componentsJoinedByString:@", "]]);
    } else {
        NSURL *current = [SaoqiangWCAssetsDocumentsURL() URLByAppendingPathComponent:@"WeChatTheme"];
        NSError *e = nil;
        NSURL *backup = [SaoqiangWCAssetsThemePack backupCurrentThemeAt:current error:&e];
        if (backup) {
            SaoqiangWCAssetsToast([NSString stringWithFormat:@"已备份到 %@，可随时回滚", backup.lastPathComponent]);
        } else {
            SaoqiangWCAssetsToast([NSString stringWithFormat:@"备份失败：%@", e.localizedDescription]);
        }
    }
    if (accessing) [url stopAccessingSecurityScopedResource];
}

- (void)showText:(NSString *)text title:(NSString *)title {
    UIViewController *vc = [UIViewController new];
    vc.title = title;
    vc.view.backgroundColor = SQSystemBackground();
    UITextView *tv = [[UITextView alloc] initWithFrame:vc.view.bounds];
    tv.text = text;
    tv.font = [UIFont fontWithName:@"Menlo" size:12];
    tv.editable = NO;
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [vc.view addSubview:tv];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - UISearchResultsUpdating

- (void)updateSearchResultsForSearchController:(UISearchController *)sc {
    self.keyword = sc.searchBar.text;
    [self refresh];
}

#pragma mark - Table view

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    SaoqiangWCAssetsRecord *r = self.rows[indexPath.row];
    cell.textLabel.text = r.name;
    cell.detailTextLabel.text = r.detailText;
    if (cell.imageView) {
        UIImage *th = r.thumbnail;
        CGSize side = CGSizeMake(44, 44);
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:side];
        cell.imageView.image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            if (th) {
                CGFloat s = MIN(side.width / th.size.width, side.height / th.size.height);
                [th drawInRect:CGRectMake(0, 0, th.size.width * s, th.size.height * s)];
            }
        }];
    }
    cell.accessoryType = UITableViewCellAccessoryDetailButton;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    SaoqiangWCAssetsRecord *r = self.rows[indexPath.row];
    [self showRecord:r];
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
    [self tableView:tableView didSelectRowAtIndexPath:indexPath];
}

- (void)showRecord:(SaoqiangWCAssetsRecord *)r {
    UIViewController *vc = [UIViewController new];
    vc.title = r.name;
    vc.view.backgroundColor = SQSystemBackground();
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:vc.view.bounds];
    scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UIImageView *iv = [[UIImageView alloc] initWithImage:r.thumbnail ?: [UIImage systemImageNamed:@"photo"]];
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.frame = CGRectMake(0, 20, scroll.bounds.size.width, 260);
    [scroll addSubview:iv];

    UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(16, 300, scroll.bounds.size.width - 32, 200)];
    tv.font = [UIFont fontWithName:@"Menlo" size:12];
    tv.editable = NO;
    NSMutableString *info = [NSMutableString string];
    [info appendFormat:@"来源: %@\n", r.provenance ?: @""];
    [info appendFormat:@"路径: %@\n", r.sourcePath ?: @""];
    [info appendFormat:@"尺寸: pt=%@ px=%@\n", NSStringFromCGSize(r.pointSize), NSStringFromCGSize(r.pixelSize)];
    [info appendFormat:@"SHA256: %@\n", r.sha256 ?: @""];
    if (r.rawSVG.length) {
        [info appendFormat:@"\nSVG 源码:\n%@\n", [[NSString alloc] initWithData:r.rawSVG encoding:NSUTF8StringEncoding] ?: @""];
    }
    tv.text = info;
    [scroll addSubview:tv];
    scroll.contentSize = CGSizeMake(scroll.bounds.size.width, CGRectGetMaxY(tv.frame) + 40);
    [vc.view addSubview:scroll];

    vc.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
        target:self action:@selector(shareRecord:)];
    objc_setAssociatedObject(vc, "sq_record", r, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)shareRecord:(UIBarButtonItem *)item {
    // 通过响应链找到 detail vc 关联的记录
    SaoqiangWCAssetsRecord *r = objc_getAssociatedObject(self.navigationController.topViewController, "sq_record");
    if (!r) return;
    NSData *payload = r.rawSVG ?: r.bytes ?: r.renderedBytes;
    if (!payload) return;
    NSURL *tmp = [NSFileManager.defaultManager.temporaryDirectory URLByAppendingPathComponent:r.suggestedFileName];
    [payload writeToURL:tmp options:NSAtomicWrite error:nil];
    UIActivityViewController *av = [[UIActivityViewController alloc] initWithActivityItems:@[tmp] applicationActivities:nil];
    av.popoverPresentationController.barButtonItem = item;
    [self presentViewController:av animated:YES completion:nil];
}

@end
