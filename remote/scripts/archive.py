"""Inspect ZIPs and copy members to fixed remote paths; never execute them."""
import hashlib
import json
import os
import shutil
import stat
import sys
import unicodedata
import zipfile

MAX_ARCHIVE = 10 * 1024 * 1024
MAX_MEMBER = 25 * 1024 * 1024
MAX_TOTAL = 100 * 1024 * 1024
MAX_ENTRIES = 1000
MAX_RATIO = 100


def validate(info, seen):
    name = info.filename
    if (not name or info.orig_filename != name or len(name) > 1024 or name.startswith('/') or '\\' in name
            or any(unicodedata.category(c) in ('Cc', 'Cf') for c in name)
            or any(part in ('.', '..') for part in name.split('/'))
            or any(not part or part.endswith((' ', '.')) or any(c in '<>:"|?*' for c in part)
                   or part.split('.')[0].upper() in {'CON', 'PRN', 'AUX', 'NUL',
                       *(f'COM{i}' for i in '123456789¹²³'), *(f'LPT{i}' for i in '123456789¹²³')}
                   for part in name.rstrip('/').split('/'))):
        raise ValueError('Archive contains an unsafe entry name')
    folded = unicodedata.normalize('NFC', name.rstrip('/')).casefold()
    if folded in seen:
        raise ValueError('Archive contains duplicate or case-colliding entry names')
    seen.add(folded)
    if info.flag_bits & 1:
        raise ValueError('Encrypted archives are not supported')
    if stat.S_ISLNK(info.external_attr >> 16):
        raise ValueError('Archives containing symbolic links are not supported')
    if info.create_system == 3:
        kind = stat.S_IFMT(info.external_attr >> 16)
        if kind and kind not in (stat.S_IFREG, stat.S_IFDIR):
            raise ValueError('Special file types are not supported')
    if info.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
        raise ValueError('Only stored or deflated entries are supported')
    if info.file_size > MAX_MEMBER:
        raise ValueError('An entry exceeds 25 MiB')
    if info.file_size and (not info.compress_size or info.file_size > MAX_RATIO * info.compress_size):
        raise ValueError('An entry exceeds the 100:1 compression ratio limit')


try:
    operation = os.environ['OPERATION']
    target = os.environ.get('ENTRY', '')
    if operation not in ('inspect', 'remove', 'extract'):
        raise ValueError('Unsupported archive operation')
    if os.path.getsize('sample') > MAX_ARCHIVE:
        raise ValueError('ZIP file exceeds 10 MiB')
    os.mkdir('archive-output')
    with zipfile.ZipFile('sample') as source:
        infos = source.infolist()
        if len(infos) > MAX_ENTRIES:
            raise ValueError('ZIP contains more than 1000 entries')
        seen = set()
        total = 0
        for info in infos:
            validate(info, seen)
            total += info.file_size
            if total > MAX_TOTAL:
                raise ValueError('ZIP expands beyond 100 MiB')
        types = {unicodedata.normalize('NFC', i.filename.rstrip('/')).casefold(): i.is_dir() for i in infos}
        for name in types:
            segments = name.split('/')
            if any('/'.join(segments[:n]) in types and not types['/'.join(segments[:n])]
                   for n in range(1, len(segments))):
                raise ValueError('Archive contains a file and folder path collision')
        if operation in ('remove', 'extract') and (not target or target not in [i.filename for i in infos] or target.endswith('/')):
            raise ValueError('Specify the exact name of a file in the archive')
        report = {'entries': [{'name': i.filename, 'size': i.file_size, 'compressed_size': i.compress_size}
                              for i in infos], 'expanded_bytes': total, 'operation': operation,
                  'selected': target if operation in ('remove', 'extract') else None}
        with open('archive-output/inventory.json', 'w', encoding='utf-8') as out:
            json.dump(report, out, ensure_ascii=True, indent=2)
        for entry in report['entries']:
            print('ZIP_ENTRY: ' + json.dumps(entry, ensure_ascii=True, separators=(',', ':')))
        if operation == 'remove':
            with zipfile.ZipFile('archive-output/edited.zip', 'w') as output:
                for info in infos:
                    if info.filename == target:
                        continue
                    clean = zipfile.ZipInfo(info.filename, date_time=info.date_time)
                    clean.compress_type = info.compress_type
                    clean.create_system = 3
                    clean.external_attr = ((stat.S_IFDIR | 0o755) << 16 | 0x10) if info.is_dir() else ((stat.S_IFREG | 0o644) << 16)
                    with source.open(info) as reader, output.open(clean, 'w') as writer:
                        shutil.copyfileobj(reader, writer, length=65536)
            with zipfile.ZipFile('archive-output/edited.zip') as edited:
                if edited.namelist() != [i.filename for i in infos if i.filename != target] or edited.testzip() is not None:
                    raise ValueError('Edited ZIP failed verification')
            with open('archive-output/edited.zip', 'rb') as data:
                digest = hashlib.file_digest(data, 'sha256').hexdigest()
            print('Edited ZIP SHA-256: ' + digest)
        elif operation == 'extract':
            original_digest = hashlib.sha256()
            with source.open(target) as reader, open('archive-output/selected-file.bin', 'wb') as output:
                while chunk := reader.read(65536):
                    original_digest.update(chunk)
                    output.write(chunk)
            with open('archive-output/selected-file.bin', 'rb') as data:
                digest = hashlib.file_digest(data, 'sha256').hexdigest()
            if digest != original_digest.hexdigest():
                raise ValueError('Copied file failed integrity verification')
            print('Selected file SHA-256: ' + digest)
    print('Archive processing completed; uploading output')
except Exception as exc:
    print('RESULT: Archive operation failed: ' + str(exc))
    sys.exit(1)
