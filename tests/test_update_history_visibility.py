"""Checks GUI-list wiring after the repeated historical-version regression.

SwiftUI cannot be built in Linux CI; these checks assert that the key UI logic
actually uses the version status logic and displays history by default.
"""
from pathlib import Path
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / "LocalUpdateBridge.swift")

class VersionHistoryUIWiring(unittest.TestCase):
    def setUp(self):
        self.source = SOURCE.read_text()

    def test_history_is_not_hidden_by_default(self):
        self.assertIn("@Published var latestOnly = false", self.source)
        self.assertIn('Toggle("Hide old versions", isOn: $bridge.latestOnly)', self.source)
        self.assertIn("guard latestOnly else { return true }", self.source)

    def test_legacy_receipts_are_discovered(self):
        self.assertIn('root.appendingPathComponent("Update Bridge/Backups"', self.source)
        self.assertIn('bridgeRoot.appendingPathComponent("Backups"', self.source)

    def test_version_classifier_connected_to_visible_rows(self):
        self.assertIn('let state = bridge.releaseState(candidate)', self.source)
        self.assertIn('Text(bridge.releaseLabel(candidate))', self.source)
        self.assertIn('case .previouslyInstalled, .older: return "Old Version"', self.source)
        self.assertIn('.opacity(bridge.isMutedRelease(candidate) ? 0.60 : 1)', self.source)

    def test_rollback_requires_backup(self):
        self.assertIn('if bridge.projectRollbackBackup(for: candidate) != nil', self.source)
        self.assertIn('Text("Backup Unavailable")', self.source)
        self.assertIn('if canRollbackLUB(item) { requestLUBRollback(item) }', self.source)

if __name__ == "__main__":
    unittest.main()