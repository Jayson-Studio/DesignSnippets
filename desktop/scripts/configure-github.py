#!/usr/bin/env python3
"""Validate and embed public GitHub App identifiers before signing."""
import json
import os
import plistlib
import re
import sys
from pathlib import Path


def validated_settings(config, env):
    client = env.get('SEMANTIC_GITHUB_CLIENT_ID', config.get('clientID', '')).strip()
    slug = env.get('SEMANTIC_GITHUB_APP_SLUG', config.get('appSlug', '')).strip()
    required = env.get('SEMANTIC_REQUIRE_GITHUB') == '1'
    if not client and not slug and not required:
        return {'SemanticDeveloperSetupAllowed': True}
    if not re.fullmatch(r'Iv[a-zA-Z0-9_.-]+', client) or not re.fullmatch(r'[a-zA-Z0-9]+(?:-[a-zA-Z0-9]+)*', slug):
        raise ValueError('Set a valid public GitHub App clientID and appSlug in desktop/github.json or SEMANTIC_GITHUB_CLIENT_ID / SEMANTIC_GITHUB_APP_SLUG. Release builds cannot use developer setup.')
    return {'SemanticGitHubClientID': client, 'SemanticGitHubAppSlug': slug,
            'SemanticDeveloperSetupAllowed': False}


def main():
    config = json.loads((Path(__file__).resolve().parents[1] / 'github.json').read_text())
    settings = validated_settings(config, os.environ)
    if sys.argv[1:] == ['--check']:
        return
    path = Path(sys.argv[1])
    info = plistlib.loads(path.read_bytes())
    for key in ('SemanticGitHubClientID', 'SemanticGitHubAppSlug', 'SemanticDeveloperSetupAllowed'):
        info.pop(key, None)
    info.update(settings)
    path.write_bytes(plistlib.dumps(info))


if __name__ == '__main__':
    try:
        main()
    except ValueError as error:
        sys.exit(str(error))
