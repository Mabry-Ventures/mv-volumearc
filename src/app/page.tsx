'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { Dumbbell, Flame, Trophy, TrendingUp } from 'lucide-react';
import { StatsCard } from '@/components/StatsCard';
import { storage } from '@/utils/storage';
import { calculateUserStats, formatWeight } from '@/utils/calculations';
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
    setHasCurrentWorkout(!!currentWorkout);

    const completed = workouts.filter(w => w.completed);
    if (completed.length > 0) {
      const sorted = [...completed].sort(
        (a, b) => new Date(b.date).getTime() - new Date(a.date).getTime()
      );
      setRecentWorkout(sorted[0]);
    }
  }, []);

  return (
    <div className="py-6">
      <header className="mb-6">
        <h1 style={{ fontSize: '2rem', fontWeight: 700 }}>
          Beast Mode
        </h1>
        <p className="text-muted mt-1">Let&apos;s crush it today!</p>
      </header>

      {hasCurrentWorkout ? (
        <Link href="/workout" className="btn btn-primary btn-lg btn-block mb-6">
          <Dumbbell />
          Continue Workout
        </Link>
      ) : (
        <Link href="/workout" className="btn btn-primary btn-lg btn-block mb-6">
          <Dumbbell />
          Start Workout
        </Link>
      )}

      {stats && (
        <div className="grid grid-cols-2 gap-3 mb-6">
          <StatsCard
            value={stats.totalWorkouts}
            label="Total Workouts"
            icon={<Dumbbell size={24} color="var(--primary)" />}
          />
          <StatsCard
            value={stats.currentStreak}
            label="Day Streak"
            icon={<Flame size={24} color="var(--primary)" />}
          />
          <StatsCard
            value={formatWeight(stats.totalVolume, unit)}
            label="Total Volume"
            icon={<TrendingUp size={24} color="var(--primary)" />}
          />
          <StatsCard
            value={stats.longestStreak}
            label="Best Streak"
            icon={<Trophy size={24} color="var(--primary)" />}
          />
        </div>
      )}

      {recentWorkout && (
        <div className="card">
          <h3 className="mb-3" style={{ fontWeight: 600 }}>Last Workout</h3>
          <div className="workout-history-item" style={{ margin: 0 }}>
            <div className="workout-history-date">
              {new Date(recentWorkout.date).toLocaleDateString('en-US', {
                weekday: 'long',
                month: 'short',
                day: 'numeric',
              })}
            </div>
            <div className="workout-history-name">{recentWorkout.name}</div>
            <div className="workout-history-stats">
              <span>{recentWorkout.exercises.length} exercises</span>
              {recentWorkout.duration && <span>{recentWorkout.duration} min</span>}
            </div>
          </div>
        </div>
      )}

      {!stats?.totalWorkouts && (
        <div className="empty-state">
          <Dumbbell className="empty-state-icon" />
          <h3 className="empty-state-title">Ready to start?</h3>
          <p className="empty-state-description">
            Begin your fitness journey by starting your first workout.
          </p>
        </div>
      )}
    </div>
  );
}
