"""Run the four journeys on an owned simulator; never erase/use an existing device."""

import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent.parent


def run(command, log, timeout=180):
    with log.open("a") as output:
        output.write("\n$ " + " ".join(map(str, command)) + "\n")
        output.flush()
        process = subprocess.Popen(list(map(str, command)), cwd=ROOT, stdout=output,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            status = process.wait(timeout=timeout)
        except BaseException:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            raise
    if status:
        raise RuntimeError(f"Command exited {status}; see {log}: {command[0]}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--results", type=Path, required=True,
                        help="New results directory; reuse is rejected to prevent stale passes")
    args = parser.parse_args()
    app = args.app.resolve()
    results = args.results.resolve()
    results.mkdir(parents=True, exist_ok=False)
    log = results / "runner.log"
    runtime = os.environ.get("CI_SIMULATOR_RUNTIME", "com.apple.CoreSimulator.SimRuntime.iOS-26-2")
    simulator = None
    started = time.monotonic()
    try:
        if not (app / "Info.plist").is_file():
            raise ValueError(f"Simulator app is missing: {app}")
        run(["xcodebuild", "-version"], log)
        run(["java", "-version"], log)
        version = subprocess.check_output(["maestro", "--version"], text=True, timeout=60).strip()
        if version != "2.10.0":
            raise ValueError(f"Expected Maestro 2.10.0, got {version!r}")
        log.write_text(log.read_text() + f"\nMaestro: {version}\nRuntime: {runtime}\n")
        runtimes = json.loads(subprocess.check_output(
            ["xcrun", "simctl", "list", "runtimes", "--json"], timeout=30))
        if not any(r["identifier"] == runtime and r.get("isAvailable") for r in runtimes["runtimes"]):
            raise ValueError(f"Required runtime unavailable: {runtime}")
        simulator = subprocess.check_output([
            "xcrun", "simctl", "create", f"DOCard Maestro {os.getpid()}",
            "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro", runtime], text=True, timeout=30).strip()
        log.write_text(log.read_text() + f"Simulator: {simulator}\n")
        run(["xcrun", "simctl", "boot", simulator], log)
        run(["xcrun", "simctl", "bootstatus", simulator, "-b"], log)
        # Always install the caller's build, never a previously installed bundle.
        run(["xcrun", "simctl", "install", simulator, app], log)
        # Dismiss system keyboard tutorials on the fresh simulator.
        run(["xcrun", "simctl", "spawn", simulator, "defaults", "write",
             "com.apple.keyboard.preferences", "DidShowContinuousPathIntroduction", "-bool", "true"], log)
        status = 0
        try:
            run(["maestro", "--device", simulator, "test", "--format", "junit",
                 "--output", results / "report.xml", "--test-output-dir", results / "artifacts",
                 "--debug-output", results / "debug", ROOT / ".maestro/smoke"], log, timeout=600)
        except (RuntimeError, subprocess.TimeoutExpired) as error:
            log.write_text(log.read_text() + f"\n{error}\n")
            status = 1
        # Validate even when Maestro failed, and never accept an old report.
        run([sys.executable, ROOT / "ci/maestro-results.py", results / "report.xml"], log)
        if status:
            raise RuntimeError("Maestro failed or timed out")
        (results / "maestro-passed").write_text("Four journeys passed\n")
        print(f"Maestro: 4/4 passed in {time.monotonic() - started:.1f}s. Results: {results}")
    finally:
        if simulator:
            try:
                subprocess.run(["xcrun", "simctl", "io", simulator, "screenshot", str(results / "last-screen.png")],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
            except subprocess.TimeoutExpired:
                pass
            # Cleanup only this invocation's simulator, including failures.
            for action in ("shutdown", "delete"):
                try:
                    subprocess.run(["xcrun", "simctl", action, simulator], stdout=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL, timeout=30)
                except subprocess.TimeoutExpired:
                    print(f"Simulator cleanup timed out: {action} {simulator}", file=sys.stderr)


if __name__ == "__main__":
    def interrupted(_signum, _frame):
        raise KeyboardInterrupt("Maestro runner interrupted")

    signal.signal(signal.SIGTERM, interrupted)
    try:
        main()
    except (ValueError, RuntimeError, subprocess.SubprocessError, OSError) as error:
        sys.exit(str(error))
