#!/usr/bin/env python3
"""Generate the first-release database from an isolated copy of verified old source."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
from datetime import datetime
from zoneinfo import ZoneInfo

REPO = Path(__file__).resolve().parents[2]


def file_hashes(root):
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in root.rglob('*') if p.is_file()
            and not any(part in ('.git', 'build') for part in p.relative_to(root).parts)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--old-source', type=Path, required=True)
    parser.add_argument('--work-dir', type=Path, required=True)
    parser.add_argument('--output-bundle', type=Path, required=True, help='New output path; never overwrites a fixture')
    parser.add_argument('--runtime', default='com.apple.CoreSimulator.SimRuntime.iOS-26-3')
    args = parser.parse_args()
    original = args.old_source.resolve()
    output = args.output_bundle.resolve()
    if output.exists():
        raise RuntimeError('Output already exists; choose a new path')
    reference_bundle = REPO / 'DoCardTests/Fixtures/Upgrade1301.bundle'
    reference = json.loads((reference_bundle / 'provenance.json').read_text())
    for expected in reference['sourceModelFiles']:
        actual = hashlib.sha256((original / expected['path']).read_bytes()).hexdigest()
        if actual != expected['sha256']:
            raise RuntimeError('Old model/opener source does not match the verified baseline: ' + expected['path'])
    before = file_hashes(original)
    args.work_dir.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='writer-', dir=args.work_dir.resolve()))
    isolated = work / 'old-source'
    shutil.copytree(original, isolated, ignore=shutil.ignore_patterns('.git', 'build', '.claude', '.agents', '.codex', '.DS_Store', '*.pdf'))
    tests = isolated / 'DoCardTests'
    tests.mkdir(exist_ok=True)
    shutil.copy2(REPO / 'scripts/upgrade1301/Upgrade1301WriterTests.swift', tests)
    shutil.copy2(REPO / 'DoCardTests/Upgrade1301Spec.swift', tests)
    resource = tests / 'Upgrade1301.bundle'
    resource.mkdir()
    for name in ['Info.plist', 'expected.json']:
        shutil.copy2(reference_bundle / name, resource / name)
    project = isolated / 'DoCard.xcodeproj/project.pbxproj'
    text = project.read_text()
    group = ('\t\tFACE1301FACE1301FACE1301 /* DoCardTests */ = {\n'
             '\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n\t\t\tpath = DoCardTests;\n'
             '\t\t\tsourceTree = "<group>";\n\t\t};\n')
    text = text.replace('/* End PBXFileSystemSynchronizedRootGroup section */', group + '/* End PBXFileSystemSynchronizedRootGroup section */')
    anchor = '\t\t801B208C2CB363A10073E9E2 = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n'
    if text.count(anchor) != 1 or text.count('\t\t\tname = DoCardTests;') != 1:
        raise RuntimeError('Old project structure changed; review writer registration')
    text = text.replace(anchor, anchor + '\t\t\t\tFACE1301FACE1301FACE1301 /* DoCardTests */,\n')
    text = text.replace('\t\t\tname = DoCardTests;', '\t\t\tfileSystemSynchronizedGroups = (\n\t\t\t\tFACE1301FACE1301FACE1301 /* DoCardTests */,\n\t\t\t);\n\t\t\tname = DoCardTests;')
    project.write_text(text)
    device = subprocess.check_output(['xcrun', 'simctl', 'create', 'DO Card 1301 Fixture Writer',
                                     'com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro', args.runtime], text=True).strip()
    print(f'Writer work directory: {work}', flush=True)
    print(f'Isolated simulator: {device}', flush=True)
    try:
        subprocess.run(['xcrun', 'simctl', 'boot', device], check=True)
        subprocess.run(['xcrun', 'simctl', 'bootstatus', device, '-b'], check=True)
        command = ['xcodebuild', 'test', '-project', 'DoCard.xcodeproj', '-scheme', 'DoCard',
                   '-destination', f'platform=iOS Simulator,id={device}', '-derivedDataPath', str(work / 'DerivedData'),
                   '-resultBundlePath', str(work / 'writer.xcresult'),
                   '-only-testing:DoCardTests/Upgrade1301WriterTests', '-parallel-testing-enabled', 'NO',
                   'CODE_SIGNING_ALLOWED=NO']
        with (work / 'writer.log').open('w') as log:
            completed = subprocess.run(command, cwd=isolated, stdout=log, stderr=subprocess.STDOUT)
        summary = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary',
                                                     '--path', str(work / 'writer.xcresult'), '--compact']))
        (work / 'writer-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
        if completed.returncode != 0 or summary['passedTests'] != 1 or summary['failedTests'] or summary['skippedTests']:
            raise RuntimeError(f'Old writer failed: {work / "writer.log"}')
        built = plistlib.loads((work / 'DerivedData/Build/Products/Debug-iphonesimulator/DoCard.app/Info.plist').read_bytes())
        if built['CFBundleShortVersionString'] != '1.30.1' or built['CFBundleVersion'] != '1':
            raise RuntimeError('Writer app is not configured as verified 1.30.1 build 1')
        ready = re.search(r'UPGRADE1301_SEED_READY: (.+)', (work / 'writer.log').read_text())
        if not ready:
            raise RuntimeError('Writer did not report a saved-data directory')
        seed = Path(ready[1].strip())
        if f'/Devices/{device}/' not in str(seed):
            raise RuntimeError('Seed path is outside the isolated simulator')
        states = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', '--json']))
        state = next(d['state'] for group in states['devices'].values() for d in group if d['udid'] == device)
        if state == 'Booted':
            subprocess.run(['xcrun', 'simctl', 'shutdown', device], check=True)
        elif state != 'Shutdown':
            raise RuntimeError('Writer simulator is not fully stopped')
        output.mkdir(parents=True)
        shutil.copytree(seed, output / 'Store')
        for name in ['Info.plist', 'expected.json']:
            shutil.copy2(resource / name, output / name)
        metadata = plistlib.loads((output / 'Store/source-store-metadata.plist').read_bytes())
        provenance = dict(reference)
        device_info = summary['devicesAndConfigurations'][0]['device']
        provenance.update(generatedDateTaipei=datetime.now(ZoneInfo('Asia/Taipei')).date().isoformat(),
                          generatedRuntime=f"iOS Simulator {device_info['osVersion']} ({device_info['osBuildNumber']})",
                          xcode=subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
                          storeFiles=file_hashes(output / 'Store'),
                          generatorSourceSHA256=hashlib.sha256((tests / 'Upgrade1301WriterTests.swift').read_bytes()).hexdigest(),
                          expectedDataSHA256=hashlib.sha256((output / 'expected.json').read_bytes()).hexdigest(),
                          generatedAppVersion=built['CFBundleShortVersionString'], generatedAppBuild=built['CFBundleVersion'],
                          oldStoreSchemaVersion=metadata['NSStoreModelVersionIdentifiers'][0],
                          writerResult='1 passed, 0 failed, 0 skipped')
        (output / 'provenance.json').write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + '\n')
        print(f'Fixture generated: {output}', flush=True)
    finally:
        # Only the temporary device created by this invocation is removed.
        subprocess.run(['xcrun', 'simctl', 'shutdown', device], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(['xcrun', 'simctl', 'delete', device], check=True)
        after = file_hashes(original)
        if before != after:
            raise RuntimeError('Historical source changed during generation; investigate before proceeding')
        (work / 'historical-source-check.json').write_text(json.dumps({'filesChecked': len(before), 'unchanged': True}, indent=2) + '\n')
        print(f'Historical source unchanged: {len(before)} files checked', flush=True)


if __name__ == '__main__':
    main()
