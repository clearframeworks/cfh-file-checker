"""Validate ZIP metadata and stage only bounded lockfiles; never run source code."""
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import zipfile

names = {'Cargo.lock', 'go.sum', 'go.mod', 'package-lock.json', 'npm-shrinkwrap.json',
         'yarn.lock', 'pnpm-lock.yaml', 'Pipfile.lock', 'poetry.lock', 'requirements.txt',
         'Gemfile.lock', 'composer.lock'}
os.chdir(tempfile.mkdtemp(prefix='cfh-source-', dir='/tmp'))
os.symlink(os.environ.get('CFH_INPUT_PATH', '/input/sample'), 'sample')
result = subprocess.run([sys.executable, '/scripts/archive.py'], env=dict(os.environ, OPERATION='inspect'), capture_output=True, text=True)
if result.returncode:
    print('Validation detail: ' + json.dumps(result.stdout[-500:], ensure_ascii=True))
    sys.exit('RESULT: Source archive failed path, link or resource validation; scan incomplete')
with zipfile.ZipFile('sample') as archive:
    selected = [item for item in archive.infolist() if not item.is_dir() and item.filename.rsplit('/', 1)[-1] in names]
    if len(selected) > 50:
        sys.exit('RESULT: More than 50 supported manifests; scan incomplete')
    total = 0
    groups = {}
    for item in selected:
        total += item.file_size
        if item.file_size > 2 * 1024 * 1024 or total > 10 * 1024 * 1024:
            sys.exit('RESULT: Dependency manifests exceed limits; scan incomplete')
        original_parent, filename = item.filename.rsplit('/', 1)
        if original_parent not in groups:
            groups[original_parent] = str(len(groups))
        destination = pathlib.Path(os.environ.get('CFH_OUTPUT_DIR', '/out')) / groups[original_parent] / filename
        destination.parent.mkdir(exist_ok=True)
        with archive.open(item) as source, destination.open('wb') as target:
            shutil.copyfileobj(source, target, 65536)
        print('LOCKFILE: ' + json.dumps(item.filename, ensure_ascii=True))
print('LOCKFILE_COUNT: ' + str(len(selected)))
