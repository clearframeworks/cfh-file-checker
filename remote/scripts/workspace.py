"""Static text operations only. User data is never interpreted as code."""
import base64
import json
import os
import re
import subprocess
import sys

try:
    op = os.environ['OPERATION']
    name = os.environ['FILENAME']
    repo = os.environ['REPOSITORY']
    if op not in ('import', 'replace', 'append', 'delete'):
        raise ValueError('Unsupported operation')
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,99}', name) or name in ('.', '..'):
        raise ValueError('Use a simple filename, up to 100 letters, numbers, dots, hyphens or underscores')
    endpoint = 'repos/' + repo + '/contents/workspace/' + name
    def api(args, payload=None):
        proc = subprocess.run(['gh', 'api'] + args, input=json.dumps(payload) if payload else None,
                              text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return proc
    get = api([endpoint])
    if get.returncode:
        if op != 'import' or '404' not in get.stderr:
            raise ValueError('Cannot find or access the named file')
        existing = None
    else:
        existing = json.loads(get.stdout)
    if op == 'import':
        if existing is not None:
            raise ValueError('That filename already exists; choose another name')
        data = open('sample', 'rb').read(1048577)
        if len(data) > 1048576:
            raise ValueError('Text workspace files must be at most 1 MiB')
        data.decode('utf-8')
        if b'\0' in data:
            raise ValueError('Only UTF-8 text files are supported')
        payload = {'message': 'Import workspace text file', 'content': base64.b64encode(data).decode('ascii')}
        put = api(['--method', 'PUT', endpoint, '--input', '-'], payload)
    elif op in ('replace', 'append'):
        data = base64.b64decode(existing['content']).decode('utf-8')
        find = os.environ.get('FIND', '')
        replacement = os.environ.get('REPLACEMENT', '')
        if op == 'replace':
            if not find or find not in data:
                raise ValueError('Text to find is empty or was not found')
            new = data.replace(find, replacement).encode('utf-8')
        else:
            if not replacement:
                raise ValueError('Enter text to append')
            new = (data + replacement).encode('utf-8')
        if len(new) > 1048576:
            raise ValueError('Edited file exceeds 1 MiB')
        payload = {'message': 'Edit workspace text file', 'sha': existing['sha'], 'content': base64.b64encode(new).decode('ascii')}
        put = api(['--method', 'PUT', endpoint, '--input', '-'], payload)
    else:
        payload = {'message': 'Remove workspace text file', 'sha': existing['sha']}
        put = api(['--method', 'DELETE', endpoint, '--input', '-'], payload)
    if put.returncode:
        raise ValueError('GitHub rejected the update; check Actions permissions and retry after checking current state')
    print('RESULT: Workspace ' + op + ' completed for ' + name)
except Exception as exc:
    print('RESULT: Workspace operation failed: ' + str(exc))
    sys.exit(1)
