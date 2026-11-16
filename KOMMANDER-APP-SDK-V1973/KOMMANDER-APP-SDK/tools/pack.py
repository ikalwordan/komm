"""Convert a linked, zero-based MIPS ELF (--emit-relocs) into a checked KAP1.
Reject unsupported relocation types instead of guessing at their semantics.
No external Python packages; also used as the build-time kapcheck.
"""
import argparse
import pathlib
import struct
import zlib


def kapmem(elf):
    """V1452: the KAP_MEMORY(heap, extra) request from the .kapmem section, or None."""
    shoff, = struct.unpack_from('<I', elf, 32)
    shnum, shstrndx = struct.unpack_from('<HH', elf, 48)
    secs = [struct.unpack_from('<10I', elf, shoff + i * 40) for i in range(shnum)]
    names = secs[shstrndx]
    for s in secs:
        end = elf.index(b'\0', names[4] + s[0])
        if elf[names[4] + s[0]:end] == b'.kapmem':
            if s[5] != 8:
                raise ValueError('.kapmem must hold two words (KAP_MEMORY)')
            return struct.unpack_from('<II', elf, s[4])
    return None


def pack(elf, heap=262144, extra=0):
    def unpack(fmt, offset):
        return struct.unpack_from('<' + fmt, elf, offset)
    if elf[:7] != b'\x7fELF\x01\x01\x01':
        raise ValueError('expected little-endian ELF32')
    typ, machine = unpack('HH', 16)
    entry, _, shoff = unpack('III', 24)
    shsize, shnum = unpack('HH', 46)
    if (typ, machine, shsize) != (2, 8, 40):
        raise ValueError('expected linked MIPS ELF with section headers')
    sections = [unpack('10I', shoff + i * 40) for i in range(shnum)]
    allocated = [s for s in sections if s[2] & 2 and s[5]]
    if not allocated or min(s[3] for s in allocated) != 0:
        raise ValueError('image must start at zero')
    memory = (max(s[3] + s[5] for s in allocated) + 15) & ~15
    image_size = max(s[3] + s[5] for s in allocated if s[1] != 8)
    if memory + heap > 8 * 1024 * 1024 or heap < 0:
        raise ValueError('KAP exceeds 8 MiB arena budget (the LOW tier)')
    if extra < 0 or extra % 16 or memory + heap + extra > 16 * 1024 * 1024:
        raise ValueError('KAP extra heap must be a multiple of 16 and fit 16 MiB with memory and heap (the HIGH tier)')
    image = bytearray(image_size)
    for s in allocated:
        if s[1] != 8:
            payload = elf[s[4]:s[4] + s[5]]
            if len(payload) != s[5]:
                raise ValueError('truncated section')
            image[s[3]:s[3] + s[5]] = payload
    if not any(s[2] & 4 and s[3] <= entry < s[3] + s[5] for s in allocated):
        raise ValueError('entry is not executable')
    patches = {}
    for s in sections:
        if s[1] == 4:
            raise ValueError('RELA is unsupported')
        if s[1] != 9 or not sections[s[7]][2] & 2:
            continue
        if s[9] != 8 or s[5] % 8:
            raise ValueError('invalid REL section')
        symbols = sections[s[6]]
        for pos in range(s[4], s[4] + s[5], 8):
            off, info = unpack('II', pos)
            kind, sym = info & 255, info >> 8
            if kind == 0:
                continue
            if off % 4 or off + 4 > len(image):
                raise ValueError('relocation outside image')
            if sym * 16 + 16 > symbols[5]:
                raise ValueError('invalid symbol')
            sym_section = unpack('H', symbols[4] + sym * 16 + 14)[0]
            if sym_section == 0:
                raise ValueError('unresolved import')
            if sym_section == 0xfff1:  # SHN_ABS is not image-relative
                continue
            if sym_section >= len(sections) or not sections[sym_section][2] & 2:
                raise ValueError('reference to non-allocated section')
            word = struct.unpack_from('<I', image, off)[0]
            if kind == 2:
                patches[off] = (word, kind)
            elif kind == 4:
                patches[off] = ((word & 0x03ffffff) << 2, kind)
            elif kind == 5:
                # Runtime arena is 64 KiB aligned: adding its base cannot change
                # a low half or its signed carry. This also handles a compiler
                # reusing one LUI for several different LO16 instructions.
                patches[off] = ((word & 65535) << 16, kind)
            elif kind == 6:
                patches[off] = (word & 65535, kind)
            else:
                raise ValueError(f'unsupported MIPS relocation {kind}')
    for offset, (value, kind) in patches.items():
        if (kind in (2, 4) and value > memory) or (kind == 5 and value > memory + 65535):
            raise ValueError(f'relocated address outside image: {offset:x} -> {value:x}')
    relocs = b''.join(struct.pack('<III', off, *patches[off]) for off in sorted(patches))
    payload = image + relocs
    return struct.pack('<10I', 0x3150414b, 1, 40, len(image), memory, entry,
                       len(patches), heap, zlib.crc32(payload), extra) + payload


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('elf', type=pathlib.Path)
    parser.add_argument('output', type=pathlib.Path)
    parser.add_argument('--heap', type=int, default=262144)
    args = parser.parse_args()
    elf = args.elf.read_bytes()
    req = kapmem(elf)
    result = pack(elf, *(req if req else (args.heap, 0)))
    args.output.write_bytes(result)
    print(f'KAP checked: {len(result)} bytes -> {args.output}')
