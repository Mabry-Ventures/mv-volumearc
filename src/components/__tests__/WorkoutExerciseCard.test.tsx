import { render, screen, fireEvent } from '@testing-library/react';
import { WorkoutExerciseCard } from '@/components/WorkoutExerciseCard';
import type { WorkoutExercise } from '@/types';

const workoutExercise: WorkoutExercise = {
  id: 'ex-1',
  exercise: {
    id: 'bench-press',
    name: 'Bench Press',
    category: 'barbell',
    muscleGroups: ['chest'],
  },
  sets: [
    {
      id: 'set-1',
      reps: 5,
      weight: 100,
      unit: 'lbs',
      completed: false,
    },
  ],
};

it('updates set values and toggles completion', () => {
  const onAddSet = jest.fn();
  const onUpdateSet = jest.fn();
  const onRemoveSet = jest.fn();
  const onRemoveExercise = jest.fn();

  const { container } = render(
    <WorkoutExerciseCard
      workoutExercise={workoutExercise}
      onAddSet={onAddSet}
      onUpdateSet={onUpdateSet}
      onRemoveSet={onRemoveSet}
      onRemoveExercise={onRemoveExercise}
    />
  );

  const inputs = screen.getAllByRole('spinbutton');
  fireEvent.change(inputs[0], { target: { value: '150' } });
  expect(onUpdateSet).toHaveBeenCalledWith('set-1', { weight: 150 });

  fireEvent.change(inputs[1], { target: { value: '8' } });
  expect(onUpdateSet).toHaveBeenCalledWith('set-1', { reps: 8 });

  const completeButton = container.querySelector('.set-complete') as HTMLElement;
  fireEvent.click(completeButton);
  expect(onUpdateSet).toHaveBeenCalledWith('set-1', { completed: true });
});
