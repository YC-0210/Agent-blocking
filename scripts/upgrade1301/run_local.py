#!/usr/bin/env python3
"""Build the reader, test migration, reopen in a new process, and optionally prove a failure."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import sqlite3
import subprocess
import tempfile
import time

REPO = Path(__file__).resolve().parents[2]
SELECTION = 'DoCardTests/Upgrade1301Tests'


def run(command, log):
    with log.open('w') as output:
        completed = subprocess.run(command, cwd=REPO, stdout=output, stderr=subprocess.STDOUT)
    return completed.returncode


def boot(device):
    devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', '--json']))
    found = next(d for group in devices['devices'].values() for d in group if d['udid'] == device)
    if found['state'] == 'Booted':
        subprocess.run(['xcrun', 'simctl', 'shutdown', device], check=True)
    subprocess.run(['xcrun', 'simctl', 'boot', device], check=True)
    subprocess.run(['xcrun', 'simctl', 'bootstatus', device, '-b'], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--simulator', required=True, help='A dedicated simulator UUID; no data is erased')
    parser.add_argument('--derived-data', required=True, type=Path)
    parser.add_argument('--results', required=True, type=Path, help='A new directory for this run')
    parser.add_argument('--source-packages', type=Path)
    parser.add_argument('--skip-build', action='store_true')
    parser.add_argument('--prove-failure', action='store_true')
    args = parser.parse_args()
    results = args.results.resolve()
    results.mkdir(parents=True, exist_ok=False)
    derived = args.derived_data.resolve()
    destination = f'platform=iOS Simulator,id={args.simulator}'
    bundle = REPO / 'DoCardTests/Fixtures/Upgrade1301.bundle'
    provenance = json.loads((bundle / 'provenance.json').read_text())
    for filename, expected in provenance['storeFiles'].items():
        actual = hashlib.sha256((bundle / 'Store' / filename).read_bytes()).hexdigest()
        if actual != expected:
            raise RuntimeError(f'Original old-store fixture changed: {filename}')
    if not args.skip_build:
        command = ['xcodebuild', 'build-for-testing', '-project', 'DoCard.xcodeproj', '-scheme', 'DoCard',
                   '-destination', destination, '-derivedDataPath', str(derived), 'CODE_SIGNING_ALLOWED=NO']
        if args.source_packages:
            command += ['-clonedSourcePackagesDirPath', str(args.source_packages.resolve())]
        if run(command, results / 'build.log') != 0:
            raise RuntimeError(f'Reader build failed; see {results / "build.log"}')
    products = derived / 'Build/Products'
    templates = list(products.glob('DoCard_DoCard_*.xctestrun'))
    if len(templates) != 1:
        raise RuntimeError('Expected one DoCard test-run file from build-for-testing')
    template = plistlib.loads(templates[0].read_bytes())
    outcomes = {}
    temporary_configs = []

    def phase(name, mode, expect_failure=False, host=None):
        started = time.monotonic()
        data = copy.deepcopy(template)
        for configuration in data['TestConfigurations']:
            for target in configuration['TestTargets']:
                if target['BlueprintName'] == 'DoCardTests':
                    target.setdefault('EnvironmentVariables', {})['DOCARD_UPGRADE_PHASE'] = mode
                    if host is not None:
                        target['TestHostPath'] = str(host)
        # Keep __TESTROOT__ relative to the original build products, per Xcode's xctestrun format.
        with tempfile.NamedTemporaryFile(dir=products, prefix='Upgrade1301-', suffix='.xctestrun', delete=False) as f:
            config = Path(f.name)
            f.write(plistlib.dumps(data))
        temporary_configs.append(config)
        boot(args.simulator)
        result = results / f'{name}.xcresult'
        code = run(['xcodebuild', 'test-without-building', '-xctestrun', str(config),
                    '-destination', destination, '-resultBundlePath', str(result),
                    '-only-testing:' + SELECTION, '-parallel-testing-enabled', 'NO'], results / f'{name}.log')
        summary = json.loads(subprocess.check_output(
            ['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(result), '--compact']))
        (results / f'{name}-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
        tree = subprocess.check_output(
            ['xcrun', 'xcresulttool', 'get', 'test-results', 'tests', '--path', str(result), '--compact'])
        (results / f'{name}-tree.json').write_bytes(tree)
        text = (results / f'{name}.log').read_text()
        marker = re.search(r'UPGRADE1301_RESULT: phase=(\w+), pid=(\d+)', text)
        outcomes[name] = {'exitCode': code, 'result': summary['result'], 'total': summary['totalTestCount'],
                          'passed': summary['passedTests'], 'failed': summary['failedTests'],
                          'skipped': summary['skippedTests'], 'processID': int(marker[2]) if marker else None,
                          'expectedFailure': expect_failure, 'wallSeconds': round(time.monotonic() - started, 3)}
        (results / 'results.json').write_text(json.dumps(outcomes, indent=2) + '\n')
        if expect_failure:
            # Require the intended field mismatch, not a build/launch/missing-file failure.
            failures = json.dumps(summary.get('testFailures', []))
            valid = (code != 0 and summary['totalTestCount'] == 1 and summary['failedTests'] == 1
                     and summary['skippedTests'] == 0 and 'Altered Work' in failures)
        else:
            valid = (code == 0 and summary['result'] == 'Passed' and summary['totalTestCount'] == 1
                     and summary['passedTests'] == 1 and summary['failedTests'] == 0
                     and summary['skippedTests'] == 0 and summary['expectedFailures'] == 0
                     and marker is not None and marker[1] == mode)
        if not valid:
            raise RuntimeError(f'{name} did not meet its expected result. See {results / (name + ".log")}')
        print(name + ': ' + ('deliberate mismatch caught' if expect_failure else 'passed'), flush=True)

    try:
        phase('migrate', 'migrate')
        phase('reopen', 'reopen')
        if outcomes['migrate']['processID'] == outcomes['reopen']['processID']:
            raise RuntimeError('Reopen did not use a new process')
        if args.prove_failure:
            host = results / 'deliberate-error/DoCard.app'
            shutil.copytree(products / 'Debug-iphonesimulator/DoCard.app', host)
            store = host / 'PlugIns/DoCardTests.xctest/Upgrade1301.bundle/Store/default.store'
            # Mutate one artificial record only in a disposable built-app copy.
            # The real fixture, expected values, schema and version markers are unchanged.
            with sqlite3.connect(store) as db:
                changed = db.execute("UPDATE ZBLOCKEDPROFILES SET ZNAME=? WHERE ZNAME=?", ('Altered Work', 'Work'))
                if changed.rowcount != 1:
                    raise RuntimeError('Could not set up the deliberate data mismatch')
            phase('deliberate-error', 'migrate', expect_failure=True, host=host)
            phase('final-migrate', 'migrate')
        for filename, expected in provenance['storeFiles'].items():
            if hashlib.sha256((bundle / 'Store' / filename).read_bytes()).hexdigest() != expected:
                raise RuntimeError('The original fixture changed during the run')
        print(f'Results: {results / "results.json"}', flush=True)
    finally:
        for config in temporary_configs:
            config.unlink(missing_ok=True)


if __name__ == '__main__':
    main()
