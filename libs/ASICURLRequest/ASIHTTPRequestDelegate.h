// ASIHTTPRequestDelegate.h
// Part of ASICURLRequest — a libcurl-backed drop-in for ASIHTTPRequest.

#ifndef ASIHTTP_REQUEST_DELEGATE_H
#define ASIHTTP_REQUEST_DELEGATE_H

@class ASIHTTPRequest;

@protocol ASIHTTPRequestDelegate <NSObject>
@optional
- (void)requestFinished:(ASIHTTPRequest *)request;
- (void)requestFailed:(ASIHTTPRequest *)request;
- (void)requestStarted:(ASIHTTPRequest *)request;
@end

#endif
