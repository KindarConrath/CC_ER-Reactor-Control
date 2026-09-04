"""Build compact offline CC packages using lossless LZW/base64 payloads."""
from pathlib import Path
import argparse
import base64
import json
import zipfile
import zlib

root = Path(__file__).resolve().parents[1]
out = root.parent / 'dist'
VERSION = json.loads((root / 'lib/version.lua').read_text().removeprefix('return ').strip())


def compress(data):
    dictionary = {bytes([value]): value for value in range(256)}
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
                dictionary = {bytes([value]): value for value in range(256)}
                next_code = 256
            word = char
    if word:
        codes.append(dictionary[word])
    packed = bytearray()
    for index in range(0, len(codes), 2):
        first = codes[index]
        packed.extend((first >> 4, (first & 15) << 4))
        if index + 1 < len(codes):
            second = codes[index + 1]
            packed[-1] |= second >> 8
            packed.append(second & 255)
    return base64.b64encode(packed).decode('ascii')


runtime = [
    'main.lua', 'agent.lua', 'startup.lua', 'diagnostics.lua', 'config.lua',
    'LICENSE', 'THIRD_PARTY_NOTICES.txt',
]
runtime += [
    path.relative_to(root).as_posix()
    for path in sorted((root / 'lib').glob('*.lua'))
    if path.name != 'demo.lua'
]
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


def source_files():
    paths = set(runtime + ['README.md', 'CHANGELOG.md'])
    paths.update(
        path.relative_to(root).as_posix()
        for path in (root / 'lib').glob('*.lua')
    )
    for directory in ('docs', 'tests', 'tools'):
        paths.update(
            path.relative_to(root).as_posix()
            for path in (root / directory).rglob('*')
            if path.is_file() and path.suffix in {'.lua', '.py', '.md', '.txt'}
        )
    paths.update(name for name in ('LICENSE', 'NOTICE') if (root / name).is_file())
    paths.add('.gitignore')
    return paths


def build_archive(installer):
    archive_path = out / f'reactor-control-{VERSION}.zip'
    with zipfile.ZipFile(archive_path, 'w', zipfile.ZIP_DEFLATED) as archive:
        for name in sorted(source_files()):
            archive.write(root / name, 'reactor-control/' + name)
        archive.write(installer, installer.name)
    return archive_path


def parse_args():
    parser = argparse.ArgumentParser(description='Build Reactor Control release packages')
    parser.add_argument(
        '--with-updater', action='store_true',
        help='also build the maintained updater for compatibility testing or later releases')
    return parser.parse_args()


def main():
    arguments = parse_args()
    out.mkdir(exist_ok=True)
    installer = build(runtime, 'install')
    artifacts = [installer]
    if arguments.with_updater:
        artifacts.append(build(update_paths, 'update'))
    artifacts.append(build_archive(installer))
    for path in artifacts:
        print(f'{path} ({path.stat().st_size:,} bytes)')


if __name__ == '__main__':
    main()
