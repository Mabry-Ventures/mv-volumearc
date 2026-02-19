import { fireEvent, render, screen } from '@testing-library/react';
import { ExerciseSelector } from '@/components/ExerciseSelector';

it('filters exercises and selects one', () => {
  const onSelect = jest.fn();
  const onClose = jest.fn();

  render(
    <ExerciseSelector
      isOpen
      onClose={onClose}
      onSelect={onSelect}
    />
  );

  const input = screen.getByPlaceholderText('Search exercises...');
  fireEvent.change(input, { target: { value: 'Bench Press' } });

  const benchPress = screen.getByText('Bench Press');
  expect(benchPress).toBeInTheDocument();

  fireEvent.click(benchPress);
  expect(onSelect).toHaveBeenCalled();
  expect(onClose).toHaveBeenCalled();
});
