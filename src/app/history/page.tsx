'use client';

import { useEffect, useMemo, useState } from 'react';
import { Calendar, Trash2, ChevronRight, Repeat2, Sparkles, Trophy } from 'lucide-react';
import { Button, Card } from '@/components';
import { storage } from '@/utils/storage';
import { calculateWorkoutVolume, convertWeight, formatDuration, formatWeight } from '@/utils/calculations';
import { uiAnalytics } from '@/lib/analytics';
import type { Workout, WorkoutSet } from '@/types';

const formatDate = (dateString: string) => {
  return new Date(dateString).toLocaleDateString('en-US', {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
};

const formatSetWeight = (set: WorkoutSet, unit: 'lbs' | 'kg'): string => {
  const weight = set.unit === unit ? set.weight : convertWeight(set.weight, set.unit, unit);
  return `${weight} ${unit}`;
};

const completedSetCount = (workout: Workout) =>
  workout.exercises.reduce((total, ex) => total + ex.sets.filter(s => s.completed).length, 0);

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

    uiAnalytics.track({
      stage: 'history',
      action: 'history_loaded',
      metadata: { completedWorkouts: completed.length },
    });
  }, []);

  const selectedComparison = useMemo(() => {
    if (!selectedWorkout) return null;

    const baseline = workouts
      .filter(workout => workout.id !== selectedWorkout.id && workout.name === selectedWorkout.name)
      .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime())[0];

    return baseline || null;
  }, [selectedWorkout, workouts]);

  const handleDelete = (id: string) => {
    if (confirm('Are you sure you want to delete this workout?')) {
      storage.deleteWorkout(id);
      setWorkouts(prev => prev.filter(w => w.id !== id));
      if (selectedWorkout?.id === id) {
        setSelectedWorkout(null);
      }
    }
  };

  if (selectedWorkout) {
    const selectedVolume = calculateWorkoutVolume(selectedWorkout, unit);
    const baselineVolume = selectedComparison ? calculateWorkoutVolume(selectedComparison, unit) : 0;

    const volumeDelta = selectedComparison ? selectedVolume - baselineVolume : 0;
    const setDelta = selectedComparison
      ? completedSetCount(selectedWorkout) - completedSetCount(selectedComparison)
      : 0;

    return (
      <div className="py-6">
        <header className="page-header flex justify-between items-center">
          <div>
            <Button variant="ghost" size="sm" className="mb-2" onClick={() => setSelectedWorkout(null)}>
              ← Back to History
            </Button>
            <h1 className="page-title">{selectedWorkout.name}</h1>
            <p className="text-muted" style={{ fontSize: '0.85rem' }}>
              {formatDate(selectedWorkout.date)}
            </p>
          </div>
        </header>

        <div className="grid grid-cols-3 gap-3 mb-4">
          <div className="stat-card">
            <div className="stat-value">{selectedWorkout.exercises.length}</div>
            <div className="stat-label">Exercises</div>
          </div>
          <div className="stat-card">
            <div className="stat-value">{completedSetCount(selectedWorkout)}</div>
            <div className="stat-label">Sets</div>
          </div>
          <div className="stat-card">
            <div className="stat-value">
              {selectedWorkout.duration ? formatDuration(selectedWorkout.duration) : '-'}
            </div>
            <div className="stat-label">Duration</div>
          </div>
        </div>

        <Card className="mb-4" elevated>
          <h3 className="mb-2" style={{ fontWeight: 700 }}>
            Total Volume: {formatWeight(selectedVolume, unit)}
          </h3>

          {selectedComparison && (
            <div className="card" style={{ padding: '0.7rem' }}>
              <p style={{ fontWeight: 650, marginBottom: '0.2rem' }}>
                <Repeat2 size={15} style={{ display: 'inline', marginRight: '0.35rem' }} />
                Compare vs previous "{selectedComparison.name}"
              </p>
              <div className="workout-history-stats">
                <span>Volume Δ {volumeDelta >= 0 ? '+' : ''}{formatWeight(volumeDelta, unit)}</span>
                <span>Set Δ {setDelta >= 0 ? '+' : ''}{setDelta}</span>
                <span>
                  Duration Δ {(selectedWorkout.duration || 0) - (selectedComparison.duration || 0) >= 0 ? '+' : ''}
                  {(selectedWorkout.duration || 0) - (selectedComparison.duration || 0)}m
                </span>
              </div>
            </div>
          )}
        </Card>

        {selectedWorkout.aiSummary && (
          <Card className="mb-4" elevated>
            <h3 className="mb-2" style={{ fontWeight: 700 }}>
              <Sparkles size={17} style={{ display: 'inline', marginRight: '0.4rem' }} />
              AI Summary
            </h3>
            <p className="mb-3">{selectedWorkout.aiSummary.summary}</p>

            {selectedWorkout.aiSummary.keyWins.length > 0 && (
              <>
                <p style={{ fontWeight: 650, marginBottom: '0.35rem' }}>Key Wins</p>
                <ul style={{ paddingLeft: '1.25rem' }} className="mb-3">
                  {selectedWorkout.aiSummary.keyWins.map(win => (
                    <li key={win}>{win}</li>
                  ))}
                </ul>
              </>
            )}

            {selectedWorkout.aiSummary.prCandidates.length > 0 && (
              <>
                <p style={{ fontWeight: 650, marginBottom: '0.35rem' }}>
                  <Trophy size={15} style={{ display: 'inline', marginRight: '0.35rem' }} />
                  PR Candidates
                </p>
                <ul style={{ paddingLeft: '1.25rem' }}>
                  {selectedWorkout.aiSummary.prCandidates.map(candidate => (
                    <li key={`${candidate.exerciseId}-${candidate.exerciseName}`}>
                      {candidate.exerciseName}: {candidate.newBest.weight} {candidate.newBest.unit} x {candidate.newBest.reps}
                    </li>
                  ))}
                </ul>
              </>
            )}
          </Card>
        )}

        {selectedWorkout.exercises.map(exercise => (
          <Card key={exercise.id} className="mb-3">
            <h4 style={{ fontWeight: 700, marginBottom: '0.75rem' }}>{exercise.exercise.name}</h4>
            <div className="grid grid-cols-3 gap-2 mb-2" style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>
              <div>SET</div>
              <div>WEIGHT</div>
              <div>REPS</div>
            </div>
            {exercise.sets
              .filter(s => s.completed)
              .map((set, index) => (
                <div key={set.id} className="grid grid-cols-3 gap-2 py-1">
                  <div>{index + 1}</div>
                  <div>{formatSetWeight(set, unit)}</div>
                  <div>{set.reps}</div>
                </div>
              ))}
          </Card>
        ))}
      </div>
    );
  }

  return (
    <div className="py-6">
      <header className="page-header">
        <h1 className="page-title">Workout History</h1>
        <p className="text-muted" style={{ fontSize: '0.84rem' }}>
          Track consistency, compare repeats, and review AI coaching outcomes.
        </p>
      </header>

      {workouts.length === 0 ? (
        <Card className="empty-state" elevated>
          <Calendar className="empty-state-icon" />
          <h3 className="empty-state-title">No workouts yet</h3>
          <p className="empty-state-description">
            Complete your first workout to start your performance timeline.
          </p>
        </Card>
      ) : (
        <div>
          {workouts.map(workout => (
            <div key={workout.id} className="workout-history-item">
              <div className="flex justify-between items-start gap-2">
                <button
                  type="button"
                  className="text-left"
                  onClick={() => {
                    setSelectedWorkout(workout);
                    uiAnalytics.track({ stage: 'history', action: 'workout_opened' });
                  }}
                  style={{
                    border: 'none',
                    background: 'transparent',
                    padding: 0,
                    margin: 0,
                    flex: 1,
                    cursor: 'pointer',
                  }}
                >
                  <div className="workout-history-date">{formatDate(workout.date)}</div>
                  <div className="workout-history-name">{workout.name}</div>
                  <div className="workout-history-stats">
                    <span>{workout.exercises.length} exercises</span>
                    {workout.duration && <span>{formatDuration(workout.duration)}</span>}
                    <span>{formatWeight(calculateWorkoutVolume(workout, unit), unit)}</span>
                  </div>
                  {workout.aiSummary && <p className="text-muted" style={{ fontSize: '0.74rem', marginTop: '0.35rem' }}>AI summary available</p>}
                </button>

                <div className="flex gap-2 items-center">
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={e => {
                      e.stopPropagation();
                      handleDelete(workout.id);
                    }}
                    aria-label="Delete workout"
                  >
                    <Trash2 size={16} />
                  </Button>
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
