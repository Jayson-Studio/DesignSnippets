import base64
import importlib.util
from pathlib import Path
import tempfile
import unittest


def load(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).parents[1] / 'scripts' / f'{name}.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


next_release = load('next-release').next_release
verify = load('verify-release').verify
NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'


def feed(build='17', version='0.3.10', url='https://example.com/app.zip', size=3):
    signature = base64.b64encode(bytes(64)).decode()
    return f'''<rss xmlns:sparkle="{NS}"><channel><item>
    <sparkle:version>{build}</sparkle:version>
    <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
    <enclosure url="{url}" length="{size}" sparkle:edSignature="{signature}" />
    </item></channel></rss>'''


class ReleaseTests(unittest.TestCase):
    def test_numeric_order_and_paginated_drafts(self):
        pages = [[{'tag_name': 'v0.3.9'}, {'tag_name': 'v0.3.10'}],
                 [{'tag_name': 'v0.3.11', 'draft': True}, {'tag_name': 'v1.0.0-beta'}]]
        self.assertEqual(next_release(pages, feed()), ('0.3.12', 18))

    def test_major_minor_are_preserved(self):
        self.assertEqual(next_release([[{'tag_name': 'v2.4.0'}]], feed('99')), ('2.4.1', 100))

    def test_missing_release_fails_closed(self):
        with self.assertRaises(ValueError):
            next_release([[]], feed())

    def test_bad_build_fails_closed(self):
        for build in ['', '0', '-1', '17.1', 'text']:
            with self.subTest(build=build), self.assertRaises(ValueError):
                next_release([[{'tag_name': 'v0.3.10'}]], feed(build))

    def test_missing_items_fails_closed(self):
        with self.assertRaises(ValueError):
            next_release([[{'tag_name': 'v0.3.10'}]], '<rss><channel /></rss>')

    def test_metadata_must_match_archive_and_version(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / 'app.zip'
            archive.write_bytes(b'zip')
            verify(archive, feed(), '0.3.10', '17', 'https://example.com/')
            for invalid in [feed(build='18'), feed(version='0.3.11'),
                            feed(url='https://wrong.example/app.zip'), feed(size=4),
                            feed().replace(base64.b64encode(bytes(64)).decode(), '')]:
                with self.subTest(feed=invalid), self.assertRaises(ValueError):
                    verify(archive, invalid, '0.3.10', '17', 'https://example.com/')


if __name__ == '__main__':
    unittest.main()
