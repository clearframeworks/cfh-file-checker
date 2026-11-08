"""Report OSV results conservatively, including incomplete coverage."""
import json
import os
import re
import sys

try:
    code = int(os.environ['OSV_EXIT'])
    warnings = os.path.getsize('osv.err') > 0
    if warnings:
        with open('osv.err', 'rb') as stream:
            warning_text = stream.read(4096).decode('utf-8', errors='replace')
        print('SCANNER_WARNING: ' + json.dumps(warning_text, ensure_ascii=True))
    if code == 128:
        print('RESULT: No supported dependencies were identified; dependency coverage is unknown')
        sys.exit(0)
    if code not in (0, 1):
        sys.exit('RESULT: Dependency scanner failed; coverage unknown')
    with open('osv.json', 'rb') as stream:
        data = stream.read(5 * 1024 * 1024 + 1)
    if len(data) > 5 * 1024 * 1024:
        sys.exit('RESULT: Dependency report exceeded limit; coverage unknown')
    report = json.loads(data)
    packages = [p for result in report.get('results', []) for p in result.get('packages', [])]
    ids = sorted({v.get('id', '') for package in packages for v in package.get('vulnerabilities', [])
                  if re.fullmatch(r'[A-Za-z0-9._-]{1,120}', v.get('id', ''))})
    print('Packages reported: ' + str(len(packages)))
    print('Advisory identifiers: ' + (', '.join(ids[:100]) if ids else 'none reported'))
    for package in packages:
        advisories = [v.get('id', '') for v in package.get('vulnerabilities', [])
                      if re.fullmatch(r'[A-Za-z0-9._-]{1,120}', v.get('id', ''))]
        if advisories:
            metadata = package.get('package', {})
            finding = {'package': str(metadata.get('name', ''))[:200], 'version': str(metadata.get('version', ''))[:100],
                       'ecosystem': str(metadata.get('ecosystem', ''))[:100], 'advisories': advisories[:100]}
            print('FINDING: ' + json.dumps(finding, ensure_ascii=True, separators=(',', ':')))
    if code == 1 and warnings:
        print('RESULT: Dependency findings reported; scanner warnings mean coverage is incomplete.')
    elif warnings:
        print('RESULT: Dependency scanner reported warnings; coverage is incomplete. Review the run.')
    elif code == 1:
        print('RESULT: Dependency findings reported. Review advisory details and applicability.')
    elif not packages:
        print('RESULT: No packages reported; dependency coverage is unknown.')
    else:
        print('RESULT: No known dependency findings in scanned lockfiles; this does not establish safety.')
except Exception:
    sys.exit('RESULT: Dependency report could not be validated; coverage unknown')
