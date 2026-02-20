'use client';

import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { Dumbbell, Flame, Trophy, TrendingUp, Zap, Sparkles, ArrowRight } from 'lucide-react';
import { StatsCard } from '@/components/StatsCard';
import { Card } from '@/components/ui/Card';
import { Button } from '@/components/ui/Button';
import { storage } from '@/utils/storage';
import { calculateUserStats, formatWeight } from '@/utils/calculations';
import { uiAnalytics } from '@/lib/analytics';
import type { Workout, UserStats } from '@/types';

export default function HomePage() {
  const [stats, setStats] = useState<UserStats | null>(null);
  const [recentWorkout, setRecentWorkout] = useState<Workout | null>(null);
  const [hasCurrentWorkout, setHasCurrentWorkout] = useState(false);
  const [unit, setUnit] = useState<'lbs' | 'kg'>('lbs');

  useEffect(() => {
    const workouts = storage.getWorkouts();
    const currentWorkout = storage.getCurrentWorkout();
    const settings = storage.getSettings();

    setUnit(settings.unit);
    setStats(calculateUserStats(workouts, settings.unit));
    setHasCurrentWorkout(Boolean(currentWorkout));

    const completed = workouts.filter(workout => workout.completed);
    if (completed.length > 0) {
      const sorted = [...completed].sort(
        (a, b) => new Date(b.date).getTime() - new Date(a.date).getTime()
      );
      setRecentWorkout(sorted[0]);
    }

    uiAnalytics.track({
      stage: 'home',
      action: 'home_loaded',
      metadata: {
        workouts: workouts.length,
        hasCurrentWorkout: Boolean(currentWorkout),
      },
    });
  }, []);

  const readinessMessage = useMemo(() => {
    if (!stats || stats.totalWorkouts === 0) return 'Lock in your first session.';
    if (stats.currentStreak >= 5) return 'Streak hot. Keep momentum rolling.';
    if (stats.currentStreak >= 2) return 'You are consistent this week. Hit another clean lift day.';
    return 'Reset focus and stack one strong session today.';
  }, [stats]);

  const streakRescueMessage = useMemo(() => {
    if (!stats || stats.totalWorkouts === 0) return null;
    if (stats.currentStreak > 0) return null;
    return 'Streak rescue available: complete one short session today to restart momentum.';
  }, [stats]);

  return (
    <div className="py-6">
      <header className="hero-card mb-4">
        <p className="workflow-chip mb-2" style={{ display: 'inline-flex' }}>
          Premium Athlete Mode
        </p>
        <h1 className="hero-title">Beast Mode</h1>
        <p className="hero-subtitle">Fast logging. Smart coaching. No wasted reps.</p>

        <div className="workflow-chip-row mt-3 mb-3">
          <span className="workflow-chip">Quick Start</span>
          <span className="workflow-chip">Last Routine</span>
          <span className="workflow-chip">AI Plan</span>
        </div>

        <p className="text-muted" style={{ fontSize: '0.84rem' }}>{readinessMessage}</p>
      </header>

      {hasCurrentWorkout ? (
        <Link href="/workout" onClick={() => uiAnalytics.track({ stage: 'home', action: 'continue_workout_click' })}>
          <Button variant="primary" size="lg" block className="mb-4">
            <Dumbbell size={18} />
            Continue Workout
          </Button>
        </Link>
      ) : (
        <Link href="/workout" onClick={() => uiAnalytics.track({ stage: 'home', action: 'start_workout_click' })}>
          <Button variant="primary" size="lg" block className="mb-4">
            <Zap size={18} />
            Start Workout
          </Button>
        </Link>
      )}

      <div className="kpi-grid mb-4">
        {stats ? (
          <>
            <StatsCard
              value={stats.totalWorkouts}
              label="Total Workouts"
              icon={<Dumbbell size={20} color="var(--accent-400)" />}
            />
            <StatsCard
              value={stats.currentStreak}
              label="Current Streak"
              icon={<Flame size={20} color="var(--warning-500)" />}
            />
            <StatsCard
              value={formatWeight(stats.totalVolume, unit)}
              label="Total Volume"
              icon={<TrendingUp size={20} color="var(--success-500)" />}
            />
            <StatsCard
              value={stats.longestStreak}
              label="Best Streak"
              icon={<Trophy size={20} color="var(--accent-400)" />}
            />
          </>
        ) : (
          <>
            <StatsCard value="-" label="Total Workouts" />
            <StatsCard value="-" label="Current Streak" />
            <StatsCard value="-" label="Total Volume" />
            <StatsCard value="-" label="Best Streak" />
          </>
        )}
      </div>

      {recentWorkout && (
        <Card className="mb-4" elevated>
          <div className="flex justify-between items-center mb-2">
            <h3 style={{ fontWeight: 700 }}>Last Session Delta</h3>
            <Link href="/history" className="workflow-chip">
              Full History
            </Link>
          </div>
          <p style={{ fontWeight: 650 }}>{recentWorkout.name}</p>
          <p className="text-muted" style={{ fontSize: '0.78rem', marginTop: '0.2rem' }}>
            {new Date(recentWorkout.date).toLocaleDateString('en-US', {
              weekday: 'short',
              month: 'short',
              day: 'numeric',
            })}
          </p>
          <div className="workflow-chip-row mt-3">
            <span className="workflow-chip">{recentWorkout.exercises.length} exercises</span>
            <span className="workflow-chip">{recentWorkout.duration || 0} min</span>
          </div>
        </Card>
      )}

      <Card className="mb-4" elevated>
        <div className="flex justify-between items-center mb-2">
          <h3 style={{ fontWeight: 700 }}>Next Workout Ready</h3>
          <span className="workflow-chip">Retention Loop</span>
        </div>
        <p className="text-muted" style={{ fontSize: '0.82rem' }}>
          Your next session is prepped with AI progression targets and recovery-aware guidance.
        </p>
        <div className="mt-3">
          <Link href="/workout" className="btn btn-secondary">
            Start Next Session <ArrowRight size={15} />
          </Link>
        </div>
      </Card>

      {streakRescueMessage && (
        <Card className="mb-4" elevated>
          <p style={{ fontWeight: 650 }}>Streak Rescue</p>
          <p className="text-muted mt-1" style={{ fontSize: '0.82rem' }}>
            {streakRescueMessage}
          </p>
        </Card>
      )}

      {!stats?.totalWorkouts && (
        <Card className="empty-state" elevated>
          <Sparkles className="empty-state-icon" />
          <h3 className="empty-state-title">Ready to start?</h3>
          <p className="empty-state-description">
            Finish one session and your coaching dashboard unlocks.
          </p>
          <Link href="/workout" className="btn btn-secondary">
            Quick Start <ArrowRight size={16} />
          </Link>
        </Card>
      )}
    </div>
  );
}
