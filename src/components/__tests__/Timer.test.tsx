import { fireEvent, render, screen } from '@testing-library/react';
import { Timer } from '@/components/Timer';

it('starts and shows pause state', () => {
  render(<Timer />);

  const startButton = screen.getByRole('button', { name: /start/i });
  fireEvent.click(startButton);

  expect(screen.getByRole('button', { name: /pause/i })).toBeInTheDocument();
});
