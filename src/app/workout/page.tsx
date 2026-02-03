'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { Plus, Check, X } from 'lucide-react';
import { useWorkouts } from '@/hooks/useWorkouts';
import { Timer } from '@/components/Timer';
import { ExerciseSelector } from '@/components/ExerciseSelector';
import { WorkoutExerciseCard } from '@/components/WorkoutExerciseCard';

export default function WorkoutPage() {
  const router = useRouter();
  const {
    currentWorkout,
    isLoading,
    startWorkout,
    addExerciseToWorkout,
    removeExerciseFromWorkout,
    addSetToExercise,
    updateSet,
    removeSet,
    completeWorkout,
    cancelWorkout,
  } = useWorkouts();

  const [showExerciseSelector, setShowExerciseSelector] = useState(false);
  const [workoutName, setWorkoutName] = useState('');

  useEffect(() => {
    if (currentWorkout) {
      setWorkoutName(currentWorkout.name);
    }
  }, [currentWorkout]);

  const handleStartWorkout = () => {
    const name = workoutName.trim() || undefined;
    startWorkout(name);
  };

  const handleCompleteWorkout = () => {
    const completed = completeWorkout();
    if (completed) {
      router.push('/history');
    }
  };

  const handleCancelWorkout = () => {
    if (confirm('Are you sure you want to cancel this workout? All progress will be lost.')) {
      cancelWorkout();
    }
  };

  if (isLoading) {
    return (
      <div className="py-6 text-center">
        <p className="text-muted">Loading...</p>
      </div>
    );
  }

  // No active workout - show start screen
  if (!currentWorkout) {
    return (
      <div className="py-6">
        <header className="page-header">
          <h1 className="page-title">New Workout</h1>
        </header>

        <div className="card mb-6">
          <label className="label">Workout Name (optional)</label>
          <input
            type="text"
            className="input"
            placeholder={`Workout ${new Date().toLocaleDateString()}`}
            value={workoutName}
            onChange={e => setWorkoutName(e.target.value)}
          />
        </div>

        <button
          className="btn btn-primary btn-lg btn-block"
          onClick={handleStartWorkout}
        >
          Start Empty Workout
        </button>

        <p className="text-muted text-center mt-4" style={{ fontSize: '0.875rem' }}>
          Add exercises as you go, or start from a template
        </p>
      </div>
    );
  }

  // Active workout
  return (
    <div className="py-6">
      <header className="flex justify-between items-center mb-6">
        <div>
          <h1 style={{ fontSize: '1.5rem', fontWeight: 700 }}>
            {currentWorkout.name}
          </h1>
          <p className="text-muted" style={{ fontSize: '0.875rem' }}>
            Started {new Date(currentWorkout.date).toLocaleTimeString([], {
              hour: '2-digit',
              minute: '2-digit',
            })}
          </p>
        </div>
        <button className="btn btn-ghost btn-sm" onClick={handleCancelWorkout}>
          <X size={20} />
        </button>
      </header>

      <Timer />

      <div className="mt-6">
        {currentWorkout.exercises.map(exercise => (
          <WorkoutExerciseCard
            key={exercise.id}
            workoutExercise={exercise}
            onAddSet={() => addSetToExercise(exercise.id)}
            onUpdateSet={(setId, updates) =>
              updateSet(exercise.id, setId, updates)
            }
            onRemoveSet={setId => removeSet(exercise.id, setId)}
            onRemoveExercise={() => removeExerciseFromWorkout(exercise.id)}
          />
        ))}
      </div>

      <button
        className="btn btn-secondary btn-block mb-4"
        onClick={() => setShowExerciseSelector(true)}
      >
        <Plus size={20} />
        Add Exercise
      </button>

      {currentWorkout.exercises.length > 0 && (
        <button
          className="btn btn-primary btn-lg btn-block"
          onClick={handleCompleteWorkout}
        >
          <Check size={20} />
          Complete Workout
        </button>
      )}

      <ExerciseSelector
        isOpen={showExerciseSelector}
        onClose={() => setShowExerciseSelector(false)}
        onSelect={addExerciseToWorkout}
      />
    </div>
  );
}
