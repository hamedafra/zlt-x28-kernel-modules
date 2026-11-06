"""Pull the kernel out of an Android boot image and decompress it if needed.

usage: bootimg_kernel.py boot.img out_dir   -> writes out_dir/kernel.bin and out_dir/Image
"""
import gzip
import os
import struct
import subprocess
import sys

d = open(sys.argv[1], "rb").read()
out = sys.argv[2]
os.makedirs(out, exist_ok=True)
print("magic:", d[:8])
ks, ka, rs, ra, ss, sa, tags, ps = struct.unpack("<8I", d[8:40])
hv = struct.unpack("<I", d[40:44])[0]
print(f"kernel_size={ks} kernel_addr={ka:#x} page_size={ps} ramdisk_size={rs} header_version={hv}")
k = d[ps:ps + ks]
open(f"{out}/kernel.bin", "wb").write(k)
kind = "gzip" if k[:2] == b"\x1f\x8b" else "lz4" if k[:4] == b"\x04\x22\x4d\x18" else "raw"
print("kernel payload:", kind, len(k), "bytes")
img = f"{out}/Image"
if kind == "gzip":
    # the gzip stream may be followed by an appended DTB; gzip.decompress stops at the stream's end
    data = gzip.GzipFile(fileobj=__import__("io").BytesIO(k)).read()
    open(img, "wb").write(data)
elif kind == "lz4":
    subprocess.run(["lz4", "-d", "-f", f"{out}/kernel.bin", img], check=True)
else:
    open(img, "wb").write(k)
im = open(img, "rb").read()
# arm64 Image header: code0 code1 text_offset image_size flags ... magic "ARM\x64" at 56
print("Image:", len(im), "bytes, magic at 56:", im[56:60], "text_offset=%#x image_size=%#x" % struct.unpack("<QQ", im[8:24]))
