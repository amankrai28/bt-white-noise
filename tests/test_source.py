"""Non-disruptive tests: never launch the app or change audio routing."""
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / 'scripts/bt-white-noise'

class SourceTests(unittest.TestCase):
    def test_shell_syntax(self):
        for script in (ROOT/'scripts').iterdir():
            subprocess.run(['/bin/zsh', '-n', str(script)], check=True)

    def test_plist(self):
        with (ROOT/'resources/Info.plist').open('rb') as stream:
            self.assertEqual(plistlib.load(stream)['CFBundleExecutable'], 'BTWhiteNoise')

    def test_helper_isolated_state(self):
        with tempfile.TemporaryDirectory() as home:
            env = dict(os.environ, HOME=home)
            def run(*args):
                return subprocess.run([str(HELPER), *args], env=env, text=True, capture_output=True)
            self.assertEqual(run('status').stdout.strip(), 'off')
            self.assertEqual(run('type').stdout.strip(), 'white')
            self.assertEqual(run('select', 'invalid').returncode, 4)
            self.assertEqual(run('select', 'brown').returncode, 5)
            self.assertFalse((Path(home)/'.bt-white-noise-type').exists())
            folder=Path(home)/'Library/Application Support/BT White Noise'
            folder.mkdir(parents=True, exist_ok=True)
            (folder/'brown.wav').touch()
            self.assertEqual(run('select', 'brown').returncode, 0)
            self.assertEqual(run('type').stdout.strip(), 'brown')

    def test_no_machine_identifiers(self):
        import re
        for folder in ('src', 'scripts', 'resources'):
            for path in (ROOT/folder).iterdir():
                content=path.read_text()
                self.assertNotIn('/Users/', content)
                self.assertIsNone(re.search(r'(?i)(?:[0-9a-f]{2}-){5}[0-9a-f]{2}', content))
                self.assertNotIn('sia', content.lower())
                self.assertNotIn('dipster', content.lower())

if __name__ == '__main__':
    unittest.main()
