#import "DirectNetworkModule.h"

@interface DirectNetworkModule () <NSURLSessionDelegate>
@property (nonatomic, strong) NSMutableSet<NSURLSession *> *activeSessions;
@end

@implementation DirectNetworkModule

RCT_EXPORT_MODULE();

- (instancetype)init {
  if (self = [super init]) {
    _activeSessions = [NSMutableSet set];
  }
  return self;
}

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
  // 必须强引用 session，否则方法返回后 session 被释放，delegate 收不到 challenge
  NSURLSession *session = [NSURLSession sessionWithConfiguration:config
                                                        delegate:self
                                                   delegateQueue:nil];
  @synchronized (self.activeSessions) {
    [self.activeSessions addObject:session];
  }

  NSURLSessionDataTask *task = [session dataTaskWithRequest:request
    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
      // 请求完成，释放 session
      @synchronized (self.activeSessions) {
        [self.activeSessions removeObject:session];
      }

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
 * Session 级别
 */
- (void)URLSession:(NSURLSession *)session
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler
{
  [self handleChallenge:challenge completionHandler:completionHandler];
}

/**
 * Task 级别（dataTaskWithRequest:completionHandler: 可能会走这里）
 */
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler
{
  [self handleChallenge:challenge completionHandler:completionHandler];
}

- (void)handleChallenge:(NSURLAuthenticationChallenge *)challenge
      completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler
{
  if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
    NSString *host = challenge.protectionSpace.host;
    if ([host isEqualToString:@"111.230.155.174"]) {
      NSURLCredential *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
      completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
      return;
    }
  }
  completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
}

@end
