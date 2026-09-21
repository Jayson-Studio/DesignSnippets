import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('github_config', Path(__file__).parents[1] / 'scripts/configure-github.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class GitHubConfigTests(unittest.TestCase):
    def test_preview_allows_setup(self):
        self.assertEqual(module.validated_settings({}, {}), {'SemanticDeveloperSetupAllowed': True})

    def test_release_requires_both_identifiers(self):
        for config in ({}, {'clientID': 'Iv1.abc'}, {'appSlug': 'my-app'}):
            with self.assertRaises(ValueError):
                module.validated_settings(config, {'SEMANTIC_REQUIRE_GITHUB': '1'})

    def test_embedded_configuration_disables_setup(self):
        result = module.validated_settings({'clientID': ' Iv1.abc ', 'appSlug': ' my-app '}, {})
        self.assertEqual(result, {'SemanticGitHubClientID': 'Iv1.abc', 'SemanticGitHubAppSlug': 'my-app', 'SemanticDeveloperSetupAllowed': False})

    def test_environment_overrides_file(self):
        result = module.validated_settings({}, {'SEMANTIC_REQUIRE_GITHUB': '1', 'SEMANTIC_GITHUB_CLIENT_ID': 'Iv1.abc', 'SEMANTIC_GITHUB_APP_SLUG': 'my-app'})
        self.assertEqual(result['SemanticGitHubClientID'], 'Iv1.abc')

    def test_rejects_invalid_identifiers(self):
        for client, slug in [('12345', 'my-app'), ('Iv1.abc', 'https://github.com/apps/my-app'), ('Iv1.abc', '../bad')]:
            with self.assertRaises(ValueError):
                module.validated_settings({'clientID': client, 'appSlug': slug}, {})


if __name__ == '__main__':
    unittest.main()
