# White ICNS representations

These original, opaque-white JPEG 2000 images supply the 256, 512 and 1024px
ICNS entries without requiring an image converter during project generation.
The generator creates the 16, 32, 48 and 128px planar RGB/mask entries itself.
The representation types and sizes match ENIL's icon; none of its artwork is used.

To reproduce with ImageMagick (use `convert` on ImageMagick 6):

```sh
for size in 256 512 1024; do
  magick -size "${size}x${size}" xc:white -depth 8 "white-${size}.jp2"
done
```

Keep JPEG 2000 encoding, not PNG payloads, for the legacy compatibility profile.
