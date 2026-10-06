import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

class CloudCoverageTest(unittest.TestCase):
    def run_hook(self, workflow, *, missing=False, failed_test=False, fail_gate=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shutil.copy(ROOT / 'ci_scripts/ci_post_xcodebuild.sh', root / 'hook.sh')
            (root / 'bundle').mkdir()
            (root / 'check_coverage.sh').write_text('echo "$COVERAGE_TARGET:$COVERAGE_THRESHOLD" >> "$CALLS"\nif [[ "$FAIL_GATE" == 1 ]]; then exit 7; fi\n')
            env = {**os.environ, 'CI_XCODEBUILD_ACTION': 'test-without-building',
                   'CI_WORKFLOW': workflow, 'CI_XCODEBUILD_EXIT_CODE': '1' if failed_test else '0',
                   'CI_RESULT_BUNDLE_PATH': str(root / ('missing' if missing else 'bundle')),
                   'CALLS': str(root / 'calls'), 'FAIL_GATE': '1' if fail_gate else '0'}
            result = subprocess.run(['bash', str(root / 'hook.sh')], env=env, capture_output=True)
            calls = (root / 'calls').read_text().splitlines() if (root / 'calls').exists() else []
            return result.returncode, calls

    def test_current_and_legacy_names_preserve_thresholds(self):
        for name in ('VolumeArc Main', 'VOL Main'):
            self.assertEqual(self.run_hook(name), (0, ['VolumeArcCore:80', 'VolumeArcUI:2']))
        for name in ('VolumeArc PR', 'VOL PR'):
            self.assertEqual(self.run_hook(name), (0, ['VolumeArcCore:0']))

    def test_unknown_missing_and_failing_coverage_block(self):
        for name in ('', 'Renamed Main'):
            self.assertNotEqual(self.run_hook(name)[0], 0)
        self.assertNotEqual(self.run_hook('VolumeArc Main', missing=True)[0], 0)
        self.assertEqual(self.run_hook('VolumeArc Main', fail_gate=True)[0], 7)
        self.assertEqual(self.run_hook('VolumeArc Main', missing=True, failed_test=True), (0, []))

if __name__ == '__main__':
    unittest.main()
