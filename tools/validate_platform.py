#!/usr/bin/env python3
"""
NOVA Platform Validation — Python φ-Mathematics Validator

Validates the platform structure and configuration integrity using
Fibonacci sequences and golden ratio assertions.

Usage:
    python3 validate_platform.py [--verbose] [--strict]

Requirements: Python 3.11+ (no external dependencies)

Casa de Medina — Architectos de Architectura Inteligente
"""

import json
import sys
import os
from pathlib import Path
from typing import NamedTuple

# ─── φ-Mathematics Constants ─────────────────────────────────────────────────

PHI = 1.6180339887498948482
PHI_INV = 0.6180339887498948


def fibonacci(n: int) -> int:
    """Return the n-th Fibonacci number."""
    if n < 0:
        raise ValueError(f"fibonacci({n}): n must be >= 0")
    a, b = 0, 1
    for _ in range(n):
        a, b = b, a + b
    return a


def nearest_fibonacci(n: int) -> int:
    """Return the nearest Fibonacci number >= n."""
    if n <= 0:
        return 0
    a, b = 0, 1
    while b < n:
        a, b = b, a + b
    return b


# ─── Validation Results ──────────────────────────────────────────────────────

class ValidationResult(NamedTuple):
    name: str
    passed: bool
    message: str


def validate_package_json(root: Path) -> list[ValidationResult]:
    """Validate root package.json configuration."""
    results = []
    pkg_path = root / "package.json"

    if not pkg_path.exists():
        results.append(ValidationResult("package.json exists", False, "File not found"))
        return results

    with open(pkg_path) as f:
        pkg = json.load(f)

    results.append(ValidationResult("package.json exists", True, str(pkg_path)))

    # Check Node engine constraint
    engines = pkg.get("engines", {})
    node_engine = engines.get("node", "")
    has_node_20 = "20" in node_engine
    results.append(ValidationResult(
        "Node 20 engine constraint",
        has_node_20,
        f"engines.node = '{node_engine}'" if node_engine else "No engines.node field"
    ))

    # Check type: module
    is_module = pkg.get("type") == "module"
    results.append(ValidationResult(
        "ESM module type",
        is_module,
        f"type = '{pkg.get('type', 'missing')}'"
    ))

    return results


def validate_frontend(root: Path) -> list[ValidationResult]:
    """Validate frontend structure and configuration."""
    results = []
    frontend = root / "src" / "frontend"

    if not frontend.exists():
        results.append(ValidationResult("Frontend directory", False, "src/frontend not found"))
        return results

    results.append(ValidationResult("Frontend directory", True, str(frontend)))

    # Check key files exist
    required_files = [
        "package.json",
        "vite.config.ts",
        "tsconfig.json",
        "tailwind.config.js",
        "src/App.tsx",
        "src/main.tsx",
        "src/index.css",
    ]

    for file in required_files:
        path = frontend / file
        results.append(ValidationResult(
            f"Frontend: {file}",
            path.exists(),
            "✓ present" if path.exists() else "✗ missing"
        ))

    # Validate frontend package.json
    fe_pkg_path = frontend / "package.json"
    if fe_pkg_path.exists():
        with open(fe_pkg_path) as f:
            fe_pkg = json.load(f)

        # Check engines
        fe_engines = fe_pkg.get("engines", {})
        fe_node = fe_engines.get("node", "")
        results.append(ValidationResult(
            "Frontend Node 20 constraint",
            "20" in fe_node,
            f"engines.node = '{fe_node}'" if fe_node else "No engines.node"
        ))

        # Check dependencies are present
        deps = fe_pkg.get("dependencies", {})
        required_deps = ["react", "react-dom", "react-router-dom", "zustand", "xstate"]
        for dep in required_deps:
            results.append(ValidationResult(
                f"Frontend dep: {dep}",
                dep in deps,
                deps.get(dep, "missing")
            ))

    return results


def validate_multi_language(root: Path) -> list[ValidationResult]:
    """Validate multi-language tool presence."""
    results = []

    # Go healthcheck
    go_main = root / "tools" / "healthcheck" / "main.go"
    results.append(ValidationResult(
        "Go health check utility",
        go_main.exists(),
        "✓ tools/healthcheck/main.go" if go_main.exists() else "✗ missing"
    ))

    # Rust (Cargo.toml)
    cargo = root / "Cargo.toml"
    results.append(ValidationResult(
        "Rust workspace (Cargo.toml)",
        cargo.exists(),
        "✓ present" if cargo.exists() else "✗ missing"
    ))

    # TypeScript
    tsconfig = root / "tsconfig.json"
    results.append(ValidationResult(
        "TypeScript config",
        tsconfig.exists(),
        "✓ present" if tsconfig.exists() else "✗ missing"
    ))

    # Motoko (check for .mo files)
    mo_files = list(root.glob("**/*.mo"))
    results.append(ValidationResult(
        "Motoko sources",
        len(mo_files) > 0,
        f"✓ {len(mo_files)} .mo files found" if mo_files else "✗ none found"
    ))

    return results


def validate_fibonacci_ci(root: Path) -> list[ValidationResult]:
    """Validate CI uses Fibonacci-aligned values."""
    results = []
    ci_path = root / ".github" / "workflows" / "ci.yml"

    if not ci_path.exists():
        results.append(ValidationResult("CI workflow", False, "ci.yml not found"))
        return results

    ci_content = ci_path.read_text()

    # Check Node version is 20
    has_node_20 = "NODE_VERSION: '20'" in ci_content or 'NODE_VERSION: "20"' in ci_content
    results.append(ValidationResult(
        "CI uses Node 20",
        has_node_20,
        "✓ NODE_VERSION: '20'" if has_node_20 else "✗ Node 20 not found"
    ))

    # Check for Fibonacci timeout values
    fib_timeouts = [89, 233, 377, 610]
    for timeout in fib_timeouts:
        has_timeout = str(timeout) in ci_content
        fib_index = [i for i in range(20) if fibonacci(i) == timeout]
        label = f"F({fib_index[0]})" if fib_index else str(timeout)
        results.append(ValidationResult(
            f"CI Fibonacci timeout {label}={timeout}",
            has_timeout,
            "✓ present" if has_timeout else "✗ missing"
        ))

    return results


# ─── Main ────────────────────────────────────────────────────────────────────

def main():
    verbose = "--verbose" in sys.argv or "-v" in sys.argv
    strict = "--strict" in sys.argv

    # Find project root (walk up from script location)
    root = Path(__file__).resolve().parent
    while root != root.parent:
        if (root / "package.json").exists() and (root / "nova.json").exists():
            break
        root = root.parent

    if not (root / "nova.json").exists():
        print("✗ Could not locate NOVA project root (nova.json)")
        sys.exit(2)

    print(f"╔═══════════════════════════════════════════════════════════╗")
    print(f"║  NOVA Platform Validation — φ-Mathematics Integrity     ║")
    print(f"║  Root: {str(root):<50} ║")
    print(f"╚═══════════════════════════════════════════════════════════╝")
    print()

    all_results: list[ValidationResult] = []

    # Run all validations
    sections = [
        ("Package Configuration", validate_package_json),
        ("Frontend Structure", validate_frontend),
        ("Multi-Language Stack", validate_multi_language),
        ("Fibonacci CI Pipeline", validate_fibonacci_ci),
    ]

    for section_name, validator in sections:
        results = validator(root)
        all_results.extend(results)

        if verbose:
            print(f"─── {section_name} ───")
            for r in results:
                icon = "✓" if r.passed else "✗"
                print(f"  {icon} {r.name}: {r.message}")
            print()

    # Summary
    passed = sum(1 for r in all_results if r.passed)
    failed = sum(1 for r in all_results if not r.passed)
    total = len(all_results)

    # Use Fibonacci for grading
    pass_rate = passed / total if total > 0 else 0

    print(f"═══ Summary ═══")
    print(f"  Passed: {passed}/{total} ({pass_rate:.1%})")
    print(f"  Failed: {failed}/{total}")
    print()

    if pass_rate >= 0.9:
        print(f"  Grade: OPTIMAL (≥90%)")
    elif pass_rate >= PHI_INV:
        print(f"  Grade: NOMINAL (≥{PHI_INV:.1%})")
    elif pass_rate >= PHI_INV * PHI_INV:
        print(f"  Grade: DEGRADED (≥{PHI_INV*PHI_INV:.1%})")
    else:
        print(f"  Grade: CRITICAL (<{PHI_INV*PHI_INV:.1%})")

    if failed > 0 and not verbose:
        print(f"\n  Failed checks:")
        for r in all_results:
            if not r.passed:
                print(f"    ✗ {r.name}: {r.message}")

    if strict and failed > 0:
        sys.exit(1)

    # Exit with Fibonacci-threshold based code
    if pass_rate < PHI_INV * PHI_INV:
        sys.exit(1)

    sys.exit(0)


if __name__ == "__main__":
    main()
