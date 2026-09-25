import contextlib
import io
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('sign_app', Path(__file__).parents[1] / 'scripts/sign-app.py')
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)
IDENTITY = 'Developer ID Application: Test (EXAMPLE)'


class SigningTests(unittest.TestCase):
    def setUp(self):
        quiet = contextlib.redirect_stdout(io.StringIO())
        quiet.__enter__()
        self.addCleanup(quiet.__exit__, None, None, None)
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.app = Path(self.directory.name).resolve() / 'DesignSnippets.app'
        (self.app / 'Contents').mkdir(parents=True)
        with (self.app / 'Contents/Info.plist').open('wb') as stream:
            plistlib.dump({'CFBundleShortVersionString': '1.0.0', 'CFBundleVersion': '1'}, stream)
        self.environment = patch.dict(os.environ, {'SEMANTIC_ALLOW_KEYCHAIN_PROMPTS': '1',
                                                  'SEMANTIC_VERSION': '1.0.0', 'SEMANTIC_BUILD_NUMBER': '1'})
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def test_default_gate_runs_no_commands(self):
        calls = []
        with patch.dict(os.environ, {'SEMANTIC_ALLOW_KEYCHAIN_PROMPTS': '0'}):
            with self.assertRaisesRegex(ValueError, 'No Keychain access'):
                signing.sign_app(self.app, IDENTITY, run=lambda *a, **k: calls.append(a))
        self.assertEqual(calls, [])

    def test_failed_step_is_retried_without_resigning_successes(self):
        signed = []
        def fail_third(command, **kwargs):
            if '--sign' in command:
                signed.append(command[-1])
                if len(signed) == 3:
                    (self.app / 'partial-signature').write_text('partially changed by codesign')
                    raise subprocess.CalledProcessError(1, command)
        with self.assertRaises(subprocess.CalledProcessError):
            signing.sign_app(self.app, IDENTITY, run=fail_third)
        state = json.loads((self.app.parent / 'signing-state.json').read_text())
        self.assertEqual(state['completed'], 2)
        calls = []
        signing.sign_app(self.app, IDENTITY, run=lambda command, **kwargs: calls.append(command))
        targets = list(map(str, signing.components(self.app)))
        self.assertEqual([c[-1] for c in calls if '--sign' in c], targets[2:])
        self.assertEqual([c[-1] for c in calls[:2]], targets[:2])
        self.assertTrue(all('--verify' in c for c in calls[:2]))
        calls.clear()
        signing.sign_app(self.app, IDENTITY, run=lambda command, **kwargs: calls.append(command))
        self.assertFalse(any('--sign' in c for c in calls))
        self.assertIn('--deep', calls[-1])

    def test_changed_artifact_or_identity_cannot_reuse_checkpoint(self):
        signing.sign_app(self.app, IDENTITY, run=lambda *a, **k: None)
        for identity in ['Developer ID Application: Another (OTHER)', IDENTITY]:
            if identity == IDENTITY:
                (self.app / 'changed').write_text('changed after checkpoint')
            with self.assertRaisesRegex(ValueError, 'changed'):
                signing.sign_app(self.app, identity, run=lambda *a, **k: self.fail('must not invoke codesign'))

    def test_changed_sources_cannot_resume_old_app(self):
        signing.sign_app(self.app, IDENTITY, run=lambda *a, **k: None)
        with patch.object(signing, 'source_digest', return_value='different sources'):
            with self.assertRaisesRegex(ValueError, 'source files'):
                signing.sign_app(self.app, IDENTITY, run=lambda *a, **k: self.fail('must not invoke codesign'))

    def test_mismatched_release_version_never_signs(self):
        with patch.dict(os.environ, {'SEMANTIC_VERSION': '2.0.0'}):
            with self.assertRaisesRegex(ValueError, 'does not match'):
                signing.sign_app(self.app, IDENTITY, run=lambda *a, **k: self.fail('must not invoke codesign'))

    def test_verification_failure_never_skips_to_next_signing_step(self):
        def fail_verification(command, **kwargs):
            if '--verify' in command:
                raise subprocess.CalledProcessError(1, command)
        with self.assertRaises(subprocess.CalledProcessError):
            signing.sign_app(self.app, IDENTITY, run=fail_verification)
        state = json.loads((self.app.parent / 'signing-state.json').read_text())
        self.assertEqual(state['completed'], 0)

    def test_timeout_stops_without_retry(self):
        calls = []
        def timeout(command, **kwargs):
            calls.append(command)
            raise subprocess.TimeoutExpired(command, kwargs['timeout'])
        with self.assertRaises(subprocess.TimeoutExpired):
            signing.sign_app(self.app, IDENTITY, run=timeout)
        self.assertEqual(len(calls), 1)
        self.assertTrue((self.app.parent / 'signing-state.json').exists())

    def test_release_and_build_gate_before_keychain_access(self):
        root = Path(__file__).parents[2]
        with patch.dict(os.environ, {'SEMANTIC_ALLOW_KEYCHAIN_PROMPTS': '0', 'SEMANTIC_SIGN_IDENTITY': IDENTITY}):
            for script in ['release.sh', 'build.sh']:
                result = subprocess.run(['bash', str(root / 'desktop/scripts' / script)], capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('No Keychain access was attempted', result.stderr)


if __name__ == '__main__':
    unittest.main()
