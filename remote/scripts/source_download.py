"""Fetch a bounded GitHub source archive at an exact commit without credentials."""
import os
import re
import subprocess
import sys

repository = os.environ.get('SOURCE_REPOSITORY', '')
revision = os.environ.get('SOURCE_REVISION', '')
if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,99}/[A-Za-z0-9][A-Za-z0-9_.-]{0,99}', repository):
    sys.exit('RESULT: Invalid public GitHub repository')
if not re.fullmatch(r'[0-9a-f]{40}', revision):
    sys.exit('RESULT: Source revision must be a full lowercase 40-character commit')
env = dict(os.environ, TARGET_URL=f'https://github.com/{repository}/archive/{revision}.zip', MAX_DOWNLOAD_BYTES=str(10 * 1024 * 1024))
result = subprocess.run([sys.executable, 'scripts/download.py'], env=env)
if result.returncode:
    sys.exit('RESULT: Source download failed; scan incomplete')
print('Source archive retrieved at requested commit; maximum download 10 MiB.')
