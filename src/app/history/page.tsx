'use client';

import { useEffect, useState } from 'react';
import { Calendar, Trash2, ChevronRight } from 'lucide-react';
import { storage } from '@/utils/storage';
import { calculateWorkoutVolume, convertWeight, formatDuration, formatWeight } from '@/utils/calculations';
import type { Workout, WorkoutSet } from '@/types';

export default function HistoryPage() {
  const [workouts, setWorkouts] = useState<Workout[]>([]);
  const [selectedWorkout, setSelectedWorkout] = useState<Workout | null>(null);
  const [unit, setUnit] = useState<'lbs' | 'kg'>('lbs');

  useEffect(() => {
    const data = storage.getWorkouts();
    const settings = storage.getSettings();
    const completed = data
      .filter(w => w.completed)
      .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());
    setWorkouts(completed);
    setUnit(settings.unit);
  }, []);

  const handleDelete = (id: string) => {
    if (confirm('Are you sure you want to delete this workout?')) {
      storage.deleteWorkout(id);
      setWorkouts(prev => prev.filter(w => w.id !== id));
      if (selectedWorkout?.id === id) {
        setSelectedWorkout(null);
      }
    }
  };

  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleDateString('en-US', {
      weekday: 'short',
      month: 'short',
      day: 'numeric',
      year: 'numeric',
    });
  };

  const formatSetWeight = (set: WorkoutSet): string => {
    const weight =
      set.unit === unit ? set.weight : convertWeight(set.weight, set.unit, unit);
    return `${weight} ${unit}`;
  };

  // Workout detail view
  if (selectedWorkout) {
    return (
      <div className="py-6">
        <header className="page-header flex justify-between items-center">
          <div>
            <button
              type="button"
              className="text-muted mb-2"
              onClick={() => setSelectedWorkout(null)}
              style={{ fontSize: '0.875rem' }}
            >
              ← Back to History
            </button>
            <h1 className="page-title">{selectedWorkout.name}</h1>
            <p className="text-muted" style={{ fontSize: '0.875rem' }}>
              {formatDate(selectedWorkout.date)}
            </p>
          </div>
        </header>

        <div className="grid grid-cols-3 gap-3 mb-6">
          <div className="stat-card">
            <div className="stat-value">{selectedWorkout.exercises.length}</div>
            <div className="stat-label">Exercises</div>
          </div>
          <div className="stat-card">
            <div className="stat-value">
              {selectedWorkout.exercises.reduce(
                (total, ex) => total + ex.sets.filter(s => s.completed).length,
                0
              )}
            </div>
            <div className="stat-label">Sets</div>
          </div>
          <div className="stat-card">
            <div className="stat-value">
              {selectedWorkout.duration ? formatDuration(selectedWorkout.duration) : '-'}
            </div>
            <div className="stat-label">Duration</div>
          </div>
        </div>

        <div className="card mb-4">
          <h3 className="mb-3" style={{ fontWeight: 600 }}>
            Total Volume: {formatWeight(calculateWorkoutVolume(selectedWorkout, unit), unit)}
          </h3>
        </div>

        {selectedWorkout.aiSummary && (
          <div className="card mb-4">
            <h3 className="mb-2" style={{ fontWeight: 600 }}>
              AI Summary
            </h3>
            <p className="mb-3">{selectedWorkout.aiSummary.summary}</p>
            {selectedWorkout.aiSummary.keyWins.length > 0 && (
              <ul style={{ paddingLeft: '1.25rem' }}>
                {selectedWorkout.aiSummary.keyWins.map(win => (
                  <li key={win}>{win}</li>
                ))}
              </ul>
            )}
          </div>
        )}

        {selectedWorkout.exercises.map(exercise => (
          <div key={exercise.id} className="card mb-3">
            <h4 style={{ fontWeight: 600, marginBottom: '0.75rem' }}>
              {exercise.exercise.name}
            </h4>
            <div className="grid grid-cols-3 gap-2 mb-2" style={{ fontSize: '0.75rem', color: 'var(--muted)' }}>
              <div>SET</div>
              <div>WEIGHT</div>
              <div>REPS</div>
            </div>
            {exercise.sets
              .filter(s => s.completed)
              .map((set, index) => (
                <div key={set.id} className="grid grid-cols-3 gap-2 py-1">
                  <div>{index + 1}</div>
                  <div>{formatSetWeight(set)}</div>
                  <div>{set.reps}</div>
                </div>
              ))}
          </div>
        ))}
      </div>
    );
  }

  // History list view
  return (
    <div className="py-6">
      <header className="page-header">
        <h1 className="page-title">Workout History</h1>
      </header>

      {workouts.length === 0 ? (
        <div className="empty-state">
          <Calendar className="empty-state-icon" />
          <h3 className="empty-state-title">No workouts yet</h3>
          <p className="empty-state-description">
            Complete your first workout to see it here.
          </p>
        </div>
      ) : (
        <div>
          {workouts.map(workout => (
            <div key={workout.id} className="workout-history-item">
              <div className="flex justify-between items-start">
                <button
                  type="button"
                  className="text-left"
                  onClick={() => setSelectedWorkout(workout)}
                  style={{
                    border: 'none',
                    background: 'transparent',
                    padding: 0,
                    margin: 0,
                    flex: 1,
                    cursor: 'pointer',
                  }}
                >
                  <div className="workout-history-date">
                    {formatDate(workout.date)}
                  </div>
                  <div className="workout-history-name">{workout.name}</div>
                  <div className="workout-history-stats">
                    <span>{workout.exercises.length} exercises</span>
                    {workout.duration && (
                      <span>{formatDuration(workout.duration)}</span>
                    )}
                    <span>{formatWeight(calculateWorkoutVolume(workout, unit), unit)}</span>
                  </div>
                </button>
                <div className="flex gap-2 items-center">
                  <button
                    type="button"
                    className="btn btn-ghost btn-sm"
                    onClick={e => {
                      e.stopPropagation();
                      handleDelete(workout.id);
                    }}
                  >
                    <Trash2 size={16} />
                  </button>
                  <ChevronRight size={20} className="text-muted" />
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
