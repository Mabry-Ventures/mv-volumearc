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
   ```
   Add your `OPENAI_API_KEY` and optional rate-limit credentials.

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
