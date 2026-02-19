'use client';

import { Plus, Trash2, Check } from 'lucide-react';
import type { WorkoutExercise, WorkoutSet } from '@/types';

interface WorkoutExerciseCardProps {
  workoutExercise: WorkoutExercise;
  onAddSet: () => void;
  onUpdateSet: (setId: string, updates: Partial<WorkoutSet>) => void;
  onRemoveSet: (setId: string) => void;
  onRemoveExercise: () => void;
}

export const WorkoutExerciseCard = ({
  workoutExercise,
  onAddSet,
  onUpdateSet,
  onRemoveSet,
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
  };

  return (
    <div className="exercise-card mb-4">
      <div className="exercise-header">
        <div>
          <div className="exercise-name">{workoutExercise.exercise.name}</div>
          <div className="text-muted" style={{ fontSize: '0.75rem' }}>
            {workoutExercise.exercise.muscleGroups.join(', ')}
          </div>
        </div>
        <button type="button" className="btn btn-ghost btn-sm" onClick={onRemoveExercise}>
          <Trash2 size={18} />
        </button>
      </div>

      <div className="exercise-sets">
        <div className="set-row" style={{ fontWeight: 600, fontSize: '0.75rem', color: 'var(--muted)' }}>
          <div className="text-center">SET</div>
          <div className="text-center">WEIGHT</div>
          <div className="text-center">REPS</div>
          <div></div>
        </div>

        {workoutExercise.sets.map((set, index) => (
          <div key={set.id} className="set-row">
            <div className="set-number">{index + 1}</div>
            <input
              type="number"
              className="set-input"
              placeholder="0"
              value={set.weight || ''}
              onChange={e =>
                handleNumberChange(set.id, 'weight', e.target.value)
              }
            />
            <input
              type="number"
              className="set-input"
              placeholder="0"
              value={set.reps || ''}
              onChange={e =>
                handleNumberChange(set.id, 'reps', e.target.value)
              }
            />
            <button
              type="button"
              className={`set-complete ${set.completed ? 'completed' : ''}`}
              onClick={() => onUpdateSet(set.id, { completed: !set.completed })}
            >
              {set.completed && <Check size={16} color="white" />}
            </button>
          </div>
        ))}

        <div className="flex gap-2 mt-3 p-2">
          <button type="button" className="btn btn-secondary btn-sm flex-1" onClick={onAddSet}>
            <Plus size={16} />
            Add Set
          </button>
          {workoutExercise.sets.length > 1 && (
            <button
              type="button"
              className="btn btn-ghost btn-sm"
              onClick={() =>
                onRemoveSet(workoutExercise.sets[workoutExercise.sets.length - 1].id)
              }
            >
              <Trash2 size={16} />
            </button>
          )}
        </div>
      </div>
    </div>
  );
};
