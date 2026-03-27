# libcrypto (OpenSSL) Analysis

### 3. Verification
* **Mach-O Check:** Verify the final merged `libcrypto.a` using `file` to ensure both `armv7` and `arm64` slices are present.
* **Symbol Check:** Ensure there are no missing symbols related to the `resolv` library, as `-lresolv` was required in the final curl link step.


