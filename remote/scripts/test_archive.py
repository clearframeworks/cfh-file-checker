"""Tests use synthetic fixtures only; run on an isolated GitHub runner."""
import os
import pathlib
import stat
import subprocess
import sys
import tempfile
import zipfile

script = pathlib.Path(__file__).with_name('archive.py').resolve()

def exercise(entries, operation='inspect', target='', expect_success=True):
    with tempfile.TemporaryDirectory() as directory:
        with zipfile.ZipFile(pathlib.Path(directory) / 'sample', 'w') as archive:
            for name, data in entries:
                archive.writestr(name, data)
        env = dict(os.environ, OPERATION=operation, ENTRY=target)
        result = subprocess.run([sys.executable, str(script)], cwd=directory, env=env, capture_output=True, text=True)
        assert (result.returncode == 0) == expect_success, result.stdout + result.stderr
        if expect_success and operation == 'remove':
            with zipfile.ZipFile(pathlib.Path(directory) / 'archive-output' / 'edited.zip') as edited:
                assert edited.namelist() == ['good/keep.txt']
                assert edited.read('good/keep.txt') == b'keep'
        if expect_success and operation == 'extract':
            assert (pathlib.Path(directory) / 'archive-output' / 'selected-file.bin').read_bytes() == b'keep'

exercise([('good/remove.txt', b'remove'), ('good/keep.txt', b'keep')], 'remove', 'good/remove.txt')
exercise([('good/keep.txt', b'keep')], 'extract', 'good/keep.txt')
exercise([('../escape.txt', b'x')], expect_success=False)
exercise([('/absolute.txt', b'x')], expect_success=False)
exercise([('C:/windows.txt', b'x')], expect_success=False)
exercise([('safe\\..\\escape.txt', b'x')], expect_success=False)
exercise([('same.txt', b'a'), ('same.txt', b'b')], expect_success=False)
exercise([('same.txt', b'a'), ('SAME.TXT', b'b')], expect_success=False)
exercise([('folder/trailing. ', b'x')], expect_success=False)
exercise([('folder/NUL.txt', b'x')], expect_success=False)
exercise([('bad//path.txt', b'x')], expect_success=False)
exercise([('folder', b'x'), ('FOLDER/file.txt', b'y')], expect_success=False)
exercise([('folder/COM¹.txt', b'x')], expect_success=False)
link = zipfile.ZipInfo('link'); link.create_system = 3; link.external_attr = (stat.S_IFLNK | 0o777) << 16
exercise([(link, b'target')], expect_success=False)
compressed = zipfile.ZipInfo('bomb.txt'); compressed.compress_type = zipfile.ZIP_DEFLATED
exercise([(compressed, b'x' * 200000)], expect_success=False)
exercise([('good.txt', b'x')], 'remove', 'missing.txt', expect_success=False)
exercise([('good.txt', b'x')], 'extract', 'missing.txt', expect_success=False)
print('Synthetic archive safety and removal tests passed.')
