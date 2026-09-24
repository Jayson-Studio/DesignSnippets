#!/usr/bin/env python3
"""Fail before publication if generated update metadata points at the wrong build."""
import base64
import os
import sys
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'


def verify(archive, feed, version, build, prefix):
    items = ET.fromstring(feed).findall('./channel/item')
    if len(items) != 1:
        raise ValueError('Expected exactly one release in the generated feed.')
    item = items[0]
    enclosure = item.find('enclosure')
    if (item.findtext(f'{SPARKLE}version') != build
            or item.findtext(f'{SPARKLE}shortVersionString') != version
            or enclosure is None
            or enclosure.get('url') != prefix + archive.name
            or enclosure.get('length') != str(archive.stat().st_size)):
        raise ValueError('Update metadata does not match the release archive/version.')
    signature = base64.b64decode(enclosure.get(f'{SPARKLE}edSignature', ''), validate=True)
    if len(signature) != 64:
        raise ValueError('Missing or invalid Sparkle signature.')


if __name__ == '__main__':
    archive = Path(sys.argv[1])
    feed = Path(sys.argv[2]).read_text()
    verify(archive, feed, os.environ['SEMANTIC_VERSION'],
           os.environ['SEMANTIC_BUILD_NUMBER'], os.environ['SEMANTIC_DOWNLOAD_URL_PREFIX'])
    signature = ET.fromstring(feed).find('./channel/item/enclosure').get(f'{SPARKLE}edSignature')
    subprocess.run(['xcrun', 'swift', '-module-cache-path', 'desktop/build/module-cache',
                    'desktop/scripts/verify-update-signature.swift', str(archive), signature], check=True)
