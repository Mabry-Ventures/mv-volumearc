import type { AiHistoryDigest, Workout } from '@/types';

export const sampleWorkout: Workout = {
  id: 'workout-fixture-1',
  name: 'Fixture Workout',
  date: '2026-02-10T10:00:00.000Z',
  completed: true,
  exercises: [],
  duration: 45,
};

export const sampleDigest: AiHistoryDigest = {
  generatedAt: '2026-02-10T11:00:00.000Z',
  unit: 'lbs',
  schemaVersion: '1.0.0',
  promptVersion: '1.0.0',
  totalWorkouts: 12,
  completedWorkouts: 12,
  currentStreak: 4,
  longestStreak: 8,
  totalVolume: 12450,
  averageDurationMinutes: 47,
  rollingVolume: {
    days7: 1800,
    days30: 6200,
    days90: 12450,
  },
  exerciseTrends: [
    {
      exerciseId: 'bench',
      exerciseName: 'Bench Press',
      sessions: 8,
      volume7d: 500,
      volume30d: 1800,
      topSet: {
        weight: 205,
        reps: 4,
        unit: 'lbs',
        date: '2026-02-09T10:00:00.000Z',
      },
      latestSet: {
        weight: 195,
        reps: 5,
        unit: 'lbs',
        date: '2026-02-10T10:00:00.000Z',
      },
    },
  ],
  fatigueSignals: {
    plateauScore: 0.3,
    overtrainingScore: 0.2,
    lowPerformanceRuns: 1,
    highRpeCount: 2,
  },
  recentWorkouts: [sampleWorkout],
};

