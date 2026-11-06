#!/usr/bin/env python3
"""Check prerequisites without modifying Xcode, signing, permissions or the phone."""
import argparse
import pathlib
import plistlib
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--profile", required=True, type=pathlib.Path)
args = parser.parse_args()

probe = """
import FamilyControls
import ManagedSettings
func probe() async throws {
  if #available(iOS 26.4, *) {
    guard AuthorizationCenter.shared.authorizationStatus == .approvedWithDataAccess else { return }
    let selected = Set<ApplicationToken>()
    for application in try await FamilyActivityData.shared.installedApplications {
      guard let token = application.token, selected.contains(token),
        let identifier = application.bundleIdentifier else { continue }
      _ = identifier
    }
  }
}
"""
try:
    sdk = subprocess.check_output(
        ["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True,
        stderr=subprocess.DEVNULL).strip()
except (OSError, subprocess.CalledProcessError):
    print("SDK unavailable — open Xcode, accept its license and finish installing required components.")
    raise SystemExit(1)
with tempfile.TemporaryDirectory(prefix="docard-icon-sdk-") as directory:
    source = pathlib.Path(directory) / "Probe.swift"
    source.write_text(probe)
    result = subprocess.run([
        "xcrun", "--sdk", "iphoneos", "swiftc", "-typecheck", "-sdk", sdk,
        "-target", "arm64-apple-ios18.0", str(source)
    ], capture_output=True, text=True)
sdk_ok = result.returncode == 0
print("SDK API compilation:", "PASS" if sdk_ok else "FAIL — install/select Xcode with the iOS 26.4+ APIs")

profile_ok = False
try:
    decoded = subprocess.run(["security", "cms", "-D", "-i", str(args.profile)],
                             capture_output=True, check=True).stdout
    profile = plistlib.loads(decoded)
    entitlements = profile.get("Entitlements", {})
    profile_ok = (entitlements.get("com.apple.developer.family-controls") is True
                  and entitlements.get("com.apple.developer.family-controls.app-and-website-usage") is True
                  and entitlements.get("get-task-allow") is True)
    print("Development profile capabilities:", "PASS" if profile_ok else "FAIL — usage capability and development profile required")
except (OSError, subprocess.SubprocessError, plistlib.InvalidFileException):
    print("Development profile capabilities: FAIL — cannot decode the supplied profile")

print("No signing or device changes made. Profile secrets are not printed.")
print("PASS checks prerequisites only; device authorization and real icon rendering still need verification.")
raise SystemExit(0 if sdk_ok and profile_ok else 1)
