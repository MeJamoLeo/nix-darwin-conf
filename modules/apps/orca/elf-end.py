"""Print the byte offset where the AppImage runtime (ELF) ends and the squashfs starts."""

import struct
import sys

with open(sys.argv[1], "rb") as f:
    h = f.read(64)
shoff, = struct.unpack_from("<Q", h, 0x28)
shentsize, shnum = struct.unpack_from("<HH", h, 0x3A)
print(shoff + shentsize * shnum)
