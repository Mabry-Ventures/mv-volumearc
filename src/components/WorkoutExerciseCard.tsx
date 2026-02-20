'use client';

import { Plus, Trash2, Check, Copy } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { ExerciseRow } from '@/components/ui/ExerciseRow';
import { SetRow } from '@/components/ui/SetRow';
import { uiAnalytics } from '@/lib/analytics';
import type { WorkoutExercise, WorkoutSet } from '@/types';

interface WorkoutExerciseCardProps {
  workoutExercise: WorkoutExercise;
  previousSets?: Array<{ weight: number; reps: number; unit: 'lbs' | 'kg' }>;
  onAddSet: () => void;
  onUpdateSet: (setId: string, updates: Partial<WorkoutSet>) => void;
  onRemoveSet: (setId: string) => void;
  onDuplicateSet?: (setId: string) => void;
  onSetCompleted?: (set: WorkoutSet) => void;
  onRemoveExercise: () => void;
}

export const WorkoutExerciseCard = ({
  workoutExercise,
  previousSets = [],
  onAddSet,
  onUpdateSet,
  onRemoveSet,
  onDuplicateSet,
  onSetCompleted,
  onRemoveExercise,
}: WorkoutExerciseCardProps) => {
  const handleNumberChange = (
    setId: string,
    field: 'weight' | 'reps',
    rawValue: string
  ) => {
    if (rawValue === '') {
      onUpdateSet(setId, { [field]: 0 } as Partial<WorkoutSet>);
      return;
    }

    const parsed = Number(rawValue);
    if (!Number.isFinite(parsed)) return;

    onUpdateSet(setId, { [field]: Math.max(0, parsed) } as Partial<WorkoutSet>);
    uiAnalytics.trackSetAction('set_edit', {
      exerciseId: workoutExercise.exercise.id,
      field,
    });
  };

  return (
    <div className="exercise-card mb-4">
      <ExerciseRow
        title={workoutExercise.exercise.name}
        subtitle={workoutExercise.exercise.muscleGroups.join(', ')}
        rightSlot={
          <Button variant="ghost" size="sm" onClick={onRemoveExercise} aria-label="Remove exercise">
            <Trash2 size={16} />
          </Button>
        }
      >
        <div className="exercise-sets">
          {workoutExercise.sets.map((set, index) => {
            const previous = previousSets[index];
            const previousText = previous
              ? `${previous.weight}${previous.unit} x ${previous.reps}`
              : undefined;

            return (
              <SetRow
                key={set.id}
                setNumber={index + 1}
                previous={previousText}
                weightInput={
                  <input
                    type="number"
                    className="set-input"
                    placeholder="Weight"
                    value={set.weight || ''}
                    onChange={event => handleNumberChange(set.id, 'weight', event.target.value)}
                  />
                }
                repsInput={
                  <input
                    type="number"
                    className="set-input"
                    placeholder="Reps"
                    value={set.reps || ''}
                    onChange={event => handleNumberChange(set.id, 'reps', event.target.value)}
                  />
                }
                completeAction={
                  <button
                    type="button"
                    className={`set-complete ${set.completed ? 'completed' : ''}`}
                    aria-label={set.completed ? 'Mark set incomplete' : 'Mark set complete'}
                    onClick={() => {
                      const nextCompleted = !set.completed;
                      onUpdateSet(set.id, { completed: nextCompleted });
                      uiAnalytics.trackSetAction('set_complete_toggle', {
                        exerciseId: workoutExercise.exercise.id,
                        completed: nextCompleted,
                      });

                      if (nextCompleted) {
                        onSetCompleted?.(set);
                      }
                    }}
                  >
                    {set.completed && <Check size={16} color="white" />}
                  </button>
                }
                quickActions={
                  <>
                    {onDuplicateSet && (
                      <Button
                        variant="ghost"
                        size="sm"
                        onClick={() => {
                          onDuplicateSet(set.id);
                          uiAnalytics.trackSetAction('set_duplicate', {
                            exerciseId: workoutExercise.exercise.id,
                          });
                        }}
                        aria-label="Duplicate set"
                      >
                        <Copy size={14} />
                      </Button>
                    )}
                    {workoutExercise.sets.length > 1 && (
                      <Button
                        variant="ghost"
                        size="sm"
                        onClick={() => {
                          onRemoveSet(set.id);
                          uiAnalytics.trackSetAction('set_remove', {
                            exerciseId: workoutExercise.exercise.id,
                          });
                        }}
                        aria-label="Remove set"
                      >
                        <Trash2 size={14} />
                      </Button>
                    )}
                  </>
                }
              />
            );
          })}

          <div className="quick-actions">
            <Button
              variant="secondary"
              size="sm"
              className="flex-1"
              onClick={() => {
                onAddSet();
                uiAnalytics.trackSetAction('set_add', {
                  exerciseId: workoutExercise.exercise.id,
                });
              }}
            >
              <Plus size={16} />
              Add Set
            </Button>
          </div>
        </div>
      </ExerciseRow>
    </div>
  );
};
