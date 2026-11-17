//
//  SaoqiangWCAssetsHooks.h
//

#import <Foundation/Foundation.h>

@interface SaoqiangWCAssetsHooks : NSObject
+ (void)installAllHooks;
+ (void)installUIImageHooks;
+ (void)installWeChatHooks;
+ (void)uninstallAllHooks;
@end
