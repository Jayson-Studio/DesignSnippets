import importlib.util
import unittest
import base64
from pathlib import Path

spec = importlib.util.spec_from_file_location('config', Path(__file__).parents[1] / 'scripts/configure-updates.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class UpdateConfigTests(unittest.TestCase):
    def test_unconfigured_preview_is_disabled(self):
        self.assertEqual(module.validated_settings({}, {}), {})

    def test_unconfigured_release_fails(self):
        with self.assertRaises(ValueError):
            module.validated_settings({}, {'SEMANTIC_REQUIRE_UPDATES': '1'})

    def test_configured_release_verifies_downloads(self):
        config = {'feedURL': 'https://example.com/appcast.xml', 'publicKey': base64.b64encode(bytes(32)).decode()}
        settings = module.validated_settings(config, {'SEMANTIC_REQUIRE_UPDATES': '1'})
        self.assertTrue(settings['SUVerifyUpdateBeforeExtraction'])
        self.assertTrue(settings['SUEnableAutomaticChecks'])
        self.assertFalse(settings['SUAutomaticallyUpdate'])
        self.assertNotIn('privateKey', settings)

    def test_bad_feed_and_key_fail(self):
        for feed in ['http://example.com/feed', 'https://user:pass@example.com/feed', 'file:///tmp/feed']:
            with self.assertRaises(ValueError):
                module.validated_settings({'feedURL': feed, 'publicKey': base64.b64encode(bytes(32)).decode()}, {})
        with self.assertRaises(ValueError):
            module.validated_settings({'feedURL': 'https://example.com/feed', 'publicKey': 'invalid'}, {})

if __name__ == '__main__':
    unittest.main()
