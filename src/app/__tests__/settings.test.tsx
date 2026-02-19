import { render, screen, fireEvent } from '@testing-library/react';
import SettingsPage from '@/app/settings/page';
import { storage } from '@/utils/storage';

describe('SettingsPage', () => {
  it('renders settings and updates unit', async () => {
    render(<SettingsPage />);

    const kgButton = await screen.findByText('Kilograms (kg)');
    fireEvent.click(kgButton);

    expect(storage.getSettings().unit).toBe('kg');
  });

  it('exports data without crashing', async () => {
    render(<SettingsPage />);

    const exportButton = await screen.findByText('Export Data');
    fireEvent.click(exportButton);

    expect(global.URL.createObjectURL).toHaveBeenCalled();
  });
});
