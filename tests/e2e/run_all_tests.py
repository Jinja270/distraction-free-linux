"""
Master 4-Tier E2E Test Runner for Distraction-Free Linux (Study OS).
Executes all test modules across Tiers 1-4:
- Tier 1: Functional Feature Matrix
- Tier 2: Boundary, Adversarial & Error Handling
- Tier 3: Cross-Feature Combinations & Invariants
- Tier 4: Real-World Application Workloads & Evasion Scenarios
Produces structured reports and summary metrics with exit code 0 on pass.
"""
import sys
import os
import time
import json
import argparse
import unittest
from pathlib import Path
from datetime import datetime, timezone

# Add tests/e2e and project root to sys.path
E2E_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = E2E_DIR.parent.parent

if str(E2E_DIR) not in sys.path:
    sys.path.insert(0, str(E2E_DIR))
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

# Registered E2E Test Modules
MODULE_MAP = {
    "network": ("test_network_blocking", "Network Distraction Blocking & Firewall"),
    "browser": ("test_browser_policy", "Firefox Enterprise Policy & Lockdown"),
    "desktop": ("test_desktop_config", "Minimal XFCE Desktop & Noise Reduction"),
    "tools": ("test_study_tools", "Study Tool Suite & Pomodoro Timer"),
    "boot": ("test_boot_and_persistence", "Live Bootloader, Amnesia & Persistence"),
}


class StructuredTestResult(unittest.TestResult):
    """Captures per-test structured execution timing, status, and error details."""

    def __init__(self, stream=None, descriptions=None, verbosity=None):
        super().__init__(stream, descriptions, verbosity)
        self.test_records = []
        self._start_times = {}

    def startTest(self, test):
        super().startTest(test)
        self._start_times[test.id()] = time.perf_counter()

    def addSuccess(self, test):
        super().addSuccess(test)
        elapsed = time.perf_counter() - self._start_times.get(test.id(), time.perf_counter())
        self.test_records.append({
            "test_id": test.id(),
            "name": test._testMethodName,
            "status": "PASS",
            "duration_ms": round(elapsed * 1000, 2),
            "error": None,
        })

    def addFailure(self, test, err):
        super().addFailure(test, err)
        elapsed = time.perf_counter() - self._start_times.get(test.id(), time.perf_counter())
        self.test_records.append({
            "test_id": test.id(),
            "name": test._testMethodName,
            "status": "FAIL",
            "duration_ms": round(elapsed * 1000, 2),
            "error": self._exc_info_to_string(err, test),
        })

    def addError(self, test, err):
        super().addError(test, err)
        elapsed = time.perf_counter() - self._start_times.get(test.id(), time.perf_counter())
        self.test_records.append({
            "test_id": test.id(),
            "name": test._testMethodName,
            "status": "ERROR",
            "duration_ms": round(elapsed * 1000, 2),
            "error": self._exc_info_to_string(err, test),
        })

    def addSkip(self, test, reason):
        super().addSkip(test, reason)
        elapsed = time.perf_counter() - self._start_times.get(test.id(), time.perf_counter())
        self.test_records.append({
            "test_id": test.id(),
            "name": test._testMethodName,
            "status": "SKIP",
            "duration_ms": round(elapsed * 1000, 2),
            "reason": reason,
            "error": None,
        })


def determine_test_tier(test) -> int:
    """Determine the tier (1, 2, 3, or 4) of a test case from class name or test method name."""
    class_name = test.__class__.__name__.lower()
    method_name = test._testMethodName.lower()

    for t in [1, 2, 3, 4]:
        if f"tier{t}" in class_name or f"tier{t}" in method_name:
            return t
    return 1


def load_selected_tests(modules: list[str], selected_tiers: list[int]) -> unittest.TestSuite:
    """Load test cases from specified modules filtered by selected tiers."""
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()

    for mod_key in modules:
        mod_name, _ = MODULE_MAP[mod_key]
        try:
            mod = __import__(mod_name, fromlist=["*"])
            module_suite = loader.loadTestsFromModule(mod)
            for test in _flatten_suite(module_suite):
                tier = determine_test_tier(test)
                if tier in selected_tiers:
                    suite.addTest(test)
        except Exception as e:
            print(f"Error loading module {mod_name}: {e}", file=sys.stderr)
            raise
    return suite


def _flatten_suite(suite):
    """Recursively yield all individual TestCase instances from a TestSuite."""
    for item in suite:
        if isinstance(item, unittest.TestSuite):
            yield from _flatten_suite(item)
        else:
            yield item


def run_e2e_suite(modules: list[str], tiers: list[int], fail_fast: bool = False, verbose: bool = False):
    """Execute the test suite and return StructuredTestResult and summary dict."""
    suite = load_selected_tests(modules, tiers)

    runner = unittest.TextTestRunner(
        resultclass=StructuredTestResult,
        verbosity=2 if verbose else 1,
        failfast=fail_fast,
    )

    start_time = time.perf_counter()
    result = runner.run(suite)
    duration = time.perf_counter() - start_time

    # Calculate Tier Breakdown
    tier_breakdown = {}
    for t in tiers:
        tier_tests = [r for r in result.test_records if f"tier{t}" in r["test_id"].lower() or f"tier_{t}" in r["test_id"].lower()]
        passed = sum(1 for r in tier_tests if r["status"] == "PASS")
        failed = sum(1 for r in tier_tests if r["status"] == "FAIL")
        errors = sum(1 for r in tier_tests if r["status"] == "ERROR")
        skipped = sum(1 for r in tier_tests if r["status"] == "SKIP")
        tier_breakdown[f"Tier {t}"] = {
            "total": len(tier_tests),
            "passed": passed,
            "failed": failed,
            "errors": errors,
            "skipped": skipped,
        }

    # Calculate Module Breakdown
    module_breakdown = {}
    for mod_key in modules:
        mod_name, desc = MODULE_MAP[mod_key]
        mod_tests = [r for r in result.test_records if mod_name in r["test_id"]]
        passed = sum(1 for r in mod_tests if r["status"] == "PASS")
        failed = sum(1 for r in mod_tests if r["status"] == "FAIL")
        errors = sum(1 for r in mod_tests if r["status"] == "ERROR")
        skipped = sum(1 for r in mod_tests if r["status"] == "SKIP")
        module_breakdown[mod_key] = {
            "name": desc,
            "total": len(mod_tests),
            "passed": passed,
            "failed": failed,
            "errors": errors,
            "skipped": skipped,
        }

    summary = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "environment": {
            "python": sys.version.split()[0],
            "platform": sys.platform,
            "project_root": str(PROJECT_ROOT),
        },
        "summary": {
            "total_tests": result.testsRun,
            "passed": len(result.test_records) - len(result.failures) - len(result.errors) - len(result.skipped),
            "failures": len(result.failures),
            "errors": len(result.errors),
            "skipped": len(result.skipped),
            "duration_seconds": round(duration, 3),
            "success": result.wasSuccessful(),
        },
        "tier_breakdown": tier_breakdown,
        "module_breakdown": module_breakdown,
        "results": result.test_records,
    }

    return result, summary


def print_summary_table(summary: dict):
    """Format and print structured console summary table."""
    s = summary["summary"]
    print("\n" + "=" * 76)
    print("      DISTRACTION-FREE LINUX (STUDY OS) -- E2E TEST SUMMARY")
    print("=" * 76)
    print(f"Total Tests Executed : {s['total_tests']}")
    print(f"Passed               : {s['passed']}")
    print(f"Failures             : {s['failures']}")
    print(f"Errors               : {s['errors']}")
    print(f"Skipped (M1-M3 wait) : {s['skipped']}")
    print(f"Execution Duration   : {s['duration_seconds']}s")
    print(f"Overall Result       : {'SUCCESS / READY' if s['success'] else 'FAILED'}")
    print("-" * 76)
    print(f"{'Tier Level':<12} | {'Total':<8} | {'Passed':<8} | {'Failed':<8} | {'Skipped':<8}")
    print("-" * 76)
    for tier_key, stats in summary["tier_breakdown"].items():
        print(f"{tier_key:<12} | {stats['total']:<8} | {stats['passed']:<8} | {stats['failed']:<8} | {stats['skipped']:<8}")
    print("-" * 76)
    print(f"{'Module':<12} | {'Total':<8} | {'Passed':<8} | {'Failed':<8} | {'Skipped':<8}")
    print("-" * 76)
    for mod_key, stats in summary["module_breakdown"].items():
        print(f"{mod_key:<12} | {stats['total']:<8} | {stats['passed']:<8} | {stats['failed']:<8} | {stats['skipped']:<8}")
    print("=" * 76 + "\n")


def main():
    parser = argparse.ArgumentParser(description="Distraction-Free Linux E2E 4-Tier Test Runner")
    parser.add_argument(
        "--tier",
        type=str,
        default="all",
        help="Comma-separated tiers to run: 1, 2, 3, 4, or all (default: all)",
    )
    parser.add_argument(
        "--module",
        type=str,
        default="all",
        help="Module to test: network, browser, desktop, tools, boot, or all (default: all)",
    )
    parser.add_argument(
        "--json-report",
        type=str,
        default=None,
        help="Path to write structured JSON test report",
    )
    parser.add_argument(
        "--fail-fast",
        action="store_true",
        help="Halt execution on first encountered test failure",
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Verbose test logging",
    )

    args = parser.parse_args()

    # Parse Tiers
    if args.tier.lower() == "all":
        selected_tiers = [1, 2, 3, 4]
    else:
        try:
            selected_tiers = [int(t.strip()) for t in args.tier.split(",")]
        except ValueError:
            print(f"Invalid tier argument: {args.tier}. Expected integers 1-4 or 'all'.", file=sys.stderr)
            sys.exit(2)

    # Parse Modules
    if args.module.lower() == "all":
        selected_modules = list(MODULE_MAP.keys())
    else:
        selected_modules = [m.strip().lower() for m in args.module.split(",")]
        for m in selected_modules:
            if m not in MODULE_MAP:
                print(f"Unknown module '{m}'. Available: {list(MODULE_MAP.keys())}", file=sys.stderr)
                sys.exit(2)

    try:
        result, summary = run_e2e_suite(
            modules=selected_modules,
            tiers=selected_tiers,
            fail_fast=args.fail_fast,
            verbose=args.verbose,
        )
    except Exception as e:
        print(f"Fatal test runner error: {e}", file=sys.stderr)
        sys.exit(2)

    print_summary_table(summary)

    if args.json_report:
        out_p = Path(args.json_report)
        out_p.parent.mkdir(parents=True, exist_ok=True)
        out_p.write_text(json.dumps(summary, indent=2), encoding="utf-8")
        print(f"Structured JSON report saved to: {out_p.resolve()}")

    if result.wasSuccessful():
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()
