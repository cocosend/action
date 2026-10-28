"""Regression tests for reproducible source-only ZIP distribution."""
import hashlib
import importlib.util
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import zipfile


def main():
    root = Path(__file__).resolve().parents[1]
    spec = importlib.util.spec_from_file_location('mixauto_package',
                                                   root / 'scripts/package_source.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert not module.is_approved_source(root / '.build-sanitized/CMakeCache.txt')
    assert not module.is_approved_source(root / '.build/track_audio_core_tests')
    assert not module.is_approved_source(root / 'secrets.env')
    assert not module.is_approved_source(root / '.github/private-token.txt')
    assert module.is_approved_source(root / 'ios/App/AudioController.swift')
    assert module.is_approved_source(root / 'tests/AudioRoutePolicyTests.swift')
    assert module.is_approved_source(root / 'ios/UITests/DJTrackBuilderUITests.swift')
    assert module.is_approved_source(root / 'ios/IntegrationTests/AudioGraphIntegrationTests.swift')
    with TemporaryDirectory() as td:
        destination = Path(td) / 'test-source.zip'
        old_args = sys.argv
        try:
            sys.argv = ['package_source.py', str(destination)]
            module.main()
        finally:
            sys.argv = old_args
        with zipfile.ZipFile(destination) as z:
            assert z.testzip() is None
            names = z.namelist()
            assert len(names) > 55
            assert all('/.build' not in n and '/.git/' not in n
                       and 'token' not in n.lower() and 'secrets' not in n.lower()
                       and not n.endswith(('.o', '.ipa', '.app', '.a')) for n in names)
            rows = z.read(f'{module.PREFIX}/SOURCE_SHA256SUMS.txt').decode().splitlines()
            assert len(rows) == len(names) - 1
            for row in rows:
                digest, rel = row.split('  ', 1)
                assert digest == hashlib.sha256(z.read(f'{module.PREFIX}/{rel}')).hexdigest()
    print('SourcePackagingTests PASS — no build binaries/credentials; all per-file SHA256 match')


if __name__ == '__main__':
    main()
