# VolumeArc

[![CI](https://github.com/Mabry-Ventures/mv-volumearc/actions/workflows/ci.yml/badge.svg)](https://github.com/Mabry-Ventures/mv-volumearc/actions/workflows/ci.yml)

AI-powered strength training coach for iOS 26 and watchOS 26. Tracks workouts, coaches in real time via voice and text, syncs across devices through CloudKit, surfaces training signals through widgets and Live Activities.

**Owner:** Mabry Ventures · **Bundle:** `com.mabryventures.VolumeArc` · **Platforms:** iPhone, Apple Watch (paired)

## Getting started

- **Contributing?** Start with [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md). Then read [`CLAUDE.md`](CLAUDE.md) for the project-specific working agreement (applies to humans too).
- **Looking for the canonical platform reference?** [`docs/PLATFORM.md`](docs/PLATFORM.md) is the source of truth for implementation status, architecture, and conventions.
- **Reviewing security or privacy posture?** [`docs/SECURITY.md`](docs/SECURITY.md).
- **Investigating an incident?** [`docs/INCIDENTS.md`](docs/INCIDENTS.md).
- **Looking at the marketing site?** [`marketing/`](marketing/) (Next.js, deployed to `volumearc.app`) — see [`docs/MARKETING.md`](docs/MARKETING.md).
- **Looking at the coach relay?** [`relay/`](relay/) (Cloudflare Worker proxying to Gemini) — see [`docs/RELAY.md`](docs/RELAY.md).

## Repo layout

```
App/                          iOS app target (SwiftUI)
Watch/, WatchWidgets/         watchOS app + widget extension
Widgets/                      iOS widget extension
VolumeArcNative/Sources/      VolumeArcCore + VolumeArcUI libraries
Tests/VolumeArcAppTests/      Unit + integration tests
Tests/VolumeArcAppUITests/    XCUITest journey + accessibility + screenshot tests
Tests/VolumeArcAppPerfTests/  Performance regression suite (tag-gated in CI)
marketing/                    Next.js marketing site → volumearc.app
relay/                        Cloudflare Worker → Gemini
scripts/                      Build / regen / coverage / signing
docs/                         Canonical platform docs (start at PLATFORM.md)
.github/workflows/            CI, AI review gate, security scans, marketing
```

## Build commands

```bash
ruby scripts/generate_xcode_project.rb    # regenerate the xcodeproj (always do this first)
./scripts/build_all_targets.sh            # Debug build (iOS + watchOS)
./scripts/test_apple_targets.sh           # Unit + UI tests
./scripts/check_coverage.sh               # 80% gate on VolumeArcCore (VOL-52 / VOL-140)
./scripts/validate_release_config.sh      # Release-config sanity (entitlements, bundle IDs, signing)
```

The Xcode project is **generated** — never edit `VolumeArcApple.xcodeproj/project.pbxproj` by hand. See [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md) "Build system: the Xcode project is generated."

## Status

VolumeArc is pre-launch. The current launch-readiness audit is tracked in [`docs/AUDIT.md`](docs/AUDIT.md), and active release work now rolls up to the [VolumeArc Release](https://linear.app/mabry-ventures/initiative/volumearc-release-68a38ea2d762) Linear initiative. The release bar is every world-class scorecard category at 9.5 or higher with no unresolved P0-P4 findings.

## License

**Proprietary — all rights reserved by Mabry Ventures, LLC** (Nashville, Tennessee). See [`LICENSE`](LICENSE) for full text, or contact `legal@volumearc.com` for licensing inquiries.

## Security

See [`SECURITY.md`](SECURITY.md) for the vulnerability-disclosure process. The detailed threat model lives in [`docs/SECURITY.md`](docs/SECURITY.md). For security disclosures, contact `security@volumearc.com`.
