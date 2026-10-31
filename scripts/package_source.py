#!/usr/bin/env python3
"""Package only allowlisted first-party SOURCE files with a SHA-256 manifest.

This is intentionally NOT a generic directory ZIP: CMake build outputs,
sanitizer binaries, local credentials and untracked files must never leak into
a shared source checkpoint.

Usage: python3 scripts/package_source.py /mnt/data/MixAuto-source.zip
"""
from __future__ import annotations
import hashlib
import pathlib
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
ALLOWED_ROOT_FILES = {'README.md', 'CMakeLists.txt', 'project.yml', '.gitignore'}
ALLOWED_AREAS = {
    'ios/App': {'.swift', '.h', '.plist'},
    'ios/UITests': {'.swift'},
    'ios/IntegrationTests': {'.swift'},
    'native/AudioCore': {'.cpp', '.h', '.txt'},
    'tests': {'.swift', '.cpp', '.py'},
    'tools': {'.cpp'},
    'docs': {'.md'},
    'scripts': {'.sh', '.py'},
    '.github/workflows': {'.yml', '.yaml'},
}
PREFIX = 'DJ-TrackBuilder-MixAuto-Pro'


def is_approved_source(file: pathlib.Path) -> bool:
    if not file.is_file() or file.is_symlink():
        return False
    try:
        relative = file.relative_to(ROOT)
    except ValueError:
        return False
    if file.resolve().is_relative_to(ROOT.resolve()) is False:
        return False
    if len(relative.parts) == 1:
        return relative.name in ALLOWED_ROOT_FILES
    for area, suffixes in ALLOWED_AREAS.items():
        base = pathlib.PurePosixPath(area)
        parts = base.parts
        if relative.parts[:len(parts)] == parts and len(relative.parts) > len(parts):
            return file.suffix in suffixes
    return False


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit('Usage: package_source.py <destination.zip>')
    destination = pathlib.Path(sys.argv[1]).expanduser().resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    files = sorted(p for p in ROOT.rglob('*') if is_approved_source(p)
                   and p.resolve() != destination)
    for required in ('project.yml', 'README.md',
                     'native/AudioCore/TrackAudioCore.cpp',
                     'ios/App/AudioController.swift',
                     'tests/AudioRoutePolicyTests.swift'):
        assert ROOT / required in files, f'Missing required source: {required}'
    manifest = []
    with zipfile.ZipFile(destination, 'w', compression=zipfile.ZIP_DEFLATED,
                         compresslevel=9) as archive:
        for file in files:
            content = file.read_bytes()
            rel = file.relative_to(ROOT).as_posix()
            info = zipfile.ZipInfo(f'{PREFIX}/{rel}')
            info.date_time = (2026, 10, 28, 0, 0, 0)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = (0o644 << 16)
            archive.writestr(info, content, compress_type=zipfile.ZIP_DEFLATED,
                             compresslevel=9)
            manifest.append(f'{hashlib.sha256(content).hexdigest()}  {rel}')
        info = zipfile.ZipInfo(f'{PREFIX}/SOURCE_SHA256SUMS.txt')
        info.date_time = (2026, 10, 28, 0, 0, 0)
        info.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(info, ('\n'.join(manifest)+'\n').encode())
    with zipfile.ZipFile(destination) as archive:
        failure = archive.testzip()
        if failure:
            raise RuntimeError(f'Archive integrity failed at {failure}')
    digest = hashlib.sha256(destination.read_bytes()).hexdigest()
    print(f'{destination}\n{len(files)} source/config/doc files; ZIP={destination.stat().st_size} bytes')
    print(f'SHA256 {digest}')
    print('Approved-source-only ZIP; no Xcode/simulator/iPhone verification implied')


if __name__ == '__main__':
    main()
