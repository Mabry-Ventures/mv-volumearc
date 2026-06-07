#!/usr/bin/env python3
"""Run a command with a wall-clock timeout and kill its process group.

This is intentionally small and dependency-free so CI can use it on
macOS runners where GNU timeout is not available.
"""

from __future__ import annotations

import argparse
import os
import signal
import subprocess
import sys


def kill_process_group(pid: int, sig: signal.Signals) -> None:
    try:
        os.killpg(pid, sig)
    except ProcessLookupError:
        return


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=float, required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    command = args.command
    if command and command[0] == "--":
        command = command[1:]
    if not command:
        parser.error("missing command to run")

    timeout_display = int(args.timeout) if args.timeout.is_integer() else args.timeout
    print(f"::notice::{args.label} watchdog armed for {timeout_display}s.", flush=True)

    process = subprocess.Popen(command, start_new_session=True)
    timed_out = False
    try:
        return process.wait(timeout=args.timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        print(
            f"::error::{args.label} exceeded {timeout_display}s wall-clock timeout; "
            f"killing process group {process.pid}",
            flush=True,
        )
        kill_process_group(process.pid, signal.SIGTERM)

    if timed_out:
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            print(
                f"::error::{args.label} did not exit after SIGTERM; sending SIGKILL.",
                flush=True,
            )
            kill_process_group(process.pid, signal.SIGKILL)
            process.wait()
        return 124

    return process.returncode or 0


if __name__ == "__main__":
    sys.exit(main())
