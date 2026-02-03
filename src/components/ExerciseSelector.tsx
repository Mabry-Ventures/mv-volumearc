'use client';

import { useState } from 'react';
import { X, Search } from 'lucide-react';
import { Exercise, ExerciseCategory } from '@/types';
import { defaultExercises } from '@/data/exercises';

interface ExerciseSelectorProps {
  isOpen: boolean;
  onClose: () => void;
  onSelect: (exercise: Exercise) => void;
}

const CATEGORIES: { value: ExerciseCategory | 'all'; label: string }[] = [
  { value: 'all', label: 'All' },
  { value: 'barbell', label: 'Barbell' },
  { value: 'dumbbell', label: 'Dumbbell' },
  { value: 'machine', label: 'Machine' },
  { value: 'bodyweight', label: 'Bodyweight' },
  { value: 'cable', label: 'Cable' },
  { value: 'cardio', label: 'Cardio' },
];

export const ExerciseSelector = ({
  isOpen,
  onClose,
  onSelect,
}: ExerciseSelectorProps) => {
  const [search, setSearch] = useState('');
  const [category, setCategory] = useState<ExerciseCategory | 'all'>('all');

  if (!isOpen) return null;

  const filteredExercises = defaultExercises.filter(exercise => {
    const matchesSearch = exercise.name
      .toLowerCase()
      .includes(search.toLowerCase());
    const matchesCategory =
      category === 'all' || exercise.category === category;
    return matchesSearch && matchesCategory;
  });

  const handleSelect = (exercise: Exercise) => {
    onSelect(exercise);
    onClose();
    setSearch('');
    setCategory('all');
  };

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal" onClick={e => e.stopPropagation()}>
        <div className="modal-header">
          <h2 className="modal-title">Add Exercise</h2>
          <button className="btn btn-ghost btn-sm" onClick={onClose}>
            <X size={20} />
          </button>
        </div>

        <div className="modal-body">
          <div className="flex gap-2 mb-4">
            <div className="flex-1" style={{ position: 'relative' }}>
              <Search
                size={18}
                style={{
                  position: 'absolute',
                  left: '0.75rem',
                  top: '50%',
                  transform: 'translateY(-50%)',
                  color: 'var(--muted)',
                }}
              />
              <input
                type="text"
                className="input"
                placeholder="Search exercises..."
                value={search}
                onChange={e => setSearch(e.target.value)}
                style={{ paddingLeft: '2.5rem' }}
              />
            </div>
          </div>

          <div className="flex gap-2 mb-4" style={{ overflowX: 'auto', paddingBottom: '0.5rem' }}>
            {CATEGORIES.map(cat => (
              <button
                key={cat.value}
                className={`btn btn-sm ${
                  category === cat.value ? 'btn-primary' : 'btn-secondary'
                }`}
                onClick={() => setCategory(cat.value)}
                style={{ whiteSpace: 'nowrap' }}
              >
                {cat.label}
              </button>
            ))}
          </div>

          <div>
            {filteredExercises.map(exercise => (
              <div
                key={exercise.id}
                className="exercise-list-item"
                onClick={() => handleSelect(exercise)}
              >
                <div className="exercise-info">
                  <div className="exercise-name">{exercise.name}</div>
                  <div className="exercise-muscles">
                    {exercise.muscleGroups.join(', ')}
                  </div>
                </div>
                <span className="category-badge">{exercise.category}</span>
              </div>
            ))}

            {filteredExercises.length === 0 && (
              <div className="empty-state">
                <p className="text-muted">No exercises found</p>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};
