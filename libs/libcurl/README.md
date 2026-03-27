# libcrypto (OpenSSL) Analysis

## iPhone ToDo Section

### 1. SSL Certificate Validation (Critical)
The current `libcurl` + `libcrypto` (OpenSSL) build on Linux skips CA cert bundle detection for cross-compilation. 
* **Problem:** iOS apps using this build will fail HTTPS requests with SSL certificate errors because OpenSSL does not automatically use the iOS system keychain.
* **Fix:** 
    1. Download a `cacert.pem` file (e.g., from [curl.se](https://curl.se/docs/caextract.html)).
    2. Add `cacert.pem` to your app's bundle/Resources.
    3. At runtime, point `libcurl` to this file:
    ```objc
    curl_easy_setopt(curl, CURLOPT_CAINFO, [[[NSBundle mainBundle] pathForResource:@"cacert" ofType:@"pem"] UTF8String]);
    ```

### 2. Hardcoded Prefix Paths
The library is currently built with a prefix of `/opt/osxcross/libs/libcurl/build-phone/prefix/`.
* **Note:** Since these paths do not exist on an iPhone, ensure all paths (CA bundles, config files) are provided manually at runtime. The static nature of the library means the code is portable, but default filesystem paths are not.

### 3. Verification
* **Mach-O Check:** Verify the final merged `libcrypto.a` using `file` to ensure both `armv7` and `arm64` slices are present.
* **Symbol Check:** Ensure there are no missing symbols related to the `resolv` library, as `-lresolv` was required in the final curl link step.

## Mac ToDo Section

### 1. SSL Certificate Validation (Critical)
Same as the iPhone build: `libcurl` is built without a default CA bundle path.
* **Symptom:** HTTPS requests will fail on macOS because OpenSSL does not use the system keychain (Secure Transport is not enabled).
* **Fix:** Use `CURLOPT_CAINFO` pointing to a bundled `cacert.pem`.

