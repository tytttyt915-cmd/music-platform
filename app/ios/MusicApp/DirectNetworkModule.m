#import "DirectNetworkModule.h"

@interface DirectNetworkModule () <NSURLSessionDelegate>
@end

@implementation DirectNetworkModule

RCT_EXPORT_MODULE();

/**
 * 直接用 NSURLSession 发请求，绕过 RCTNetworking。
 * 支持自签名证书（用于 IP 直连 HTTPS）。
 * 参数：url, method, headers(dict), body(string or nil)
 * resolve: @{ status: number, headers: dict, body: string }
 * reject: code, message
 */
RCT_EXPORT_METHOD(sendRequest:(NSString *)url
                  method:(NSString *)method
                  headers:(NSDictionary *)headers
                  body:(NSString *)body
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  NSURL *nsUrl = [NSURL URLWithString:url];
  if (!nsUrl) {
    reject(@"INVALID_URL", @"URL 格式错误", nil);
    return;
  }

  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:nsUrl];
  request.HTTPMethod = method ?: @"GET";
  request.timeoutInterval = 30;

  for (NSString *key in headers) {
    [request setValue:headers[key] forHTTPHeaderField:key];
  }

  if (body && [body length] > 0) {
    request.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];
  }

  NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
  // 用 delegate 来处理自签名证书的信任
  NSURLSession *session = [NSURLSession sessionWithConfiguration:config
                                                        delegate:self
                                                   delegateQueue:nil];

  // 把 resolver/rejecter 存起来，delegate 回调时用
  // 为简化，用关联对象或直接在 completionHandler 里处理
  // 注意：delegate 方法会在 challenge 时被调用
  NSURLSessionDataTask *task = [session dataTaskWithRequest:request
    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
      if (error) {
        NSString *detail = [NSString stringWithFormat:@"%@ (code=%ld, domain=%@)",
          error.localizedDescription, (long)error.code, error.domain];
        if (error.userInfo[NSUnderlyingErrorKey]) {
          NSError *under = error.userInfo[NSUnderlyingErrorKey];
          detail = [detail stringByAppendingFormat:@" | underlying: %@ (code=%ld)",
            under.localizedDescription, (long)under.code];
        }
        reject(@"NETWORK_ERROR", detail, error);
        return;
      }

      NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
      NSString *bodyStr = @"";
      if (data) {
        bodyStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!bodyStr) bodyStr = @"";
      }

      resolve(@{
        @"status": @([httpResp statusCode]),
        @"headers": [httpResp allHeaderFields] ?: @{},
        @"body": bodyStr,
      });
    }];

  [task resume];
}

#pragma mark - NSURLSessionDelegate

/**
 * 处理服务器信任挑战：接受自签名证书。
 * 仅用于我们自己的服务器 IP（111.230.155.174）。
 */
- (void)URLSession:(NSURLSession *)session
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler
{
  if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
    NSString *host = challenge.protectionSpace.host;
    // 只信任我们自己的服务器 IP
    if ([host isEqualToString:@"111.230.155.174"]) {
      NSURLCredential *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
      completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
      return;
    }
  }
  completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
}

@end
