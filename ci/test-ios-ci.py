"""Check the real CI shell script using controlled Xcode/simulator responses."""

import copy
import json
import os
import re
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
SUITES = {"ScheduleTests": 36, "UnlockRecoveryTests": 28, "SessionHistoryTests": 8,
          "SessionReportTests": 7, "SessionReportDurationTests": 1,
          "SubscriptionAccessTests": 12, "EntitlementsTests": 2, "SelectionRulesTests": 4,
          "SelectionEnforcementTests": 1, "SubscriptionLifecycleTests": 20,
          "SubscriptionStoreTests": 4, "SubscriptionRefreshTests": 1, "SettingsLayoutTests": 15,
          "AppUpdateTests": 8, "AppUpdateNetworkTests": 9}


def tree_for(suites):
    return {"testNodes": [{"nodeType": "Unit test bundle", "name": "DoCardTests", "children": [
        {"nodeType": "Test Suite", "name": suite, "children": [
            {"nodeType": "Test Case", "nodeIdentifier": f"{suite}/{method}()", "result": "Passed"}
            for method in re.findall(r"^  func (test\w+)\(",
                (ROOT / "DoCardTests" / f"{suite}.swift").read_text(), re.MULTILINE)]}
        for suite in suites]}]}


SUMMARY = {"result": "Passed", "totalTestCount": sum(SUITES.values()),
           "passedTests": sum(SUITES.values()), "failedTests": 0, "skippedTests": 0,
           "expectedFailures": 0}
TREE = tree_for(SUITES)
STOREKIT_SUMMARY = {**SUMMARY, "totalTestCount": 4, "passedTests": 4}
STOREKIT_TREE = tree_for(["StoreKitAccessTests"])

UPGRADE_SUMMARY = {**SUMMARY, 'totalTestCount': 1, 'passedTests': 1}
UPGRADE_TREE = {'testNodes': [{'nodeType': 'Unit test bundle', 'name': 'DoCardTests', 'children': [
    {'nodeType': 'Test Suite', 'name': 'Upgrade1301Tests', 'children': [
        {'nodeType': 'Test Case',
         'nodeIdentifier': 'Upgrade1301Tests/testFirstReleaseSavedDataSurvivesUpdate()',
         'result': 'Passed'}]}]}]}

XCRUN = '''import json, os, pathlib, sys
args = sys.argv[1:]
fixture = pathlib.Path(os.environ['CI_FIXTURE_DIR'])
with (fixture / 'commands.jsonl').open('a') as output:
    output.write(json.dumps(['xcrun'] + args) + '\\n')
if args[:3] == ['simctl', 'list', 'runtimes']:
    print(json.dumps({'runtimes':[{'identifier':'test-runtime','isAvailable':True}]}))
elif args[:3] == ['simctl', 'list', 'devices']:
    print(json.dumps({'devices': {'test-runtime': [{'udid': 'fixture-simulator', 'state': 'Booted'}]}}))
elif args[:2] == ['simctl', 'create']:
    print('fixture-simulator')
elif args[:3] == ['xcresulttool', 'get', 'test-results']:
    name = 'test-summary.json' if args[3] == 'summary' else 'test-tree.json'
    phase = pathlib.Path(args[args.index('--path') + 1]).stem
    if phase in ['migrate', 'reopen']:
        name = phase + '-' + name
    elif phase.startswith('storekit-'):
        name = 'storekit-' + name
    print((fixture / name).read_text())
'''
XCODEBUILD = '''import json, os, pathlib, plistlib, sys
args = sys.argv[1:]
fixture = pathlib.Path(os.environ['CI_FIXTURE_DIR'])
with (fixture / 'commands.jsonl').open('a') as output:
    output.write(json.dumps(['xcodebuild'] + args) + '\\n')
if args == ['-version']:
    print('Controlled Xcode response')
elif args[0] == 'build-for-testing':
    products = pathlib.Path(args[args.index('-derivedDataPath') + 1]) / 'Build/Products'
    products.mkdir(parents=True)
    template = {'TestConfigurations': [{'TestTargets': [{'BlueprintName': 'DoCardTests'}]}]}
    (products / 'DoCard_DoCard_test.xctestrun').write_bytes(plistlib.dumps(template))
    print('** TEST BUILD SUCCEEDED **')
elif args[0] in ['test', 'test-without-building']:
    phase = pathlib.Path(args[args.index('-resultBundlePath') + 1]).stem
    pathlib.Path(args[args.index('-resultBundlePath') + 1]).mkdir()
    if phase in ['migrate', 'reopen']:
        config = plistlib.loads(pathlib.Path(args[args.index('-xctestrun') + 1]).read_bytes())
        mode = config['TestConfigurations'][0]['TestTargets'][0]['EnvironmentVariables']['DOCARD_UPGRADE_PHASE']
        assert mode == phase
        marker = json.loads(os.environ['SIMULATED_MARKERS'])[phase]
        if marker:
            print(marker)
        sys.exit(int(os.environ['SIMULATED_' + phase.upper() + '_STATUS']))
    selected = [arg for arg in args if arg.startswith('-only-testing:')]
    expected = (['StoreKitAccessTests'] if phase.startswith('storekit-')
                else json.loads(os.environ['EXPECTED_DETERMINISTIC_SUITES']))
    assert sorted(selected) == sorted('-only-testing:DoCardTests/' + suite for suite in expected)
    assert args[args.index('-parallel-testing-enabled') + 1] == 'NO'
    if phase.startswith('storekit-'):
        pathlib.Path(fixture, 'storekit-called').touch()
        sys.exit(int(os.environ['SIMULATED_STOREKIT_STATUS']))
    sys.exit(int(os.environ['SIMULATED_TEST_STATUS']))
elif args[0] == 'build':
    pathlib.Path(os.environ['CI_FIXTURE_DIR'], 'release-called').touch()
    if os.environ['SIMULATED_RELEASE_STATUS'] == '0':
        print('** BUILD SUCCEEDED **')
    sys.exit(int(os.environ['SIMULATED_RELEASE_STATUS']))
'''


class PipelineChecks(unittest.TestCase):
    def run_pipeline(self, summary=None, tree=None, test_status=0, release_status=0,
                     upgrade=None, markers=None, migrate_status=0, reopen_status=0,
                     storekit_summary=None, storekit_tree=None, storekit_status=0):
        with tempfile.TemporaryDirectory(prefix="docard-ci-guard-") as temporary:
            fixture = Path(temporary)
            binary = fixture / 'bin'
            binary.mkdir()
            for name, body in [('xcrun', XCRUN), ('xcodebuild', XCODEBUILD)]:
                path = binary / name
                path.write_text(f'#!{sys.executable}\n' + body)
                path.chmod(0o755)
            for name, value in [('test-summary.json', SUMMARY if summary is None else summary),
                                ('test-tree.json', TREE if tree is None else tree)]:
                (fixture / name).write_text(value if isinstance(value, str) else json.dumps(value))
            for kind, value in [('summary', STOREKIT_SUMMARY if storekit_summary is None else storekit_summary),
                                ('tree', STOREKIT_TREE if storekit_tree is None else storekit_tree)]:
                (fixture / ('storekit-test-' + kind + '.json')).write_text(
                    value if isinstance(value, str) else json.dumps(value))
            for phase in ['migrate', 'reopen']:
                for kind, default in [('summary', UPGRADE_SUMMARY), ('tree', UPGRADE_TREE)]:
                    value = (upgrade or {}).get(phase + '-' + kind, default)
                    (fixture / (phase + '-test-' + kind + '.json')).write_text(
                        value if isinstance(value, str) else json.dumps(value))
            results = fixture / 'results'
            results.mkdir()
            # A prior success must not hide this invocation's failure.
            (results / 'ci-passed').touch()
            (results / 'release.log').write_text('** BUILD SUCCEEDED **')
            (results / 'upgrade-results.json').write_text(json.dumps({
                'result': 'Passed', 'phases': {}, 'errors': []}))
            env = {**os.environ, 'PATH': str(binary) + os.pathsep + os.environ['PATH'],
                   'CI_FIXTURE_DIR': str(fixture), 'CI_RESULTS_DIR': str(results),
                   'CI_BUILD_DIR': str(fixture / 'build'), 'CI_SIMULATOR_RUNTIME': 'test-runtime',
                   'EXPECTED_DETERMINISTIC_SUITES': json.dumps(list(SUITES)),
                   'SIMULATED_STOREKIT_STATUS': str(storekit_status),
                   'SIMULATED_TEST_STATUS': str(test_status),
                   'SIMULATED_MIGRATE_STATUS': str(migrate_status),
                   'SIMULATED_REOPEN_STATUS': str(reopen_status),
                   'SIMULATED_MARKERS': json.dumps(markers if markers is not None else {
                       'migrate': 'UPGRADE1301_RESULT: phase=migrate, pid=101',
                       'reopen': 'UPGRADE1301_RESULT: phase=reopen, pid=202'}),
                   'SIMULATED_RELEASE_STATUS': str(release_status)}
            run = subprocess.run(['bash', str(ROOT / 'ci/run-ios-ci.sh')], env=env,
                                 capture_output=True, text=True)
            rendered = subprocess.run([sys.executable, str(ROOT / 'ci/ios-ci-summary.py'), str(results)],
                                      capture_output=True, text=True, check=True)
            self.storekit_called = (fixture / 'storekit-called').exists()
            self.commands = [json.loads(line) for line in (fixture / 'commands.jsonl').read_text().splitlines()]
            return (run.returncode, (fixture / 'release-called').exists(),
                    (results / 'ci-passed').exists(), rendered.stdout)

    def assert_blocked(self, **kwargs):
        status, release_called, marker, report = self.run_pipeline(**kwargs)
        self.assertNotEqual(status, 0)
        self.assertFalse(release_called)
        self.assertFalse(marker)
        self.assertIn('Release simulator build: **not reached**', report)

    def test_complete_run_reaches_release_and_reports_all_suites(self):
        status, release_called, marker, report = self.run_pipeline()
        self.assertEqual(status, 0)
        self.assertTrue(release_called)
        self.assertTrue(marker)
        self.assertIn('| ScheduleTests | 36 | 36 | 36 | 0 | 0 |', report)
        self.assertIn('| UnlockRecoveryTests | 28 | 28 | 28 | 0 | 0 |', report)
        for suite, count in {**SUITES, 'StoreKitAccessTests': 4}.items():
            self.assertIn(f'| {suite} | {count} | {count} | {count} | 0 | 0 |', report)
        self.assertIn('| migrate | Passed | 101 |', report)
        self.assertIn('| reopen | Passed | 202 |', report)
        builds = [args[1] for args in self.commands if args[0] == 'xcodebuild']
        self.assertEqual(builds.count('build-for-testing'), 1)
        self.assertEqual(builds.count('test-without-building'), 4)
        self.assertNotIn('test', builds)
        self.assertNotIn('erase', [arg for command in self.commands for arg in command])
        deleted = [args for args in self.commands if args[:3] == ['xcrun', 'simctl', 'delete']]
        self.assertEqual(deleted, [['xcrun', 'simctl', 'delete', 'fixture-simulator']])

    def test_deterministic_failure_stops_before_storekit(self):
        self.assert_blocked(test_status=65)
        self.assertFalse(self.storekit_called)

    def test_storekit_incomplete_or_failed_results_block_release(self):
        for result in ['Failed', 'Skipped']:
            tree = copy.deepcopy(STOREKIT_TREE)
            tree['testNodes'][0]['children'][0]['children'][0]['result'] = result
            with self.subTest(result=result):
                self.assert_blocked(storekit_tree=tree)
        self.assert_blocked(storekit_tree={'testNodes': []})
        self.assert_blocked(storekit_summary='invalid json')
        self.assert_blocked(storekit_status=65)

    def test_wrong_storekit_method_blocks_release(self):
        tree = copy.deepcopy(STOREKIT_TREE)
        tree['testNodes'][0]['children'][0]['children'][0]['nodeIdentifier'] = 'StoreKitAccessTests/other()'
        self.assert_blocked(storekit_tree=tree)

    def test_upgrade_failure_or_missing_results_blocks_release(self):
        self.assert_blocked(migrate_status=65)

    def test_reopen_failure_blocks_release(self):
        self.assert_blocked(reopen_status=65)

    def test_zero_skipped_failed_or_missing_upgrade_results_block_release(self):
        for phase in ['migrate', 'reopen']:
            skipped = copy.deepcopy(UPGRADE_TREE)
            skipped['testNodes'][0]['children'][0]['children'][0]['result'] = 'Skipped'
            failed = copy.deepcopy(UPGRADE_TREE)
            failed['testNodes'][0]['children'][0]['children'][0]['result'] = 'Failed'
            for values in [
                {phase + '-summary': {**UPGRADE_SUMMARY, 'totalTestCount': 0, 'passedTests': 0}},
                {phase + '-tree': skipped},
                {phase + '-tree': failed},
                {phase + '-tree': {'testNodes': []}},
                {phase + '-summary': 'missing result'},
                {phase + '-summary': {**UPGRADE_SUMMARY, 'expectedFailures': 1}},
            ]:
                with self.subTest(phase=phase, values=values):
                    self.assert_blocked(upgrade=values)

    def test_reopen_requires_a_new_process_and_correct_phase(self):
        for reopen in [None, 'UPGRADE1301_RESULT: phase=reopen, pid=101',
                       'UPGRADE1301_RESULT: phase=migrate, pid=202']:
            with self.subTest(reopen=reopen):
                self.assert_blocked(markers={
                    'migrate': 'UPGRADE1301_RESULT: phase=migrate, pid=101', 'reopen': reopen})

    def test_wrong_regression_method_blocks_release_with_unchanged_counts(self):
        tree = copy.deepcopy(TREE)
        tree['testNodes'][0]['children'][0]['children'][0]['nodeIdentifier'] = 'ScheduleTests/notARealTest()'
        self.assert_blocked(tree=tree)

    def test_wrong_upgrade_method_blocks_release(self):
        tree = copy.deepcopy(UPGRADE_TREE)
        tree['testNodes'][0]['children'][0]['children'][0]['nodeIdentifier'] = 'Upgrade1301Tests/other()'
        self.assert_blocked(upgrade={'reopen-tree': tree})

    def test_missing_suite_cannot_be_replaced_by_extra_schedule_tests(self):
        tree = copy.deepcopy(TREE)
        tree['testNodes'][0]['children'] = [suite for suite in tree['testNodes'][0]['children']
                                            if suite['name'] != 'UnlockRecoveryTests']
        children = tree['testNodes'][0]['children'][0]['children']
        children.extend({'nodeType': 'Test Case', 'nodeIdentifier': f'ScheduleTests/extra{n}()',
                         'result': 'Passed'} for n in range(28))
        self.assert_blocked(tree=tree)

    def test_missing_new_suite_blocks_release_even_with_passing_summary(self):
        for name in list(SUITES)[2:]:
            with self.subTest(suite=name):
                tree = copy.deepcopy(TREE)
                tree['testNodes'][0]['children'] = [suite for suite in tree['testNodes'][0]['children']
                                                    if suite['name'] != name]
                self.assert_blocked(tree=tree)

    def test_failed_or_skipped_new_case_blocks_release(self):
        for name in list(SUITES)[2:]:
            for result in ['Failed', 'Skipped']:
                with self.subTest(suite=name, result=result):
                    tree = copy.deepcopy(TREE)
                    suite = next(s for s in tree['testNodes'][0]['children'] if s['name'] == name)
                    suite['children'][0]['result'] = result
                    self.assert_blocked(tree=tree)

    def test_old_63_test_run_cannot_satisfy_expanded_gate(self):
        tree = copy.deepcopy(TREE)
        tree['testNodes'][0]['children'] = tree['testNodes'][0]['children'][:2]
        self.assert_blocked(tree=tree, summary={**SUMMARY, 'totalTestCount': 63, 'passedTests': 63})

    def test_skipped_case_blocks_release_even_with_passing_summary(self):
        tree = copy.deepcopy(TREE)
        tree['testNodes'][0]['children'][1]['children'][0]['result'] = 'Skipped'
        self.assert_blocked(tree=tree)

    def test_failed_case_blocks_release_even_with_successful_command(self):
        tree = copy.deepcopy(TREE)
        tree['testNodes'][0]['children'][1]['children'][0]['result'] = 'Failed'
        self.assert_blocked(tree=tree)

    def test_command_failure_is_preserved_even_with_passing_results(self):
        status, release_called, marker, _ = self.run_pipeline(test_status=65)
        self.assertEqual(status, 65)
        self.assertFalse(release_called)
        self.assertFalse(marker)

    def test_unreadable_results_block_release(self):
        for values in [{'summary': 'broken json'}, {'tree': 'broken json'}]:
            with self.subTest(values=values):
                self.assert_blocked(**values)

    def test_zero_tests_block_release(self):
        self.assert_blocked(tree={'testNodes': []})

    def test_duplicate_tests_block_release(self):
        tree = copy.deepcopy(TREE)
        children = tree['testNodes'][0]['children'][1]['children']
        children[1] = copy.deepcopy(children[0])
        self.assert_blocked(tree=tree)

    def test_failed_summary_blocks_release_even_with_passing_tree(self):
        self.assert_blocked(summary={**SUMMARY, 'result': 'Failed', 'failedTests': 1})

    def test_release_failure_does_not_write_success_marker(self):
        status, release_called, marker, _ = self.run_pipeline(release_status=65)
        self.assertEqual(status, 65)
        self.assertTrue(release_called)
        self.assertFalse(marker)


if __name__ == '__main__':
    unittest.main(verbosity=2)
