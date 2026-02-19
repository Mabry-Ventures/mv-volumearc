import { render, screen } from '@testing-library/react';
import { StatsCard } from '@/components/StatsCard';

it('renders value and label', () => {
  render(<StatsCard value={42} label="Total Workouts" />);
  expect(screen.getByText('42')).toBeInTheDocument();
  expect(screen.getByText('Total Workouts')).toBeInTheDocument();
});
