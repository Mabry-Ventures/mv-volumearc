import {
  calculateSetVolume,
  calculateExerciseVolume,
  calculateWorkoutVolume,
  calculateTotalVolume,
  calculate1RM,
  convertWeight,
  calculateStreak,
  calculateUserStats,
  formatWeight,
  formatDuration,
} from '@/utils/calculations';
import type { Exercise, Workout, WorkoutExercise, WorkoutSet } from '@/types';

const exercise: Exercise = {
  id: 'bench-press',
  name: 'Bench Press',
  category: 'barbell',
  muscleGroups: ['chest'],
};

const makeSet = (overrides: Partial<WorkoutSet> = {}): WorkoutSet => ({
  id: 'set-1',
  reps: 5,
  weight: 100,
  unit: 'lbs',
  completed: true,
  ...overrides,
});

const makeExercise = (sets: WorkoutSet[]): WorkoutExercise => ({
  id: 'ex-1',
  exercise,
  sets,
});

const makeWorkout = (overrides: Partial<Workout> = {}): Workout => ({
  id: 'workout-1',
  name: 'Workout 1',
  date: '2026-02-04T10:00:00.000Z',
  exercises: [makeExercise([makeSet()])],
  completed: true,
  ...overrides,
});

describe('calculations', () => {
  it('calculates set volume with unit conversion and NaN safety', () => {
    const kgSet = makeSet({ weight: 100, reps: 2, unit: 'kg' });
    const volume = calculateSetVolume(kgSet, 'lbs');
    expect(volume).toBeCloseTo(440.9, 1);

    const nanSet = makeSet({ weight: Number.NaN, reps: 5 });
    expect(calculateSetVolume(nanSet)).toBe(0);
  });

  it('calculates exercise, workout, and total volume', () => {
    const sets = [
      makeSet({ weight: 100, reps: 5, completed: true }),
      makeSet({ id: 'set-2', weight: 200, reps: 3, completed: false }),
    ];
    const workoutExercise = makeExercise(sets);
    expect(calculateExerciseVolume(workoutExercise)).toBe(500);

    const workout = makeWorkout({ exercises: [workoutExercise] });
    expect(calculateWorkoutVolume(workout)).toBe(500);

    const workout2 = makeWorkout({
      id: 'workout-2',
      exercises: [makeExercise([makeSet({ weight: 50, reps: 10 })])],
    });
    expect(calculateTotalVolume([workout, workout2])).toBe(1000);
  });

  it('calculates 1RM and weight conversion', () => {
    expect(calculate1RM(100, 1)).toBe(100);
    expect(calculate1RM(100, 5)).toBe(113);
    expect(convertWeight(100, 'lbs', 'kg')).toBe(45.4);
  });

  it('calculates streaks by unique workout days', () => {
    jest.useFakeTimers().setSystemTime(new Date('2026-02-04T12:00:00.000Z'));

    const workouts = [
      makeWorkout({ id: 'w1', date: '2026-02-04T08:00:00.000Z' }),
      makeWorkout({ id: 'w2', date: '2026-02-04T18:00:00.000Z' }),
      makeWorkout({ id: 'w3', date: '2026-02-03T10:00:00.000Z' }),
    ];

    const streaks = calculateStreak(workouts);
    expect(streaks.current).toBe(2);
    expect(streaks.longest).toBe(2);

    jest.useRealTimers();
  });

  it('calculates user stats with target unit', () => {
    const workout = makeWorkout({
      exercises: [
        makeExercise([
          makeSet({ weight: 100, reps: 1, unit: 'kg' }),
        ]),
      ],
    });

    const stats = calculateUserStats([workout], 'kg');
    expect(stats.totalWorkouts).toBe(1);
    expect(stats.totalVolume).toBeCloseTo(100, 2);
  });

  it('formats weight and duration', () => {
    expect(formatWeight(150, 'lbs')).toBe('150 lbs');
    expect(formatDuration(135)).toBe('2h 15m');
  });
});
