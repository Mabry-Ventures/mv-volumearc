import { render, screen } from '@testing-library/react';
import { Navigation } from '@/components/Navigation';

it('highlights the active route', () => {
  const mockUsePathname = (
    globalThis as typeof globalThis & { __mockUsePathname: jest.Mock }
  ).__mockUsePathname;
  mockUsePathname.mockReturnValue('/history');

  render(<Navigation />);

  const historyLink = screen.getByText('History').closest('a');
  expect(historyLink).toHaveClass('active');
});
