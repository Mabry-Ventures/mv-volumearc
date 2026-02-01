#!/usr/bin/env python3
"""
check_coverage.py
Beast Mode Test Coverage Checker

Parses Xcode coverage JSON and verifies minimum coverage thresholds.
Usage: python3 check_coverage.py <coverage.json> <threshold>
"""

import json
import sys
from pathlib import Path


def load_coverage(file_path: str) -> dict:
    """Load coverage JSON from file."""
    with open(file_path, 'r') as f:
        return json.load(f)


def calculate_coverage(data: dict) -> dict:
    """Calculate coverage statistics from Xcode coverage data."""
    results = {
        'overall': 0.0,
        'targets': {},
        'files': {},
        'low_coverage_files': []
    }

    targets = data.get('targets', [])
    total_covered = 0
    total_executable = 0

    for target in targets:
        target_name = target.get('name', 'Unknown')

        # Skip test targets
        if 'Tests' in target_name:
            continue

        target_covered = 0
        target_executable = 0

        for file in target.get('files', []):
            file_path = file.get('path', '')
            file_name = Path(file_path).name

            # Skip generated files and vendor code
            if any(skip in file_path for skip in ['Generated', 'Vendor', '.build']):
                continue

            covered = file.get('coveredLines', 0)
            executable = file.get('executableLines', 0)

            if executable > 0:
                file_coverage = (covered / executable) * 100
                results['files'][file_name] = {
                    'coverage': file_coverage,
                    'covered': covered,
                    'executable': executable,
                    'path': file_path
                }

                # Track low coverage files (below 70%)
                if file_coverage < 70:
                    results['low_coverage_files'].append({
                        'name': file_name,
                        'coverage': file_coverage,
                        'path': file_path
                    })

                target_covered += covered
                target_executable += executable

        if target_executable > 0:
            target_coverage = (target_covered / target_executable) * 100
            results['targets'][target_name] = {
                'coverage': target_coverage,
                'covered': target_covered,
                'executable': target_executable
            }

        total_covered += target_covered
        total_executable += target_executable

    if total_executable > 0:
        results['overall'] = (total_covered / total_executable) * 100

    return results


def print_report(results: dict, threshold: float) -> bool:
    """Print coverage report and return True if threshold is met."""
    print("\n" + "=" * 60)
    print("BEAST MODE TEST COVERAGE REPORT")
    print("=" * 60)

    # Overall coverage
    overall = results['overall']
    status = "✅" if overall >= threshold else "❌"
    print(f"\n{status} Overall Coverage: {overall:.1f}% (threshold: {threshold:.1f}%)")

    # Target coverage
    if results['targets']:
        print("\n--- Target Coverage ---")
        for target, data in sorted(results['targets'].items()):
            coverage = data['coverage']
            indicator = "✅" if coverage >= threshold else "⚠️" if coverage >= 70 else "❌"
            print(f"  {indicator} {target}: {coverage:.1f}%")

    # Low coverage files
    if results['low_coverage_files']:
        print("\n--- Low Coverage Files (< 70%) ---")
        sorted_files = sorted(results['low_coverage_files'], key=lambda x: x['coverage'])
        for file in sorted_files[:10]:  # Show top 10 lowest
            print(f"  ⚠️ {file['name']}: {file['coverage']:.1f}%")

    # Service coverage (key files)
    print("\n--- Core Service Coverage ---")
    key_services = [
        'PRDetectionService.swift',
        'StreakService.swift',
        'AnalyticsService.swift',
        'PlanSharingService.swift',
        'AICoachService.swift',
        'HealthKitService.swift'
    ]

    for service in key_services:
        if service in results['files']:
            data = results['files'][service]
            coverage = data['coverage']
            indicator = "✅" if coverage >= 90 else "⚠️" if coverage >= 70 else "❌"
            print(f"  {indicator} {service}: {coverage:.1f}%")
        else:
            print(f"  ❓ {service}: Not found")

    print("\n" + "=" * 60)

    return overall >= threshold


def main():
    if len(sys.argv) < 3:
        print("Usage: python3 check_coverage.py <coverage.json> <threshold>")
        print("Example: python3 check_coverage.py coverage.json 80.0")
        sys.exit(1)

    coverage_file = sys.argv[1]
    threshold = float(sys.argv[2])

    if not Path(coverage_file).exists():
        print(f"Error: Coverage file not found: {coverage_file}")
        sys.exit(1)

    try:
        data = load_coverage(coverage_file)
        results = calculate_coverage(data)
        passed = print_report(results, threshold)

        if not passed:
            print(f"\n❌ Coverage {results['overall']:.1f}% is below threshold {threshold:.1f}%")
            sys.exit(1)
        else:
            print(f"\n✅ Coverage threshold met!")
            sys.exit(0)

    except json.JSONDecodeError as e:
        print(f"Error parsing coverage JSON: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
