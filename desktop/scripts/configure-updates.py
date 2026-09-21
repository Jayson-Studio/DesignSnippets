#!/usr/bin/env python3
"""Embed public updater settings. Private signing material never enters the app."""
import base64
import json
import os
import plistlib
import sys
from urllib.parse import urlsplit
from pathlib import Path


def validated_settings(config, env):
    feed = env.get('SEMANTIC_UPDATE_FEED_URL', config.get('feedURL', '')).strip()
    key = env.get('SEMANTIC_UPDATE_PUBLIC_KEY', config.get('publicKey', '')).strip()
    if not feed:
        if env.get('SEMANTIC_REQUIRE_UPDATES') == '1':
            raise ValueError('Set the public HTTPS feedURL in desktop/updates.json before releasing.')
        return {}
    parsed = urlsplit(feed)
    if parsed.scheme != 'https' or not parsed.hostname or parsed.username is not None or parsed.password is not None or parsed.fragment:
        raise ValueError('The update feed must be a public HTTPS URL without embedded credentials or a fragment.')
    try:
        decoded = base64.b64decode(key, validate=True)
    except ValueError as error:
        raise ValueError('Invalid public update signing key.') from error
    if len(decoded) != 32:
        raise ValueError('The public update signing key must decode to 32 bytes.')
    return {'SUFeedURL': feed, 'SUPublicEDKey': key, 'SUEnableAutomaticChecks': True,
            'SUAutomaticallyUpdate': False, 'SUSendProfileInfo': False, 'SUVerifyUpdateBeforeExtraction': True}


def main():
    config = json.loads(Path('desktop/updates.json').read_text())
    settings = validated_settings(config, os.environ)
    path = Path(sys.argv[1])
    info = plistlib.loads(path.read_bytes())
    info.update(settings)
    info['CFBundleShortVersionString'] = os.environ.get('SEMANTIC_VERSION', '0.3.0')
    info['CFBundleVersion'] = os.environ.get('SEMANTIC_BUILD_NUMBER', '7')
    path.write_bytes(plistlib.dumps(info))
    print('In-app updates configured.' if settings else 'Development build: update feed not configured.')


if __name__ == '__main__':
    main()
