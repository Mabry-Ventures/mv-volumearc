'use client';

import { useEffect, useState } from 'react';
import { BarChart3, Dumbbell, Flame, Trophy, TrendingUp, ShieldAlert } from 'lucide-react';
import { storage } from '@/utils/storage';
import { calculateUserStats, calculateWorkoutVolume, formatWeight } from '@/utils/calculations';
import type { Workout, UserStats } from '@/types';
import { StatsCard } from '@/components/StatsCard';
import { useRiskAnalysis } from '@/hooks/useRiskAnalysis';
import { buildHistoryDigest } from '@/lib/ai/contextBuilder';

export default function StatsPage() {
  const [stats, setStats] = useState<UserStats | null>(null);
  const [workouts, setWorkouts] = useState<Workout[]>([]);
  const [weeklyVolume, setWeeklyVolume] = useState<
    { dateKey: string; day: string; volume: number }[]
  >([]);
  const [unit, setUnit] = useState<'lbs' | 'kg'>('lbs');
  const riskAnalysis = useRiskAnalysis();

  useEffect(() => {
    const settings = storage.getSettings();
    const data = storage.getWorkouts().filter(workout => workout.completed);
    setWorkouts(data);
    setUnit(settings.unit);
    setStats(calculateUserStats(data, settings.unit));

    const digest = buildHistoryDigest(data, settings.unit);
    void riskAnalysis.analyzeRisk({
      fullHistoryDigest: digest,
      trendWindows: [7, 30, 90],
    });

    // Calculate weekly volume
    const today = new Date();
    const weekData: { dateKey: string; day: string; volume: number }[] = [];
    const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    for (let i = 6; i >= 0; i--) {
      const date = new Date(today);
      date.setDate(date.getDate() - i);
      date.setHours(0, 0, 0, 0);

      const nextDate = new Date(date);
      nextDate.setDate(nextDate.getDate() + 1);

      const dayWorkouts = data.filter(workout => {
        const workoutDate = new Date(workout.date);
        return workoutDate >= date && workoutDate < nextDate;
      });

      const volume = dayWorkouts.reduce(
        (total, workout) => total + calculateWorkoutVolume(workout, settings.unit),
        0
      );

      weekData.push({
        dateKey: date.toISOString().slice(0, 10),
        day: dayNames[date.getDay()],
        volume,
      });
    }

    setWeeklyVolume(weekData);
  }, [riskAnalysis.analyzeRisk]);

  const maxVolume = Math.max(...weeklyVolume.map(day => day.volume), 1);

  return (
    <div className="py-6">
      <header className="page-header">
        <h1 className="page-title">Statistics</h1>
      </header>

      {!stats || workouts.length === 0 ? (
        <div className="empty-state">
          <BarChart3 className="empty-state-icon" />
          <h3 className="empty-state-title">No data yet</h3>
          <p className="empty-state-description">
            Complete some workouts to see your statistics.
          </p>
        </div>
      ) : (
        <>
          <div className="grid grid-cols-2 gap-3 mb-6">
            <StatsCard
              value={stats.totalWorkouts}
              label="Total Workouts"
              icon={<Dumbbell size={24} color="var(--primary)" />}
            />
            <StatsCard
              value={stats.currentStreak}
              label="Current Streak"
              icon={<Flame size={24} color="var(--primary)" />}
            />
            <StatsCard
              value={formatWeight(stats.totalVolume, unit)}
              label="Total Volume"
              icon={<TrendingUp size={24} color="var(--primary)" />}
            />
            <StatsCard
              value={stats.longestStreak}
              label="Longest Streak"
              icon={<Trophy size={24} color="var(--primary)" />}
            />
          </div>

          <div className="card mb-6">
            <div className="flex items-center gap-2 mb-3">
              <ShieldAlert size={18} color="var(--primary)" />
              <h3 style={{ fontWeight: 600 }}>AI Risk Monitor</h3>
            </div>

            {riskAnalysis.isLoading && (
              <p className="text-muted" style={{ fontSize: '0.875rem' }}>
                Analyzing plateau and overtraining risk...
              </p>
            )}

            {riskAnalysis.error && (
              <p className="text-danger" style={{ fontSize: '0.875rem' }}>
                {riskAnalysis.error}
              </p>
            )}

            {riskAnalysis.data && (
              <>
                <div className="grid grid-cols-2 gap-2 mb-3">
                  <div className="card" style={{ padding: '0.75rem' }}>
                    <p className="text-muted" style={{ fontSize: '0.75rem' }}>
                      Plateau Risk
                    </p>
                    <p style={{ fontWeight: 700 }}>
                      {riskAnalysis.data.plateauRisk.level.toUpperCase()} ({Math.round(riskAnalysis.data.plateauRisk.score * 100)}%)
                    </p>
                  </div>
                  <div className="card" style={{ padding: '0.75rem' }}>
                    <p className="text-muted" style={{ fontSize: '0.75rem' }}>
                      Overtraining Risk
                    </p>
                    <p style={{ fontWeight: 700 }}>
                      {riskAnalysis.data.overtrainingRisk.level.toUpperCase()} ({Math.round(riskAnalysis.data.overtrainingRisk.score * 100)}%)
                    </p>
                  </div>
                </div>

                {riskAnalysis.data.recommendedActions.length > 0 && (
                  <>
                    <p className="mb-2" style={{ fontWeight: 600 }}>Recommended Actions</p>
                    <ul style={{ paddingLeft: '1.25rem' }}>
                      {riskAnalysis.data.recommendedActions.map(action => (
                        <li key={action}>{action}</li>
                      ))}
                    </ul>
                  </>
                )}
              </>
            )}
          </div>

          {stats.favoriteExercise && (
            <div className="card mb-6">
              <h3 className="mb-2" style={{ fontWeight: 600 }}>Favorite Exercise</h3>
              <p className="text-primary" style={{ fontSize: '1.25rem', fontWeight: 600 }}>
                {stats.favoriteExercise.name}
              </p>
              <p className="text-muted" style={{ fontSize: '0.875rem' }}>
                {stats.favoriteExercise.muscleGroups.join(', ')}
              </p>
            </div>
          )}

          <div className="card">
            <h3 className="mb-4" style={{ fontWeight: 600 }}>Weekly Volume</h3>
            <div className="flex gap-2 items-end" style={{ height: '150px' }}>
              {weeklyVolume.map(day => (
                <div
                  key={day.dateKey}
                  className="flex-1 flex flex-col items-center gap-2"
                >
                  <div
                    style={{
                      width: '100%',
                      height: `${(day.volume / maxVolume) * 120}px`,
                      minHeight: day.volume > 0 ? '8px' : '2px',
                      background: day.volume > 0 ? 'var(--primary)' : 'var(--border)',
                      borderRadius: '4px 4px 0 0',
                      transition: 'height 0.3s ease',
                    }}
                  />
                  <span style={{ fontSize: '0.75rem', color: 'var(--muted)' }}>
                    {day.day}
                  </span>
                </div>
              ))}
            </div>
          </div>

          <div className="card mt-6">
            <h3 className="mb-3" style={{ fontWeight: 600 }}>Averages</h3>
            <div className="flex justify-between py-2 border-b" style={{ borderColor: 'var(--border)' }}>
              <span className="text-muted">Volume per Workout</span>
              <span style={{ fontWeight: 600 }}>
                {formatWeight(Math.round(stats.totalVolume / stats.totalWorkouts), unit)}
              </span>
            </div>
            <div className="flex justify-between py-2 border-b" style={{ borderColor: 'var(--border)' }}>
              <span className="text-muted">Exercises per Workout</span>
              <span style={{ fontWeight: 600 }}>
                {Math.round(
                  workouts.reduce((sum, workout) => sum + workout.exercises.length, 0) /
                    workouts.length
                )}
              </span>
            </div>
            <div className="flex justify-between py-2">
              <span className="text-muted">Sets per Workout</span>
              <span style={{ fontWeight: 600 }}>
                {Math.round(
                  workouts.reduce(
                    (sum, workout) =>
                      sum +
                      workout.exercises.reduce(
                        (exerciseSum, exercise) =>
                          exerciseSum + exercise.sets.filter(set => set.completed).length,
                        0
                      ),
                    0
                  ) / workouts.length
                )}
              </span>
            </div>
          </div>
        </>
      )}
    </div>
  );
}
