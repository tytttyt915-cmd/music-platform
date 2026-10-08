#import "DirectNetworkModule.h"

@implementation DirectNetworkModule

RCT_EXPORT_MODULE();

/**
 * 直接用 NSURLSession 发请求，绕过 RCTNetworking。
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
  NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

  NSURLSessionDataTask *task = [session dataTaskWithRequest:request
    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
      if (error) {
        // 把底层 NSError 的详细信息传回 JS，这是 RN 的 fetch 不给的东西
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

@end
