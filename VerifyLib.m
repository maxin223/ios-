#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <SystemConfiguration/CaptiveNetwork.h>
#import "config.h"

static BOOL isActivated = NO;
static NSString *savedCardCode = nil;
static NSString *deviceID = nil;

static NSString *getDeviceID() {
    if (deviceID) return deviceID;
    NSString *uuid = [[UIDevice currentDevice] identifierForVendor].UUIDString;
    deviceID = [uuid stringByReplacingOccurrencesOfString:@"-" withString:@""];
    return deviceID;
}

static void verifyCardCode(NSString *code, void(^completion)(BOOL success, NSString *message)) {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@check", API_URL]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [request setValue:API_KEY forHTTPHeaderField:@"Authorization"];
    
    NSString *postData = [NSString stringWithFormat:@"card=%@&device=%@&appid=%@", code, getDeviceID(), SOFTWARE_ID];
    request.HTTPBody = [postData dataUsingEncoding:NSUTF8StringEncoding];
    
    NSURLSessionTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                completion(NO, @"网络错误，请检查后台地址");
                return;
            }
            NSDictionary *result = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([result[@"code"] intValue] == 1) {
                completion(YES, @"验证成功");
            } else {
                completion(NO, result[@"msg"] ?: @"验证失败");
            }
        });
    }];
    [task resume];
}

static void startHeartbeat() {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        while (isActivated) {
            sleep(HEARTBEAT_INTERVAL);
            dispatch_async(dispatch_get_main_queue(), ^{
                NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@heartbeat", API_URL]];
                NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
                request.HTTPMethod = @"POST";
                [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
                [request setValue:API_KEY forHTTPHeaderField:@"Authorization"];
                
                NSString *postData = [NSString stringWithFormat:@"card=%@&device=%@&appid=%@", savedCardCode, getDeviceID(), SOFTWARE_ID];
                request.HTTPBody = [postData dataUsingEncoding:NSUTF8StringEncoding];
                
                NSURLSessionTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                    if (error) return;
                    NSDictionary *result = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                    if ([result[@"code"] intValue] != 1) {
                        isActivated = NO;
                        dispatch_async(dispatch_get_main_queue(), ^{
                            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:@"卡密已失效或被强制下线" preferredStyle:UIAlertControllerStyleAlert];
                            [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                                exit(0);
                            }]];
                            UIViewController *topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
                            [topVC presentViewController:alert animated:YES completion:nil];
                        });
                    }
                }];
                [task resume];
            });
        }
    });
}

static void showActivationAlert() {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"软件激活" message:@"请输入你的卡密" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"请输入卡密";
        textField.secureTextEntry = NO;
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        exit(0);
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *code = alert.textFields.firstObject.text;
        if (!code || code.length == 0) {
            showActivationAlert();
            return;
        }
        verifyCardCode(code, ^(BOOL success, NSString *message) {
            if (success) {
                isActivated = YES;
                savedCardCode = code;
                [[NSUserDefaults standardUserDefaults] setObject:code forKey:@"savedCardCode"];
                startHeartbeat();
            } else {
                UIAlertController *failAlert = [UIAlertController alertControllerWithTitle:@"验证失败" message:message preferredStyle:UIAlertControllerStyleAlert];
                [failAlert addAction:[UIAlertAction actionWithTitle:@"重试" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    showActivationAlert();
                }]];
                UIViewController *topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
                [topVC presentViewController:failAlert animated:YES completion:nil];
            }
        });
    }]];
    
    UIViewController *topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    [topVC presentViewController:alert animated:YES completion:nil];
}

__attribute__((constructor)) static void dylib_entry() {
    dispatch_async(dispatch_get_main_queue(), ^{
        savedCardCode = [[NSUserDefaults standardUserDefaults] objectForKey:@"savedCardCode"];
        if (savedCardCode && savedCardCode.length > 0) {
            verifyCardCode(savedCardCode, ^(BOOL success, NSString *message) {
                if (success) {
                    isActivated = YES;
                    startHeartbeat();
                } else {
                    showActivationAlert();
                }
            });
        } else {
            showActivationAlert();
        }
    });
}
@end