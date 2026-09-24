#!/usr/bin/env python3
"""Allocate from GitHub releases and the existing feed, before a serialized local release."""
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'


def next_release(pages, feed):
    versions = []
    for page in pages:
        for release in page:
            match = re.fullmatch(r'v(\d+)\.(\d+)\.(\d+)', release['tag_name'])
            if match:
                # Include drafts so failed publication never overwrites artifacts.
                versions.append(tuple(map(int, match.groups())))
    if not versions:
        raise ValueError('No versioned releases found; seed the initial release manually.')
    items = ET.fromstring(feed).findall('./channel/item')
    builds = [item.findtext(f'{SPARKLE}version') for item in items]
    if not builds or any(not value or not value.isdigit() for value in builds):
        raise ValueError('Existing update feed must contain positive integer build numbers.')
    if min(map(int, builds)) < 1:
        raise ValueError('Build numbers must be positive.')
    major, minor, patch = max(versions)
    return f'{major}.{minor}.{patch + 1}', max(map(int, builds)) + 1


if __name__ == '__main__':
    version, build = next_release(json.loads(Path(sys.argv[1]).read_text()), Path(sys.argv[2]).read_text())
    print(f'SEMANTIC_VERSION={version}')
    print(f'SEMANTIC_BUILD_NUMBER={build}')
