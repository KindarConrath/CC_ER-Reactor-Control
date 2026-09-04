"""Build compact offline CC packages using lossless LZW/base64 payloads."""
from pathlib import Path
import base64
import json
import zipfile
import zlib

root = Path(__file__).resolve().parents[1]
out = root.parent / 'dist'
VERSION = json.loads((root / 'lib/version.lua').read_text().removeprefix('return ').strip())


def compress(data):
    dictionary = {bytes([i]): i for i in range(256)}
    next_code = 256
    word = b''
    codes = []
    for value in data:
        char = bytes([value])
        combined = word + char
        if combined in dictionary:
            word = combined
        else:
            codes.append(dictionary[word])
            if next_code < 4096:
                dictionary[combined] = next_code
                next_code += 1
            else:
                dictionary = {bytes([i]): i for i in range(256)}
                next_code = 256
            word = char
    if word:
        codes.append(dictionary[word])
    packed = bytearray()
    for i in range(0, len(codes), 2):
        first = codes[i]
        packed.extend((first >> 4, (first & 15) << 4))
        if i + 1 < len(codes):
            second = codes[i + 1]
            packed[-1] |= second >> 8
            packed.append(second & 255)
    return base64.b64encode(packed).decode('ascii')


runtime = ['main.lua', 'agent.lua', 'startup.lua', 'diagnostics.lua', 'config.lua', 'THIRD_PARTY_NOTICES.txt']
runtime += [p.relative_to(root).as_posix() for p in sorted((root / 'lib').glob('*.lua'))]
runtime += ['vendor/basalt.lua', 'vendor/BASALT-LICENSE.txt']
# Refresh every first-party module. User configuration and the pinned vendor bundle
# are preserved; adding a runtime module must not require a second manifest edit.
update_paths = [name for name in runtime if name != 'config.lua' and not name.startswith('vendor/')]


def build(names, role):
    lines = [f'-- Reactor Control {VERSION} compact offline {role}. Basalt2 is MIT licensed.',
             (root / 'tools/package_codec.lua').read_text(), 'local files = {']
    for name in names:
        data = (root / name).read_bytes()
        lines.append(f'[{json.dumps(name)}] = {{{len(data)}, {zlib.adler32(data)}, "{compress(data)}"}},')
    lines += ['}', (root / f'tools/{role}_runtime.lua').read_text().replace('@VERSION@', VERSION)]
    path = out / f'reactor-control-{role}-{VERSION}.lua'
    path.write_text('\n'.join(lines))
    (out / f'reactor-control-{role}.lua').write_bytes(path.read_bytes())
    return path


def main():
    out.mkdir(exist_ok=True)
    installer = build(runtime, 'install')
    updater = build(update_paths, 'update')
    archive_path = out / f'reactor-control-{VERSION}.zip'
    source_paths = set(runtime + ['README.md', 'CHANGELOG.md'])
    for directory in ('docs', 'tests', 'tools'):
        source_paths.update(
            path.relative_to(root).as_posix()
            for path in (root / directory).rglob('*')
            if path.is_file() and path.suffix in {'.lua', '.py', '.md', '.txt'}
        )
    source_paths.update(name for name in ('LICENSE', 'NOTICE') if (root / name).is_file())
    with zipfile.ZipFile(archive_path, 'w', zipfile.ZIP_DEFLATED) as archive:
        for name in sorted(source_paths):
            archive.write(root / name, 'reactor-control/' + name)
        archive.write(installer, installer.name)
        archive.write(updater, updater.name)
    for path in (installer, updater, archive_path):
        print(f'{path} ({path.stat().st_size:,} bytes)')


if __name__ == '__main__':
    main()
