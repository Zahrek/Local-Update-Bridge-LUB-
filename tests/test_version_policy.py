"""Exercises the actual Foundation-only Swift classification code extracted from the app."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'LocalUpdateBridge.swift'

class VersionPolicyTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('swiftc'), 'Swift compiler unavailable')
    def test_version_classification(self):
        source = SOURCE.read_text()
        start = source.index('// BEGIN TESTABLE VERSION POLICY')
        end = source.index('// END TESTABLE VERSION POLICY') + len('// END TESTABLE VERSION POLICY')
        policy = source[start:end]
        cases = '''
import Foundation
''' + policy + '''
func expect(_ got: LUBVersionPolicy.Result, _ expected: LUBVersionPolicy.Result, _ name: String) {
    guard got == expected else { fatalError("\\(name): expected \\(expected), got \\(got)") }
}
func check(package: String, installed: String?, knownVersions: [String], matchesActiveReceipt: Bool, activeFilesChanged: Bool = false) -> LUBVersionPolicy.Result {
    LUBVersionPolicy.decide(package: package, installed: installed, knownVersions: knownVersions, matchesActiveReceipt: matchesActiveReceipt, activeFilesChanged: activeFilesChanged)
}
expect(check(package: "1.3.1", installed: "1.3.2", knownVersions: ["1.3.2"], matchesActiveReceipt: false), .old, "previous with receipt")
expect(check(package: "1.3.1", installed: nil, knownVersions: ["1.3.2"], matchesActiveReceipt: false), .old, "previous without receipt")
expect(check(package: "1.3.2", installed: nil, knownVersions: ["1.3.2"], matchesActiveReceipt: false), .available, "latest unknown installed")
expect(check(package: "1.3.3", installed: "1.3.2", knownVersions: ["1.3.3", "1.3.2"], matchesActiveReceipt: false), .newer, "genuinely newer")
expect(check(package: "1.3.2", installed: "1.3.2", knownVersions: ["1.3.2"], matchesActiveReceipt: true), .current, "active receipt")
expect(check(package: "1.3.2", installed: "1.3.2", knownVersions: ["1.3.2"], matchesActiveReceipt: true, activeFilesChanged: true), .modified, "changed active files")
expect(check(package: "1.3.2", installed: "1.3.3", knownVersions: ["1.3.2"], matchesActiveReceipt: false), .old, "older even with only old ZIP present")
expect(check(package: "1.2.0", installed: "1.2.0", knownVersions: ["1.3.0"], matchesActiveReceipt: true), .current, "intentional downgrade active")
expect(LUBVersionPolicy.compare("1.3.10", "1.3.9") == .orderedDescending ? .current : .old, .current, "numeric versions")
expect(check(package: "1.3.2", installed: "1.3.2", knownVersions: [], matchesActiveReceipt: false), .available, "same name no receipt")
print("PASS: 10 Swift release-classification scenarios")
'''
        with tempfile.TemporaryDirectory(prefix='lub-version-tests-') as folder:
            test_file = Path(folder) / 'main.swift'
            exe = Path(folder) / 'policy-check'
            test_file.write_text(cases)
            subprocess.run(['swiftc', str(test_file), '-o', str(exe)], check=True, capture_output=True, text=True)
            run = subprocess.run([str(exe)], check=True, capture_output=True, text=True)
            self.assertIn('10 Swift', run.stdout)

if __name__ == '__main__':
    unittest.main()