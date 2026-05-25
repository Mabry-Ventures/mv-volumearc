#!/usr/bin/env bash
# VOL-100 / VOL-244: coach response-quality eval harness.
#
# The production relay is App Attest-only. For nightly response evals, this
# wrapper delegates to a Node runner that uses a staging-only eval attestation
# broker: an ephemeral P-256 key is bootstrapped once per run, then each fixture
# request carries a one-time nonce, signature, and monotonic counter.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec node "$ROOT/scripts/run_coach_evals.mjs"
