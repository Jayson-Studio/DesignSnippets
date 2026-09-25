#!/usr/bin/env python3
"""Explicit, resumable production signing. Tests inject a fake command runner."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys

CONSENT = 'SEMANTIC_ALLOW_KEYCHAIN_PROMPTS'


def require_consent():
    if os.environ.get(CONSENT) != '1':
        raise ValueError(
            'Production signing is paused. No Keychain access was attempted. '
            f'Set {CONSENT}=1 only when you are ready for macOS signing prompts. '
            'See desktop/UPDATES.md for signing setup and recovery.')


def digest_tree(app, ignore_bytecode=False):
    digest = hashlib.sha256()
    for path in sorted(app.rglob('*')):
        if ignore_bytecode and ('__pycache__' in path.parts or path.suffix == '.pyc'):
            continue
        digest.update(str(path.relative_to(app)).encode() + b'\0')
        digest.update(str(path.lstat().st_mode).encode() + b'\0')
        if path.is_symlink():
            digest.update(os.readlink(path).encode())
        elif path.is_file():
            with path.open('rb') as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                    digest.update(chunk)
        digest.update(b'\0')
    return digest.hexdigest()


def source_digest():
    desktop = Path(__file__).resolve().parents[1]
    digest = hashlib.sha256()
    for name in ['Sources', 'Resources', 'scripts', 'github.json', 'updates.json']:
        path = desktop / name
        digest.update(name.encode())
        if path.is_dir():
            digest.update(digest_tree(path, ignore_bytecode=True).encode())
        else:
            digest.update(path.read_bytes())
    return digest.hexdigest()


def components(app):
    framework = app / 'Contents/Frameworks/Sparkle.framework'
    return [framework / relative for relative in (
        'Versions/B/XPCServices/Downloader.xpc',
        'Versions/B/XPCServices/Installer.xpc',
        'Versions/B/Autoupdate', 'Versions/B/Updater.app', '.',
    )] + [app]


def save_checkpoint(path, state, app):
    state['digest'] = digest_tree(app)
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(state, indent=2) + '\n')
    temporary.replace(path)


def sign_app(app, identity, run=subprocess.run):
    require_consent()  # Must precede every command, including verification.
    if not identity.startswith('Developer ID Application:'):
        raise ValueError('An explicit Developer ID Application identity is required.')
    app = Path(app).resolve()
    with (app / 'Contents/Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    for variable, key in [('SEMANTIC_VERSION', 'CFBundleShortVersionString'),
                          ('SEMANTIC_BUILD_NUMBER', 'CFBundleVersion')]:
        if os.environ.get(variable) and os.environ[variable] != str(info.get(key)):
            raise ValueError(f'{variable} does not match the staged app; rebuild instead.')
    checkpoint = app.parent / 'signing-state.json'
    with (app.parent / 'signing.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError('This staged app is already being signed.')
        state = {'identity': identity, 'completed': 0, 'source_digest': source_digest()}
        if checkpoint.exists():
            state = json.loads(checkpoint.read_text())
            if (state.get('identity') != identity or state.get('digest') != digest_tree(app)
                    or state.get('source_digest') != source_digest()):
                raise ValueError('Staged app, source files, or signing identity changed; refusing to reuse signing progress.')
            if type(state.get('completed')) is not int or not 0 <= state['completed'] <= 6:
                raise ValueError('Invalid signing checkpoint; rebuild instead.')
        targets = components(app)
        # Re-verify completed steps; a checkpoint alone is never proof of a valid seal.
        for target in targets[:state['completed']]:
            run(['/usr/bin/codesign', '--verify', '--strict', str(target)], check=True, timeout=120)
        for index in range(state['completed'], len(targets)):
            target = targets[index]
            print(f'Signing [{index + 1}/6]: {target.name}', flush=True)
            command = ['/usr/bin/codesign', '--force', '--sign', identity, '--options', 'runtime', '--timestamp']
            if target != app:
                command.append('--preserve-metadata=entitlements')
            try:
                run(command + [str(target)], check=True, timeout=120)
                run(['/usr/bin/codesign', '--verify', '--strict', str(target)], check=True, timeout=120)
            except (subprocess.SubprocessError, OSError):
                # codesign may have partially modified this component. Retry only
                # this incomplete step; already verified components are retained.
                save_checkpoint(checkpoint, state, app)
                raise
            state['completed'] = index + 1
            save_checkpoint(checkpoint, state, app)
        run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True, timeout=120)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', nargs='?')
    parser.add_argument('--identity', default=os.environ.get('SEMANTIC_SIGN_IDENTITY', ''))
    parser.add_argument('--check-consent', action='store_true')
    args = parser.parse_args()
    try:
        if args.check_consent:
            require_consent()
        elif args.app:
            sign_app(args.app, args.identity)
        else:
            parser.error('app is required')
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f'Signing stopped: {error}', file=sys.stderr)
        print('No automatic retry will run. Staged signing progress is retained.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
