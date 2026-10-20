"""Run only offline AI on the hosted Mac; keep graphics evidence with artifacts."""
import json
import subprocess
import shutil
import time
from pathlib import Path

out = Path('dist')
out.mkdir(exist_ok=True)
log = Path.home() / 'Library/Logs/Wyrm/engine.log'
try:
    result = subprocess.run(['build/Wyrm.app/Contents/MacOS/Wyrm', '--smoke-ai'], timeout=60)
    code = result.returncode
except subprocess.TimeoutExpired:
    code = -1
text = log.read_text(errors='replace') if log.exists() else 'No engine log produced.'
(out / 'ci-smoke.log').write_text(text)
passed = code == 0 and 'WYRM_MAC_SMOKE_OK' in text
(out / 'ci-smoke.json').write_text(json.dumps({'passed': passed, 'exitCode': code,
    'scope': 'Hosted Mac offline AI; physical Mac and online gameplay not tested'}, indent=2))
print('Hosted Mac offline AI:', 'PASS (120 presented frames)' if passed else 'NOT VERIFIED; see ci-smoke.log')
if not passed:
    time.sleep(3)
    reports = Path.home() / 'Library/Logs/DiagnosticReports'
    for report in reports.glob('Wyrm*'):
        if report.is_file():
            shutil.copyfile(report, out/report.name)
    gpu = subprocess.run(['system_profiler', 'SPDisplaysDataType', '-json'], capture_output=True, text=True)
    (out/'graphics.json').write_text(gpu.stdout)
    print(text[-5000:])
    raise SystemExit(1)
