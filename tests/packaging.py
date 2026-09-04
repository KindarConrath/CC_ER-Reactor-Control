"""Offline package integrity and installer/update behavior."""
from pathlib import Path
import importlib.util
import os
import posixpath
from lupa.lua52 import LuaRuntime

root = Path(__file__).resolve().parents[1]
dist = root.parent / 'dist'
spec = importlib.util.spec_from_file_location('package_builder', root / 'tools/package.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)
version = builder.VERSION
installer = (dist / f'reactor-control-install-{version}.lua').read_text()
updater_path = builder.build(builder.update_paths, 'update')
updater = updater_path.read_text()

with builder.zipfile.ZipFile(dist / f'reactor-control-{version}.zip') as archive:
    assert archive.read('reactor-control/tools/demo.lua') == (root / 'tools/demo.lua').read_bytes()
    assert archive.read('reactor-control/lib/demo.lua') == (root / 'lib/demo.lua').read_bytes()
    assert f'reactor-control-update-{version}.lua' not in archive.namelist()
    assert f'reactor-control-install-{version}.lua' in archive.namelist()
print('PASS first-release archive contains installer and source, but no updater artifact')
assert 'tools/demo.lua' not in builder.runtime
assert 'tools/demo.lua' not in builder.update_paths
assert 'lib/demo.lua' not in builder.runtime
assert 'lib/demo.lua' not in builder.update_paths
print('PASS development demo code stays in source archive, outside installed runtime')

# Binary edge cases exercise dictionary reset, repeated sequences and padding.
binary_lua = LuaRuntime(encoding=None, unpack_returned_tuples=True)
decode = binary_lua.execute((root / 'tools/package_codec.lua').read_bytes() + b'\nreturn unpackFile')
for data in (b'', b'A', b'AB', b'ABA', b'A' * 100000, bytes(range(256)) * 200, os.urandom(60000)):
    item = binary_lua.table_from([len(data), builder.zlib.adler32(data), builder.compress(data).encode()])
    assert decode(item) == data
print('PASS package codec binary round-trip, dictionary resets and padding')


class Computer:
    def __init__(self):
        self.files, self.dirs = {}, {''}
        self.capacity = 1_000_000
        self.messages = []
        self.mounts = {}
        self.fail_write = None
        self.fail_move = None
        self.answers = ['']
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        fs = self.lua.table()
        fs.combine = lambda left, right: self.path(left + '/' + right)
        fs.getDir = lambda path: self.path(path).rpartition('/')[0]
        fs.exists = lambda path: self.path(path) in self.files or self.path(path) in self.dirs
        fs.isDir = lambda path: self.path(path) in self.dirs
        fs.getSize = lambda path: len(self.files[self.path(path)].encode())
        fs.list = self.list
        fs.getDrive = self.drive
        fs.getCapacity = lambda path: self.capacity
        def free_space(path):
            self.drive(path)  # Match the documented requirement that the queried path exists.
            return self.capacity - self.used()
        fs.getFreeSpace = free_space
        fs.makeDir = self.mkdir
        fs.delete = self.delete
        fs.move = self.move
        fs.open = self.open
        self.lua.globals().fs = fs
        self.lua.globals().print = lambda *items: self.messages.append(' '.join(map(str, items)))
        self.lua.globals().write = lambda text: self.messages.append(text)
        self.lua.globals().shell = self.lua.table_from({'resolve': self.path})
        self.lua.globals().os.getComputerID = lambda: 42
        self.lua.globals().read = lambda: self.answers.pop(0)
        self.lua.globals().textutils = self.lua.execute((root / 'tests/memory_fs.lua').read_text()).new()[1]

    @staticmethod
    def path(path):
        result = posixpath.normpath('/' + path).lstrip('/')
        return '' if result == '.' else result

    def drive(self, path):
        path = self.path(path)
        assert path in self.files or path in self.dirs, 'No such path: ' + path
        for mount, drive in self.mounts.items():
            if path == mount or path.startswith(mount + '/'):
                return drive
        return 'hdd'

    def list(self, path):
        path = self.path(path)
        assert path in self.dirs
        prefix = path + '/' if path else ''
        names = {candidate[len(prefix):].split('/')[0]
                 for candidate in self.files.keys() | self.dirs
                 if candidate.startswith(prefix) and candidate != path}
        return self.lua.table_from(sorted(names))

    def used(self):
        return (sum(max(500, len(value.encode())) for path, value in self.files.items() if self.drive(path)=='hdd')
                + 500 * sum(self.drive(path)=='hdd' for path in self.dirs))

    def mkdir(self, path):
        path = self.path(path)
        if path in self.dirs:
            return
        self.mkdir(path.rpartition('/')[0])
        assert self.used() + 500 <= self.capacity, 'out of space'
        self.dirs.add(path)

    def delete(self, path):
        path = self.path(path)
        self.files = {candidate: value for candidate, value in self.files.items()
                      if candidate != path and not candidate.startswith(path + '/')}
        self.dirs = {candidate for candidate in self.dirs
                     if candidate != path and not candidate.startswith(path + '/')}

    def move(self, source, target):
        source, target = self.path(source), self.path(target)
        if self.fail_move and self.fail_move(source, target):
            self.fail_move = None
            raise RuntimeError('injected move failure')
        assert target not in self.files and target not in self.dirs
        assert target.rpartition('/')[0] in self.dirs
        if source in self.files:
            self.files[target] = self.files.pop(source)
        else:
            assert source in self.dirs
            moved_files = {target + candidate[len(source):]: value
                           for candidate, value in self.files.items()
                           if candidate.startswith(source + '/')}
            moved_dirs = {target + candidate[len(source):] for candidate in self.dirs
                          if candidate == source or candidate.startswith(source + '/')}
            self.delete(source)
            self.files.update(moved_files)
            self.dirs.update(moved_dirs)

    def open(self, path, mode):
        path = self.path(path)
        handle = self.lua.table()
        handle.close = lambda: None
        if mode == 'r':
            assert path in self.files
            handle.readAll = lambda: self.files[path]
        else:
            assert mode == 'w' and path.rpartition('/')[0] in self.dirs
            old = self.files.pop(path, None)
            assert self.used() + 500 <= self.capacity, 'out of space'
            self.files[path] = ''
            def write(text):
                if self.fail_write and self.fail_write(path):
                    raise RuntimeError('injected out of space')
                value = self.files[path] + text
                assert self.used() - max(500, len(self.files[path].encode())) + max(500, len(value.encode())) <= self.capacity, 'out of space'
                self.files[path] = value
            handle.write = write
        return handle

    def run(self, source, *args):
        return self.lua.execute(source, *args)


def must_fail(computer, source, message, *args):
    try:
        computer.run(source, *args)
    except Exception as exc:
        assert message in str(exc), exc
    else:
        raise AssertionError('Expected failure: ' + message)


computer = Computer();computer.run(installer)
for name in builder.runtime:
    assert computer.files['reactor-control/' + name] == (root / name).read_text()
must_fail(computer, installer, 'Destination exists')
print('PASS full bundled source round-trip and existing installation protection')

# Do not derive expectations from update_paths: a forgotten manifest entry must fail.
complete = Computer();complete.run(installer)
program_paths = ['main.lua', 'agent.lua', 'startup.lua', 'diagnostics.lua']
program_paths += [
    path.relative_to(root).as_posix()
    for path in (root / 'lib').glob('*.lua')
    if path.name != 'demo.lua'
]
for name in program_paths:
    complete.files['reactor-control/' + name] = '-- old installed module\n'
complete.files['reactor-control/config.lua'] = '-- user configuration\n'
complete.run(updater)
for name in program_paths:
    assert complete.files['reactor-control/' + name] == (root / name).read_text(), name
assert complete.files['reactor-control/config.lua'] == '-- user configuration\n'
print('PASS updater refreshes every runtime module, including network dependencies')

# Follow the installed launcher through the real startup entry to its role command.
def boot_target(computer, directory='reactor-control'):
    module = computer.run(computer.files[directory + '/lib/startup.lua'])
    computer.lua.globals().installedStartup = module
    computer.run('package.preload["lib.startup"] = function() return installedStartup end')
    called = []
    def execute(path, *args):
        called.append((path, args))
        if path.endswith('/startup.lua'):
            computer.lua.globals().shell.getRunningProgram = lambda: path
            computer.run(computer.files[computer.path(path)], *args)
        return True
    computer.lua.globals().shell.execute = execute
    computer.run(computer.files['startup/reactor-control.lua'])
    return called[-1]

assert boot_target(computer) == ('/reactor-control/main.lua', ('--boot',))
assert 'reactor-control/settings.dat' not in computer.files
print('PASS interactive controller install creates a launcher which reaches boot mode')

peer = Computer();peer.answers = ['unknown', ' 2 ', 'bad', '-1', '42', '1.5', '0']
peer.run(installer)
assert boot_target(peer) == ('/reactor-control/agent.lua', ('0',))
assert not peer.answers and any('Setup > Peers > add ID 42' in line for line in peer.messages)
print('PASS peer setup validates role and pairing; controller ID zero survives boot')

custom = Computer();custom.answers = []
custom.mkdir('plants')
custom.lua.globals().shell.resolve = lambda path: (
    custom.path('plants/' + path) if not path.startswith('/') else custom.path(path))
custom.run(installer, 'custom build', '--companion', '7')
assert boot_target(custom, 'plants/custom build') == ('/plants/custom build/agent.lua', ('7',))
print('PASS explicit companion role and custom relative directory boot using literal absolute paths')

for args, message in [(('--companion', '42'), 'different controller'),
                      (('--companion', '-1'), 'different controller'),
                      (('--companion', '1.5'), 'different controller'),
                      (('--companion',), 'requires'),
                      (('--controller', '--companion', '7'), 'only one'),
                      (('--unknown',), 'Unknown')]:
    invalid = Computer();before = dict(invalid.files), set(invalid.dirs)
    must_fail(invalid, installer, message, *args)
    assert (invalid.files, invalid.dirs) == before

for path in ('startup', 'startup/reactor-control.lua'):
    conflict = Computer();conflict.mkdir(conflict.path(path).rpartition('/')[0])
    conflict.files[path] = 'USER STARTUP'
    before = dict(conflict.files), set(conflict.dirs)
    must_fail(conflict, installer, 'startup', '--controller')
    assert (conflict.files, conflict.dirs) == before
print('PASS invalid roles and conflicting startup files fail before installation writes')

recoverable = Computer()
recoverable.fail_write = lambda path: path == 'reactor-control/startup-launcher.tmp'
must_fail(recoverable, installer, 'Program installed, but startup setup failed', '--controller')
assert 'reactor-control/main.lua' in recoverable.files
assert 'startup/reactor-control.lua' not in recoverable.files
assert 'reactor-control/startup-launcher.tmp' not in recoverable.files
recoverable.fail_write = None
module = recoverable.run(recoverable.files['reactor-control/lib/startup.lua'])
module.setup('reactor-control')
assert boot_target(recoverable) == ('/reactor-control/main.lua', ('--boot',))
print('PASS failed launcher write leaves installed code and can be repaired with startup setup')

# Installer present on disk alongside Basalt and startup must fit the normal quota.
quota = Computer();quota.files['install.lua'] = installer
quota.run(installer, '--controller')
assert quota.used() < 1_000_000
print(f'PASS installer, Basalt, runtime and startup fit 1 MB ({quota.used():,} bytes used)')

again = dict(complete.files), set(complete.dirs)
complete.run(updater)
assert (complete.files, complete.dirs) == again
print('PASS repeated update is idempotent')

# Corrupted payload must not erase a legacy backup or truncate any runtime file.
import re
broken = Computer();broken.run(installer)
broken.mkdir('reactor-control/backup-0.1.10')
broken.files['reactor-control/backup-0.1.10/main.lua'] = 'OLD CODE'
original = dict(broken.files), set(broken.dirs)
corrupt = re.sub(r'(\["[^"\n]+"\] = \{\d+, )\d+', r'\g<1>0', updater, count=1)
assert corrupt != updater
must_fail(broken, corrupt, 'Damaged package checksum')
assert (broken.files, broken.dirs) == original
print('PASS payload validation precedes legacy-backup cleanup and all runtime writes')
