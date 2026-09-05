"""Run a small catalog of existing tests without changing their result semantics."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent


def contained(root, relative):
    path = (root / relative).resolve()
    if Path(relative).is_absolute() or not path.is_relative_to(root):
        raise ValueError(f'Path must stay inside repository: {relative}')
    return path


def selection(root, suite):
    files = []
    for selector in suite['selectors']:
        path = contained(root, selector)
        matches = sorted(path.rglob('*_test.dart')) if path.is_dir() else [path]
        if not matches or not all(item.is_file() for item in matches):
            raise ValueError(f'Missing file or empty selection: {selector}')
        for item in matches:
            if not item.resolve().is_relative_to(root):
                raise ValueError(f'Test outside repository: {item}')
        files.extend(matches)
    if not files:
        raise ValueError('Suite has no tests')
    return sorted(set(files))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('suite', nargs='?')
    parser.add_argument('--list', action='store_true')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--flutter', default='flutter', help='Flutter executable, including flutter.bat on Windows')
    parser.add_argument('--root', type=Path, default=HERE.parents[2])
    parser.add_argument('--manifest', type=Path, default=HERE / 'suites.json')
    args = parser.parse_args()
    try:
        manifest = json.loads(args.manifest.read_text(encoding='utf-8-sig'))
        suites = manifest['suites']
        root = args.root.resolve()
        if args.list:
            for name, suite in suites.items():
                files = selection(root, suite)
                print(f'{name}: {suite.get("purpose", "")} ({len(files)} files)')
            return 0
        if args.suite not in suites:
            raise ValueError(f'Unknown suite: {args.suite!r}; use --list')
        suite = suites[args.suite]
        files = selection(root, suite)
        cwd = contained(root, suite['cwd'])
        if not cwd.is_dir():
            raise ValueError(f'Missing working directory: {cwd}')
        if suite['engine'] == 'flutter':
            selectors = [str(contained(root, selector)) for selector in suite['selectors']]
            command = [args.flutter, 'test', '--no-pub', *selectors, '--reporter', 'expanded']
        elif suite['engine'] == 'python':
            command = [sys.executable, '-B', '-m', 'unittest', *[str(path.relative_to(cwd)) for path in files]]
        else:
            raise ValueError(f'Unknown engine: {suite["engine"]}')
        print(f'Suite: {args.suite}; mode: raw pass/fail; cwd: {cwd}', flush=True)
        print('Files:\n' + '\n'.join(path.relative_to(root).as_posix() for path in files), flush=True)
        print('Command argv: ' + json.dumps(command), flush=True)
        if args.dry_run:
            print('Dry run only; SDK and test results not verified.')
            return 0
        if suite['engine'] == 'flutter':
            version = subprocess.run([args.flutter, '--version', '--machine'], cwd=cwd,
                                     capture_output=True, text=True)
            if version.returncode:
                print(version.stdout, end='')
                print(version.stderr, end='', file=sys.stderr)
                return version.returncode
            actual = json.loads(version.stdout)['frameworkVersion']
            if actual != manifest['flutter_version']:
                raise ValueError(f'Expected Flutter {manifest["flutter_version"]}, got {actual}')
        return subprocess.run(command, cwd=cwd).returncode
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f'handoff: {error}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
