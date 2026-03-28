# 📝 TODO: AICURLConnection Async Implementation Plan

This document outlines the roadmap for bringing asynchronous `NSURLConnection` parity to `AICURLConnection`, focusing on **Mac OS X 10.4 Tiger** compatibility.

## 🎯 Goal
Implement a subset of the `NSURLConnection` API that allows for non-blocking network requests while using standard `NSURLConnectionDelegate` patterns.

---

### Phase 1: The Asynchronous Engine
- **Mechanism**: Use `NSThread` to wrap `curl_easy_perform`.
- **Rationale**: Simplest and most robust approach for Tiger/Leopard without the complexity of `curl_multi` / `CFRunLoopSource`.
- **Task**: Implement a background worker method that handles the CURL lifecycle.

### Phase 2: Core Lifecycle API (10.4 Parity)
Implement the following methods in `AICURLConnection`:
- `+ (BOOL)canHandleRequest:(NSURLRequest *)request;`
- `- (id)initWithRequest:(NSURLRequest *)request delegate:(id)delegate;`
- `- (id)initWithRequest:(NSURLRequest *)request delegate:(id)delegate startImmediately:(BOOL)startImmediately;`
- `- (void)start;`
- `- (void)cancel;`

### Phase 3: Delegate Forwarding (Type Mismatch Strategy)
Map internal CURL events to standard `NSURLConnectionDelegate` methods. Even though the first parameter will be an `AICURLConnection` instead of an `NSURLConnection`, the method signatures will remain identical for ease of use.

**Methods to Support:**
1. `connection:didReceiveResponse:` (Triggered by CURL header callback)
2. `connection:didReceiveData:` (Triggered by CURL write callback)
3. `connection:didFailWithError:` (Triggered by non-zero CURL codes)
4. `connectionDidFinishLoading:` (Triggered by successful CURL completion)

**Threading Safety:** Use `performSelector:onThread:withObject:waitUntilDone:YES` to ensure all delegate callbacks fire on the thread where the connection was initiated (typically the Main Thread).

### Phase 4: Header & Response Handling
- **Header Parsing**: Implement `CURLOPT_HEADERFUNCTION` to capture HTTP headers.
- **Response Object**: Accumulate headers into an `NSDictionary` and use the `NSHTTPURLResponse (CrossPlatform)` category to instantiate a proper response object for the delegate.

### Phase 5: RunLoop Management
- Implement `- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode;`
- Ensure callbacks respect the specified RunLoop modes (e.g., handling downloads during window resizing or menu tracking).

---
*Plan formulated for くまさん*
