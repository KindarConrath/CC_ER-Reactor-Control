"""Host tests: python -m pip install lupa; python tests/run.py
Uses Lua 5.2, matching CC:Tweaked syntax (not a Minecraft emulator).
"""
import os
from pathlib import Path
from lupa.lua52 import LuaRuntime

root = Path(__file__).resolve().parents[1]
os.chdir(root)
lua = LuaRuntime(unpack_returned_tuples=True)
check = lua.eval('''function(source, name)
  local chunk, loadError = load(source, name)
  return chunk ~= nil, loadError
end''')
files = list(root.rglob('*.lua'))
for path in files:
    ok, error = check(path.read_text(), str(path))
    assert ok, error
print(f'Syntax OK: {len(files)} Lua files', flush=True)
lua.execute((root / 'tests/run.lua').read_text())
restart_lua = LuaRuntime(unpack_returned_tuples=True)
restart_lua.execute((root / 'tests/restart.lua').read_text())
diagnostic_lua = LuaRuntime(unpack_returned_tuples=True)
diagnostic_lua.execute((root / 'tests/diagnostics.lua').read_text())
ui_lua = LuaRuntime(unpack_returned_tuples=True)
ui_lua.execute((root / 'tests/ui.lua').read_text())

for test in ("calibration.lua", "commissioning.lua", "calibration_ui.lua", "demo.lua", "setup.lua", "setup_ui.lua", "companion.lua", "companion_ui.lua", "controller_display.lua", "ui_cleanup.lua"):
    LuaRuntime(unpack_returned_tuples=True).execute((root / "tests" / test).read_text())
