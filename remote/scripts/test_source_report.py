"""Confirm scan outcomes do not turn missing coverage or errors into success."""
import json
import os
import pathlib
import subprocess
import sys
import tempfile

script = pathlib.Path(__file__).with_name('source_report.py').resolve()

def check(code, report, warning, expected, successful=True):
    with tempfile.TemporaryDirectory() as directory:
        root = pathlib.Path(directory)
        (root / 'osv.json').write_text(json.dumps(report), encoding='utf-8')
        (root / 'osv.err').write_text(warning, encoding='utf-8')
        result = subprocess.run([sys.executable, str(script)], cwd=root, env=dict(os.environ, OSV_EXIT=str(code)), capture_output=True, text=True)
        assert (result.returncode == 0) == successful, result.stdout + result.stderr
        assert expected in result.stdout + result.stderr, result.stdout + result.stderr

package = {'package': {'name': 'example', 'version': '1.0', 'ecosystem': 'Go'}, 'vulnerabilities': []}
clean = {'results': [{'packages': [package]}]}
check(0, clean, '', 'No known dependency findings')
check(0, {'results': []}, '', 'coverage is unknown')
check(128, {}, '', 'coverage is unknown')
check(127, {}, '', 'scanner failed', successful=False)
package['vulnerabilities'] = [{'id': 'GO-2026-1234'}]
check(1, clean, '', 'Dependency findings reported')
check(1, clean, 'warning', 'coverage is incomplete')
print('Synthetic source report outcome tests passed.')
