"""Exercise only synthetic ZIPs inside the isolated preparation container."""
import os
import pathlib
import stat
import subprocess
import sys
import tempfile
import zipfile

with tempfile.TemporaryDirectory(dir='/tmp') as directory:
    base = pathlib.Path(directory)
    good = base / 'good.zip'
    with zipfile.ZipFile(good, 'w') as archive:
        archive.writestr('project/go.mod', 'module example.org/test\n')
        archive.writestr('project/go.sum', 'example.org/a v1.0.0 h1:test\n')
        archive.writestr('project/sub/Cargo.lock', 'version = 3\n')
    out = base / 'out'; out.mkdir()
    env = dict(os.environ, CFH_INPUT_PATH=str(good), CFH_OUTPUT_DIR=str(out))
    result = subprocess.run([sys.executable, '/scripts/source_prepare.py'], env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr
    assert (out / '0/go.mod').is_file() and (out / '0/go.sum').is_file()
    assert (out / '1/Cargo.lock').is_file()
    bad = base / 'bad.zip'
    link = zipfile.ZipInfo('project/link'); link.create_system = 3; link.external_attr = (stat.S_IFLNK | 0o777) << 16
    with zipfile.ZipFile(bad, 'w') as archive:
        archive.writestr(link, '/etc/passwd')
    env['CFH_INPUT_PATH'] = str(bad)
    result = subprocess.run([sys.executable, '/scripts/source_prepare.py'], env=env, capture_output=True, text=True)
    assert result.returncode != 0 and 'scan incomplete' in result.stderr
print('Synthetic source grouping and symlink tests passed.')
