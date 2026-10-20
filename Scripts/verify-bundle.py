"""Inspect actual shipped Mach-O slices and minimum OS without executing them."""
import json
import struct
from pathlib import Path

def inspect(path):
    data = path.read_bytes()
    magic, count = struct.unpack_from('>II', data)
    assert magic in (0xcafebabe, 0xcafebabf), f'{path}: not universal'
    archs = {}
    for i in range(count):
        if magic == 0xcafebabe:
            cpu, subtype, offset, size, align = struct.unpack_from('>IIIII', data, 8 + 20*i)
        else:
            cpu, subtype, offset, size, align, reserved = struct.unpack_from('>IIQQII', data, 8 + 32*i)
        assert data[offset:offset+4] == b'\xcf\xfa\xed\xfe', 'Expected 64-bit Mach-O'
        ncmds = struct.unpack_from('<I', data, offset+16)[0]
        pos = offset + 32
        minimum = None
        for j in range(ncmds):
            cmd, cmdsize = struct.unpack_from('<II', data, pos)
            assert cmdsize >= 8 and pos + cmdsize <= offset + size
            if cmd == 0x32:
                platform, minimum = struct.unpack_from('<II', data, pos+8)
                assert platform == 1, 'Expected macOS platform'
            elif cmd == 0x24:
                minimum = struct.unpack_from('<I', data, pos+8)[0]
            pos += cmdsize
        assert minimum is not None and minimum <= 0x000c0000, f'{path}: needs macOS newer than 12'
        name = {0x01000007: 'x86_64', 0x0100000c: 'arm64'}.get(cpu, hex(cpu))
        archs[name] = {'minimumOS': f'{minimum >> 16}.{(minimum >> 8) & 255}.{minimum & 255}'}
    assert 'x86_64' in archs and 'arm64' in archs, f'{path}: missing architecture'
    return archs

bundle = Path('build/Wyrm.app/Contents')
report = {str(path.relative_to(bundle)): inspect(path) for path in
          [bundle/'MacOS/Wyrm', bundle/'Frameworks/SDL3.framework/SDL3']}
assert (bundle/'Resources/app/res/shaders/bin/bdv.spv').is_file()
assert (bundle/'Resources/app/res/textures/tex_atlas_8k.png').is_file()
Path('dist').mkdir(exist_ok=True)
Path('dist/bundle-verification.json').write_text(json.dumps(report, indent=2))
print(json.dumps(report, indent=2))
