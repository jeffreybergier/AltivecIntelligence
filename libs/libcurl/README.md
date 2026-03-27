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

### 2. Threaded Resolver Disabled
The build explicitly uses `--disable-threaded-resolver`.
* **Problem:** DNS lookups will be synchronous and blocking.
* **Risk:** In a GUI Mac app, this will cause the "spinning beachball" (app hang) if a DNS lookup takes more than a few milliseconds.
* **Recommendation:** Switch to `--enable-threaded-resolver` or bundle `c-ares`.

### 3. C11 Atomics Disabled (`HAVE_ATOMIC=0`)
The build script manually overrides `HAVE_ATOMIC` and `HAVE_STDATOMIC_H` to 0.
* **Problem:** This disables modern thread-safe operations in curl's internal logic.
* **Context:** This was likely done for compatibility with very old macOS versions (10.5/10.6), but it is applied even to the `arm64` slice (which is macOS 11+).
* **Performance:** High-concurrency network operations may be slightly less efficient.

### 4. LDAP Dependencies
The Mac build has LDAP enabled (`LDAP: enabled (OpenLDAP)`).
* **Problem:** It links against `-lldap`. If this is not a static library within the toolchain, it might try to link against a system LDAP library on the target Mac that has a different version or is deprecated.
* **Check:** Verify `otool -L` on the final binary to see if it has a dynamic dependency on `/usr/lib/libldap.dylib`.

### 5. Toolchain Wrapper Warnings
The log shows `osxcross: warning: this wrapper was built for target 'darwin9'`.
* **Meaning:** You are using a Leopard (10.5) compiler wrapper for modern macOS (11.0) targets.
* **Impact:** This is mostly harmless but confirms the "legacy-first" nature of the environment. Ensure modern linker features (like `rpath` or `bitcode`) are not being incorrectly suppressed by the old wrapper.
