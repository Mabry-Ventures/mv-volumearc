import { buildProgressionBlock } from '@/lib/progression/engine';
import type { AiHistoryDigest } from '@/types';

const digest: AiHistoryDigest = {
  generatedAt: new Date().toISOString(),
  unit: 'lbs',
  schemaVersion: '1.0.0',
  promptVersion: '1.0.0',
  totalWorkouts: 10,
  completedWorkouts: 10,
  currentStreak: 4,
  longestStreak: 6,
  totalVolume: 50000,
  averageDurationMinutes: 55,
  rollingVolume: { days7: 5000, days30: 16000, days90: 42000 },
  exerciseTrends: [
    {
      exerciseId: 'bench-press',
      exerciseName: 'Bench Press',
      sessions: 8,
      volume7d: 1200,
      volume30d: 4500,
      topSet: { weight: 185, reps: 5, unit: 'lbs', date: new Date().toISOString() },
      latestSet: { weight: 180, reps: 5, unit: 'lbs', date: new Date().toISOString() },
    },
  ],
  fatigueSignals: {
    plateauScore: 0.2,
    overtrainingScore: 0.25,
    lowPerformanceRuns: 0,
    highRpeCount: 3,
  },
  recentWorkouts: [],
};

describe('progression engine', () => {
  it('creates progression updates for tracked exercises', () => {
    const block = buildProgressionBlock(digest);

    expect(block.updates.length).toBeGreaterThan(0);
    expect(block.updates[0]?.exerciseId).toBe('bench-press');
    expect(block.deloadRecommended).toBe(false);
  });
});
