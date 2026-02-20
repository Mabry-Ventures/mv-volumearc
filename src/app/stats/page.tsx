'use client';

import { useEffect, useMemo, useState } from 'react';
import {
  BarChart3,
  Dumbbell,
  Flame,
  Trophy,
  TrendingUp,
  ShieldAlert,
  Activity,
  HeartPulse,
  Target,
} from 'lucide-react';
import { storage } from '@/utils/storage';
import { calculateUserStats, calculateWorkoutVolume, formatWeight } from '@/utils/calculations';
import { StatsCard, Card, SegmentedControl } from '@/components';
import { useRiskAnalysis } from '@/hooks/useRiskAnalysis';
import { buildHistoryDigest } from '@/lib/ai/contextBuilder';
import { uiAnalytics } from '@/lib/analytics';
import type { Workout, UserStats } from '@/types';

type VolumeOverlay = 'volume' | 'intensity' | 'frequency' | 'recovery';

const severityTone = (level: 'low' | 'medium' | 'high') => {
  if (level === 'high') return 'var(--danger-500)';
  if (level === 'medium') return 'var(--warning-500)';
  return 'var(--success-500)';
};

export default function StatsPage() {
  const [stats, setStats] = useState<UserStats | null>(null);
  const [workouts, setWorkouts] = useState<Workout[]>([]);
  const [weeklyVolume, setWeeklyVolume] = useState<
    { dateKey: string; day: string; volume: number; sessions: number; avgIntensity: number; recovery: number }[]
  >([]);
  const [unit, setUnit] = useState<'lbs' | 'kg'>('lbs');
  const [overlay, setOverlay] = useState<VolumeOverlay>('volume');
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

    const today = new Date();
    const weekData: {
      dateKey: string;
      day: string;
      volume: number;
      sessions: number;
      avgIntensity: number;
      recovery: number;
    }[] = [];
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

      const sets = dayWorkouts.flatMap(workout =>
        workout.exercises.flatMap(exercise => exercise.sets.filter(set => set.completed))
      );

      const avgIntensity = sets.length > 0 ? sets.reduce((sum, set) => sum + set.weight, 0) / sets.length : 0;
      const recovery = Math.max(0, 100 - dayWorkouts.length * 22);

      weekData.push({
        dateKey: date.toISOString().slice(0, 10),
        day: dayNames[date.getDay()],
        volume,
        sessions: dayWorkouts.length,
        avgIntensity,
        recovery,
      });
    }

    setWeeklyVolume(weekData);
    uiAnalytics.track({ stage: 'stats', action: 'stats_loaded', metadata: { workouts: data.length } });
  }, [riskAnalysis.analyzeRisk]);

  const chartConfig = useMemo(() => {
    if (overlay === 'volume') {
      const max = Math.max(...weeklyVolume.map(day => day.volume), 1);
      return {
        max,
        valueLabel: 'Volume',
        formatter: (value: number) => `${Math.round(value)} ${unit}`,
        getValue: (day: (typeof weeklyVolume)[number]) => day.volume,
      };
    }

    if (overlay === 'intensity') {
      const max = Math.max(...weeklyVolume.map(day => day.avgIntensity), 1);
      return {
        max,
        valueLabel: 'Intensity',
        formatter: (value: number) => `${Math.round(value)} ${unit}`,
        getValue: (day: (typeof weeklyVolume)[number]) => day.avgIntensity,
      };
    }

    if (overlay === 'frequency') {
      const max = Math.max(...weeklyVolume.map(day => day.sessions), 1);
      return {
        max,
        valueLabel: 'Frequency',
        formatter: (value: number) => `${Math.round(value)} sessions`,
        getValue: (day: (typeof weeklyVolume)[number]) => day.sessions,
      };
    }

    const max = Math.max(...weeklyVolume.map(day => day.recovery), 1);
    return {
      max,
      valueLabel: 'Recovery Proxy',
      formatter: (value: number) => `${Math.round(value)}%`,
      getValue: (day: (typeof weeklyVolume)[number]) => day.recovery,
    };
  }, [weeklyVolume, overlay, unit]);

  const goalProgress = useMemo(() => {
    if (!stats) return 0;
    const weeklyTarget = 4;
    const thisWeekSessions = weeklyVolume.reduce((sum, day) => sum + day.sessions, 0);
    return Math.min(100, Math.round((thisWeekSessions / weeklyTarget) * 100));
  }, [stats, weeklyVolume]);

  return (
    <div className="py-6">
      <header className="page-header">
        <h1 className="page-title">Statistics</h1>
        <p className="text-muted" style={{ fontSize: '0.84rem' }}>
          Performance trends, risk signals, and weekly consistency in one view.
        </p>
      </header>

      {!stats || workouts.length === 0 ? (
        <Card className="empty-state" elevated>
          <BarChart3 className="empty-state-icon" />
          <h3 className="empty-state-title">No data yet</h3>
          <p className="empty-state-description">
            Complete workouts to unlock trend analytics and AI risk monitoring.
          </p>
        </Card>
      ) : (
        <>
          <div className="grid grid-cols-2 gap-3 mb-6">
            <StatsCard
              value={stats.totalWorkouts}
              label="Total Workouts"
              icon={<Dumbbell size={24} color="var(--accent-400)" />}
            />
            <StatsCard
              value={stats.currentStreak}
              label="Current Streak"
              icon={<Flame size={24} color="var(--warning-500)" />}
            />
            <StatsCard
              value={formatWeight(stats.totalVolume, unit)}
              label="Total Volume"
              icon={<TrendingUp size={24} color="var(--success-500)" />}
            />
            <StatsCard
              value={stats.longestStreak}
              label="Longest Streak"
              icon={<Trophy size={24} color="var(--accent-400)" />}
            />
          </div>

          <Card className="mb-4" elevated>
            <div className="flex items-center gap-2 mb-2">
              <Target size={18} color="var(--accent-400)" />
              <h3 style={{ fontWeight: 700 }}>Goal Progress Rail</h3>
            </div>
            <p className="text-muted" style={{ fontSize: '0.8rem' }}>
              Weekly target: 4 sessions
            </p>
            <div className="timer-progress" style={{ marginTop: '0.75rem' }}>
              <div className="timer-progress-bar" style={{ width: `${goalProgress}%` }} />
            </div>
            <p className="text-muted" style={{ fontSize: '0.8rem', marginTop: '0.4rem' }}>
              {goalProgress}% complete this week
            </p>
          </Card>

          <Card className="mb-4" elevated>
            <div className="flex items-center gap-2 mb-3">
              <ShieldAlert size={18} color="var(--accent-400)" />
              <h3 style={{ fontWeight: 700 }}>Risk Monitor</h3>
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
                    <p className="text-muted" style={{ fontSize: '0.75rem' }}>Plateau Risk</p>
                    <p style={{ fontWeight: 700, color: severityTone(riskAnalysis.data.plateauRisk.level) }}>
                      {riskAnalysis.data.plateauRisk.level.toUpperCase()} ({Math.round(riskAnalysis.data.plateauRisk.score * 100)}%)
                    </p>
                  </div>
                  <div className="card" style={{ padding: '0.75rem' }}>
                    <p className="text-muted" style={{ fontSize: '0.75rem' }}>Overtraining Risk</p>
                    <p style={{ fontWeight: 700, color: severityTone(riskAnalysis.data.overtrainingRisk.level) }}>
                      {riskAnalysis.data.overtrainingRisk.level.toUpperCase()} ({Math.round(riskAnalysis.data.overtrainingRisk.score * 100)}%)
                    </p>
                  </div>
                </div>

                {riskAnalysis.data.recommendedActions.length > 0 && (
                  <>
                    <p className="mb-2" style={{ fontWeight: 700 }}>Recommended Actions</p>
                    <ul style={{ paddingLeft: '1.25rem' }}>
                      {riskAnalysis.data.recommendedActions.map(action => (
                        <li key={action}>{action}</li>
                      ))}
                    </ul>
                  </>
                )}
              </>
            )}
          </Card>

          <Card className="mb-4" elevated>
            <h3 className="mb-3" style={{ fontWeight: 700 }}>Weekly Volume</h3>
            <SegmentedControl
              ariaLabel="Weekly chart overlay"
              value={overlay}
              options={[
                { value: 'volume', label: 'Volume' },
                { value: 'intensity', label: 'Intensity' },
                { value: 'frequency', label: 'Frequency' },
                { value: 'recovery', label: 'Recovery' },
              ]}
              onChange={value => setOverlay(value as VolumeOverlay)}
            />

            <div className="flex gap-2 items-end mt-3" style={{ height: '158px' }}>
              {weeklyVolume.map(day => {
                const metricValue = chartConfig.getValue(day);
                const height = (metricValue / chartConfig.max) * 122;

                return (
                  <div key={day.dateKey} className="flex-1 flex flex-col items-center gap-2">
                    <div
                      title={`${day.day} ${chartConfig.valueLabel}: ${chartConfig.formatter(metricValue)}`}
                      style={{
                        width: '100%',
                        height: `${height}px`,
                        minHeight: metricValue > 0 ? '8px' : '2px',
                        background: metricValue > 0 ? 'var(--accent-500)' : 'var(--surface-border)',
                        borderRadius: '4px 4px 0 0',
                        transition: 'height 0.24s ease',
                      }}
                    />
                    <span style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>{day.day}</span>
                  </div>
                );
              })}
            </div>

            <p className="text-muted mt-3" style={{ fontSize: '0.8rem' }}>
              Overlay: {chartConfig.valueLabel}
            </p>
          </Card>

          {stats.favoriteExercise && (
            <Card className="mb-4" elevated>
              <h3 className="mb-2" style={{ fontWeight: 700 }}>Favorite Exercise</h3>
              <p className="text-primary" style={{ fontSize: '1.25rem', fontWeight: 700 }}>
                {stats.favoriteExercise.name}
              </p>
              <p className="text-muted" style={{ fontSize: '0.875rem' }}>
                {stats.favoriteExercise.muscleGroups.join(', ')}
              </p>
            </Card>
          )}

          <Card elevated>
            <h3 className="mb-3" style={{ fontWeight: 700 }}>Averages</h3>
            <div className="flex justify-between py-2 border-b">
              <span className="text-muted">Volume per Workout</span>
              <span style={{ fontWeight: 700 }}>
                {formatWeight(Math.round(stats.totalVolume / stats.totalWorkouts), unit)}
              </span>
            </div>
            <div className="flex justify-between py-2 border-b">
              <span className="text-muted">Exercises per Workout</span>
              <span style={{ fontWeight: 700 }}>
                {Math.round(
                  workouts.reduce((sum, workout) => sum + workout.exercises.length, 0) / workouts.length
                )}
              </span>
            </div>
            <div className="flex justify-between py-2">
              <span className="text-muted">Sets per Workout</span>
              <span style={{ fontWeight: 700 }}>
                {Math.round(
                  workouts.reduce(
                    (sum, workout) =>
                      sum +
                      workout.exercises.reduce(
                        (exerciseSum, exercise) => exerciseSum + exercise.sets.filter(set => set.completed).length,
                        0
                      ),
                    0
                  ) / workouts.length
                )}
              </span>
            </div>
          </Card>

          <Card className="mt-4" elevated>
            <div className="flex items-center gap-2 mb-2">
              <Activity size={17} color="var(--warning-500)" />
              <p style={{ fontWeight: 680 }}>Training Signal</p>
            </div>
            <p className="text-muted" style={{ fontSize: '0.82rem' }}>
              Frequency and recovery overlays help spot missed rest windows before performance drops.
            </p>
          </Card>

          <Card className="mt-4" elevated>
            <div className="flex items-center gap-2 mb-2">
              <HeartPulse size={17} color="var(--success-500)" />
              <p style={{ fontWeight: 680 }}>Consistency Loop</p>
            </div>
            <p className="text-muted" style={{ fontSize: '0.82rem' }}>
              Keep stacking sessions to maintain streak and steadily increase weekly volume.
            </p>
          </Card>
        </>
      )}
    </div>
  );
}
