// Original placeholder artwork. Conversion of user artwork uses ImageMagick only on request.
const fs = require("node:fs");
const path = require("node:path");
const zlib = require("node:zlib");
const { spawnSync } = require("node:child_process");
const icons = {
  "AppIcon29x29.png": 29,
  "AppIcon29x29@2x.png": 58,
  "AppIcon40x40@2x.png": 80,
  "AppIcon57x57.png": 57,
  "AppIcon57x57@2x.png": 114,
  "AppIcon60x60@2x.png": 120,
  "AppIcon60x60@3x.png": 180,
};
const launches = {
  "Default.png": [320, 480],
  "Default@2x.png": [640, 960],
  "Default-568h@2x.png": [640, 1136],
  "Default-iOS8-667h@2x.png": [750, 1334],
  "Default-iOS8-736h@3x.png": [1242, 2208],
  "Default-iOS11-812h@3x.png": [1125, 2436],
  "Default-iOS12-896h@2x.png": [828, 1792],
  "Default-iOS12-896h@3x.png": [1242, 2688],
};
function u32(n) {
  const b = Buffer.alloc(4);
  b.writeUInt32BE(n);
  return b;
}
function crc(data) {
  let c = 0xffffffff;
  for (const n of data) {
    c ^= n;
    for (let i = 0; i < 8; i++) c = (c >>> 1) ^ (c & 1 ? 0xedb88320 : 0);
  }
  return (c ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const body = Buffer.concat([Buffer.from(type), data]);
  return Buffer.concat([u32(data.length), body, u32(crc(body))]);
}
function pixels(w, h) {
  return Buffer.alloc(w * h * 4, 255);
}
function png(w, h, rgba) {
  const rows = Buffer.alloc(h * (w * 4 + 1));
  for (let y = 0; y < h; y++)
    rgba.copy(rows, y * (w * 4 + 1) + 1, y * w * 4, (y + 1) * w * 4);
  return Buffer.concat([
    Buffer.from("89504e470d0a1a0a", "hex"),
    chunk(
      "IHDR",
      Buffer.concat([u32(w), u32(h), Buffer.from([8, 6, 0, 0, 0])]),
    ),
    chunk("IDAT", zlib.deflateSync(rows)),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}
function pack(data) {
  const out = [];
  for (let i = 0; i < data.length;) {
    let n = 1;
    while (n < 130 && i + n < data.length && data[i + n] === data[i]) n++;
    if (n >= 3) {
      out.push(n + 125, data[i]);
      i += n;
    } else {
      let start = i++;
      while (
        i < data.length &&
        i - start < 128 &&
        !(data[i] === data[i + 1] && data[i] === data[i + 2])
      )
        i++;
      out.push(i - start - 1, ...data.subarray(start, i));
    }
  }
  return Buffer.from(out);
}
function element(type, data) {
  if (data.length + 8 > 300000)
    throw Error("ICNS element exceeds Leopard limit");
  return Buffer.concat([Buffer.from(type), u32(data.length + 8), data]);
}
function icns(getPixels, source) {
  const parts = [];
  for (const [n, rgb, mask] of [
    [16, "is32", "s8mk"],
    [32, "il32", "l8mk"],
    [48, "ih32", "h8mk"],
    [128, "it32", "t8mk"],
  ]) {
    const rgba = getPixels(n),
      channels = [0, 1, 2, 3].map((c) =>
        Buffer.from(Array.from({ length: n * n }, (_, i) => rgba[i * 4 + c])),
      );
    parts.push(
      element(
        rgb,
        Buffer.concat([
          ...(n === 128 ? [Buffer.alloc(4)] : []),
          ...channels.slice(0, 3).map(pack),
        ]),
      ),
      element(mask, channels[3]),
    );
  }
  // Match ENIL: legacy planar RGB/masks plus JPEG 2000 high-resolution images.
  for (const [n, type] of [[256, "ic08"], [512, "ic09"], [1024, "ic10"]]) {
    let data;
    if (source) {
      const r = spawnSync("magick", [path.resolve(source), "-resize", `${n}x${n}!`,
        "-depth", "8", "jp2:-"], { maxBuffer: 8e6 });
      if (r.error || r.status !== 0)
        throw Error("Artwork conversion requires ImageMagick with JPEG 2000 support");
      data = r.stdout;
    } else {
      data = fs.readFileSync(path.join(__dirname, "../templates/artwork", `white-${n}.jp2`));
    }
    parts.push(element(type, data));
  }
  const body = Buffer.concat(parts);
  if (body.length + 8 > 1000000) throw Error("ICNS exceeds Leopard file limit");
  return Buffer.concat([Buffer.from("icns"), u32(body.length + 8), body]);
}
function generate(root, source) {
  const convert = (n) => {
    if (!source) return pixels(n, n);
    const r = spawnSync(
      "magick",
      [path.resolve(source), "-resize", `${n}x${n}!`, "-depth", "8", "rgba:-"],
      { maxBuffer: 8e6 },
    );
    if (r.error || r.status !== 0 || r.stdout.length !== n * n * 4)
      throw Error(
        "Artwork conversion requires ImageMagick (magick) and a readable image",
      );
    return r.stdout;
  };
  const ios = path.join(root, "source/iOS/Resources"),
    mac = path.join(root, "source/macOS/Resources");
  if (fs.existsSync(ios)) {
    for (const [name, n] of Object.entries(icons))
      fs.writeFileSync(path.join(ios, name), png(n, n, convert(n)));
    for (const [name, [w, h]] of Object.entries(launches))
      fs.writeFileSync(path.join(ios, name), png(w, h, pixels(w, h)));
  }
  if (fs.existsSync(mac))
    fs.writeFileSync(path.join(mac, "AppIcon.icns"), icns(convert, source));
}
function validate(root) {
  const ios = path.join(root, "source/iOS/Resources");
  if (fs.existsSync(ios)) {
    for (const [name, [w, h]] of Object.entries({
      ...Object.fromEntries(Object.entries(icons).map(([k, n]) => [k, [n, n]])),
      ...launches,
    })) {
      const b = fs.readFileSync(path.join(ios, name));
      if (
        b.subarray(0, 8).toString("hex") !== "89504e470d0a1a0a" ||
        b.readUInt32BE(16) !== w ||
        b.readUInt32BE(20) !== h
      )
        throw Error(`Invalid PNG dimensions: ${name}`);
      let offset = 8;
      while (offset < b.length) {
        const n = b.readUInt32BE(offset);
        if (
          offset + n + 12 > b.length ||
          crc(b.subarray(offset + 4, offset + 8 + n)) !==
            b.readUInt32BE(offset + 8 + n)
        )
          throw Error(`Invalid PNG chunk: ${name}`);
        offset += 12 + n;
      }
    }
  }
  const file = path.join(root, "source/macOS/Resources/AppIcon.icns");
  if (fs.existsSync(file)) {
    const b = fs.readFileSync(file),
      seen = new Set();
    if (
      b.toString("ascii", 0, 4) !== "icns" ||
      b.readUInt32BE(4) !== b.length ||
      b.length > 1000000
    )
      throw Error("Invalid ICNS");
    let i = 8;
    while (i < b.length) {
      const n = b.readUInt32BE(i + 4);
      if (n < 8 || n > 300000 || i + n > b.length)
        throw Error("Invalid ICNS element");
      const type = b.toString("ascii", i, i + 4);
      const size = { ic08: 256, ic09: 512, ic10: 1024 }[type];
      if (size) {
        const data = b.subarray(i + 8, i + n);
        if (data.subarray(0, 12).toString("hex") !== "0000000c6a5020200d0a870a")
          throw Error(`Invalid JPEG 2000 ICNS element: ${type}`);
        let dimensions;
        for (let j = 12; j + 8 <= data.length;) {
          const length = data.readUInt32BE(j);
          if (length < 8 || j + length > data.length)
            throw Error(`Invalid JPEG 2000 box: ${type}`);
          if (data.toString("ascii", j + 4, j + 8) === "jp2h" && length >= 30 &&
              data.toString("ascii", j + 12, j + 16) === "ihdr")
            dimensions = [data.readUInt32BE(j + 16), data.readUInt32BE(j + 20)];
          j += length;
        }
        if (!dimensions || dimensions.some(n => n !== size))
          throw Error(`Invalid JPEG 2000 dimensions: ${type}`);
      }
      seen.add(type);
      i += n;
    }
    for (const k of [
      "is32",
      "s8mk",
      "il32",
      "l8mk",
      "ih32",
      "h8mk",
      "it32",
      "t8mk",
      "ic08",
      "ic09",
      "ic10",
    ])
      if (!seen.has(k)) throw Error(`Missing ICNS element: ${k}`);
  }
}
module.exports = { generate, validate, icons, launches };
