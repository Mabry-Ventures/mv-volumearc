'use client';

import { useEffect, useState } from 'react';
import { BarChart3, Dumbbell, Flame, Trophy, TrendingUp } from 'lucide-react';
import { storage } from '@/utils/storage';
import { calculateUserStats, calculateWorkoutVolume, formatWeight } from '@/utils/calculations';
import { Workout, UserStats } from '@/types';
import { StatsCard } from '@/components/StatsCard';

export default function StatsPage() {
  const [stats, setStats] = useState<UserStats | null>(null);
  const [workouts, setWorkouts] = useState<Workout[]>([]);
  const [weeklyVolume, setWeeklyVolume] = useState<{ day: string; volume: number }[]>([]);

  useEffect(() => {
    const data = storage.getWorkouts().filter(w => w.completed);
    setWorkouts(data);
    setStats(calculateUserStats(data));

    // Calculate weekly volume
    const today = new Date();
    const weekData: { day: string; volume: number }[] = [];
    const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    for (let i = 6; i >= 0; i--) {
      const date = new Date(today);
      date.setDate(date.getDate() - i);
      date.setHours(0, 0, 0, 0);

      const nextDate = new Date(date);
      nextDate.setDate(nextDate.getDate() + 1);

      const dayWorkouts = data.filter(w => {
        const workoutDate = new Date(w.date);
        return workoutDate >= date && workoutDate < nextDate;
      });

      const volume = dayWorkouts.reduce(
        (total, w) => total + calculateWorkoutVolume(w),
        0
      );

      weekData.push({
        day: dayNames[date.getDay()],
        volume,
      });
    }

    setWeeklyVolume(weekData);
  }, []);

  const maxVolume = Math.max(...weeklyVolume.map(d => d.volume), 1);

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
              value={formatWeight(stats.totalVolume, 'lbs')}
              label="Total Volume"
              icon={<TrendingUp size={24} color="var(--primary)" />}
            />
            <StatsCard
              value={stats.longestStreak}
              label="Longest Streak"
              icon={<Trophy size={24} color="var(--primary)" />}
            />
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
              {weeklyVolume.map((day, index) => (
                <div
                  key={index}
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
                {formatWeight(Math.round(stats.totalVolume / stats.totalWorkouts), 'lbs')}
              </span>
            </div>
            <div className="flex justify-between py-2 border-b" style={{ borderColor: 'var(--border)' }}>
              <span className="text-muted">Exercises per Workout</span>
              <span style={{ fontWeight: 600 }}>
                {Math.round(
                  workouts.reduce((sum, w) => sum + w.exercises.length, 0) /
                    workouts.length
                )}
              </span>
            </div>
            <div className="flex justify-between py-2">
              <span className="text-muted">Sets per Workout</span>
              <span style={{ fontWeight: 600 }}>
                {Math.round(
                  workouts.reduce(
                    (sum, w) =>
                      sum +
                      w.exercises.reduce(
                        (exSum, ex) => exSum + ex.sets.filter(s => s.completed).length,
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
