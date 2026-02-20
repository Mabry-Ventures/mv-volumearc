# Beast Mode

A powerful workout tracker designed to help you push your limits and achieve your fitness goals.

## Overview

Beast Mode is a comprehensive fitness tracking application that helps you log workouts, track progress, and stay motivated on your fitness journey. Whether you're a beginner or an experienced athlete, Beast Mode provides the tools you need to take your training to the next level.

## Features

- **Workout Logging** - Record exercises, sets, reps, and weights with ease
- **Progress Tracking** - Visualize your gains over time with detailed charts and statistics
- **Custom Routines** - Create and save personalized workout routines
- **Exercise Library** - Access a comprehensive database of exercises with proper form guides
- **Rest Timer** - Built-in timer to optimize rest periods between sets
- **Personal Records** - Automatically track and celebrate your PRs
- **Workout History** - Review past workouts and analyze your training patterns

## Getting Started

### Prerequisites

- Node.js 18.x or higher
- npm or yarn

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/Mabry-Ventures/Beast-Mode.git
   cd Beast-Mode
   ```

2. Install dependencies:
   ```bash
   npm install
   ```

3. Configure environment variables:
   ```bash
   cp .env.example .env.local
   npm run env:bootstrap:prod
   npm run env:check
   ```
   Add your `OPENAI_API_KEY` and optional rate-limit credentials.
   For cloud sync persistence, set `DATABASE_URL` and apply:
   `npm run db:migrate`.

4. Start the development server:
   ```bash
   npm run dev
   ```

5. Open your browser and navigate to `http://localhost:3000`

## Usage

### Creating a Workout

1. Navigate to the "New Workout" section
2. Select exercises from the library or add custom ones
3. Log your sets, reps, and weights as you train
4. Save your workout when complete

### Tracking Progress

- View your workout history in the "History" tab
- Check your personal records in the "PRs" section
- Analyze trends in the "Statistics" dashboard

## Visual Baselines

Capture visual baseline snapshots for the redesigned core flows:

```bash
# Build and start the app in another terminal
npm run build
npm run start -- --hostname 127.0.0.1 --port 4173

# Capture baseline images
npm run visual:baseline

# On later runs, compare current UI against baselines
npm run visual:ci
```

Snapshots are written to:

`output/playwright/visual-baselines`

## Release Checklist

Run this checklist before each production release:

1. Verify environment variables from `.env.example` are set for the target environment.
2. Confirm progressive rollout flags in `GET /api/me/features` match intended rollout.
3. Run quality gates:
   - `npm run lint`
   - `npm test -- --runInBand`
   - `npm run build`
   - `npm run ai:eval`
4. Validate AI safety rails:
   - all AI routes return schema-valid payloads
   - deterministic fallback responses are returned when provider calls fail
5. Validate retention KPI telemetry:
   - `POST /api/telemetry/ingest` accepts events
   - `GET /api/telemetry/dashboard` shows set-log latency and fallback rates
6. Confirm rollback readiness:
   - feature-flag kill switches are available
   - latest stable tag/build is deployable

## Kill-Switch Map

Use these flags to disable features without redeploying code:

- `AI_ENABLE_WORKOUT_PLAN`: `/api/ai/workout-plan`
- `AI_ENABLE_LIVE_COACH`: `/api/ai/live-coach`
- `AI_ENABLE_POST_WORKOUT`: `/api/ai/post-workout`
- `AI_ENABLE_RISK_ANALYSIS`: `/api/ai/risk-analysis`
- `AI_ENABLE_LOG_PARSER`: `/api/ai/parse-log`
- `AI_ENABLE_TRANSCRIBE`: `/api/ai/transcribe`
- `AI_ENABLE_PROGRESSION_PLAN`: `/api/ai/progression-plan`
- `FEATURE_TELEMETRY_INGEST`: `/api/telemetry/ingest`
- `FEATURE_CLOUD_SYNC_ALPHA`: `/api/sync/push`, `/api/sync/pull`
- `FEATURE_PROGRESSION_AUTOPILOT`: progression plan generation/apply flow
- `FEATURE_HEALTH_INTEGRATIONS`: `/api/integrations/health/import`
- `FEATURE_MONETIZATION_CONTROLS`: `/api/subscription/entitlements`

Additional health sync route: `/api/integrations/health/sync` (provider pull, currently `oura` and `generic-json`).

Telemetry export wiring:

- `TELEMETRY_EXPORT_URL`: webhook endpoint that receives dashboard snapshots
- `TELEMETRY_EXPORT_TOKEN`: optional bearer token for export auth
- `TELEMETRY_EXPORT_MIN_INTERVAL_MS`: minimum export interval (default `30000`)

Program delivery plan: `docs/program/beast-mode-maximization-sprints-2026.md`

## Project Structure

```
Beast-Mode/
├── src/
│   ├── components/     # Reusable UI components
│   ├── pages/          # Application pages
│   ├── hooks/          # Custom React hooks
│   ├── utils/          # Utility functions
│   ├── types/          # TypeScript type definitions
│   └── styles/         # Global styles
├── public/             # Static assets
├── tests/              # Test files
└── docs/               # Documentation
```

## Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Guidelines

- Write clean, readable code with meaningful variable names
- Add tests for new features
- Follow the existing code style
- Update documentation as needed

## Roadmap

- [ ] Social features - share workouts with friends
- [ ] Workout templates from fitness influencers
- [ ] Apple Watch / Wear OS integration
- [x] AI-powered workout recommendations
- [ ] Nutrition tracking integration
- [ ] Multi-language support

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Thanks to all contributors who help make Beast Mode better
- Inspired by the fitness community's dedication to self-improvement

---

**Go Beast Mode!** 💪
