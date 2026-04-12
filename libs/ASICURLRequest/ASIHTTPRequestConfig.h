// ASIHTTPRequestConfig.h
// Part of ASICURLRequest — a libcurl-backed drop-in for ASIHTTPRequest.
// Tiger-compatible (10.4+). No GCD, no blocks, no NSOperationQueue.

#ifndef ASIHTTP_REQUEST_CONFIG_H
#define ASIHTTP_REQUEST_CONFIG_H

extern NSString * const ASIHTTPRequestErrorDomain;

// Error codes matching the original ASIHTTPRequest constants
enum {
  ASIConnectionFailureErrorType   = 1,
  ASIRequestTimedOutErrorType     = 2,
  ASIAuthenticationErrorType      = 3,
  ASIRequestCancelledErrorType    = 4,
  ASIUnableToCreateRequestError   = 5,
  ASITooMuchRedirectionErrorType  = 9,
};

#endif
