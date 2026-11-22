#!/usr/bin/env python3
"""Replace one raw BGRA8888 entry in an extracted image.bin.

Format of each entry in /tmp/image.bin (decompressed image.bin.lzma):
    64 bytes  name, NUL padded
    12 bytes  u32 flags, u32 descriptor, u32 data_size
    N bytes   raw BGRA8888 pixels

The descriptor packs format, width and height:
    desc = (height << 20) | (width_hi4 << 16) | (width_lo8 << 8) | format
so it can be decoded with:
    format = desc & 0xff
    width  = ((desc >> 8) & 0xff) | (((desc >> 16) & 0x0f) << 8)
    height = (desc >> 16) >> 4

Usage:
  ./replace_packed_image.py --image-bin image.bin \
      --name hm_bg.jpg --input new.jpg --output image.bin
"""
import argparse
import pathlib
import struct
import subprocess


def ffprobe_size(path):
    out = subprocess.check_output([
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "stream=width,height", "-of", "csv=p=0", str(path),
    ], text=True).strip().split(",")
    return int(out[0]), int(out[1])


def decode_bgra(path, expected_size):
    rgba = subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", str(path),
        "-f", "rawvideo", "-pix_fmt", "rgba", "-",
    ])
    if len(rgba) != expected_size:
        raise SystemExit(
            f"decoded {len(rgba)} bytes, expected {expected_size}")
    bgra = bytearray(rgba)
    bgra[0::4] = rgba[2::4]
    bgra[2::4] = rgba[0::4]
    return bytes(bgra)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--image-bin", required=True)
    ap.add_argument("--name", required=True)
    ap.add_argument("--input", required=True)
    ap.add_argument("--output", required=True)
    a = ap.parse_args()

    data = bytearray(pathlib.Path(a.image_bin).read_bytes())
    needle = a.name.encode() + b"\0"
    pos = data.find(needle)
    if pos < 0:
        raise SystemExit(f"entry {a.name} not found")
    if data[pos:pos + 64].rstrip(b"\0") != needle.rstrip(b"\0"):
        raise SystemExit(f"entry {a.name} has an invalid 64-byte name field")

    flags, desc, size = struct.unpack_from("<III", data, pos + 64)
    fmt = desc & 0xff
    width = ((desc >> 8) & 0xff) | (((desc >> 16) & 0x0f) << 8)
    height = (desc >> 16) >> 4
    print(f"{a.name}: flags={flags} fmt={fmt} {width}x{height} data={size}")

    iw, ih = ffprobe_size(a.input)
    if (iw, ih) != (width, height):
        raise SystemExit(f"input is {iw}x{ih}, entry needs {width}x{height}")

    raw = decode_bgra(a.input, size)
    data[pos + 76:pos + 76 + size] = raw
    pathlib.Path(a.output).write_bytes(data)
    print(f"patched -> {a.output} ({len(data)} bytes)")


if __name__ == "__main__":
    main()
