'use client';

import { useEffect, useState } from 'react';
import { Trash2, Download, Upload } from 'lucide-react';
import { storage } from '@/utils/storage';

export default function SettingsPage() {
  const [unit, setUnit] = useState<'lbs' | 'kg'>('lbs');
  const [workoutCount, setWorkoutCount] = useState(0);

  useEffect(() => {
    const settings = storage.getSettings();
    setUnit(settings.unit);
    setWorkoutCount(storage.getWorkouts().length);
  }, []);

  const handleUnitChange = (newUnit: 'lbs' | 'kg') => {
    setUnit(newUnit);
    storage.saveSettings({ unit: newUnit });
  };

  const handleExportData = () => {
    const data = {
      workouts: storage.getWorkouts(),
      templates: storage.getTemplates(),
      personalRecords: storage.getPersonalRecords(),
      settings: storage.getSettings(),
      exportedAt: new Date().toISOString(),
    };

    const blob = new Blob([JSON.stringify(data, null, 2)], {
      type: 'application/json',
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `beast-mode-backup-${new Date().toISOString().split('T')[0]}.json`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  };

  const handleImportData = (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = e => {
      try {
        const data = JSON.parse(e.target?.result as string);

        if (data.workouts) storage.saveWorkouts(data.workouts);
        if (data.templates) storage.saveTemplates(data.templates);
        if (data.personalRecords) storage.savePersonalRecords(data.personalRecords);
        if (data.settings) storage.saveSettings(data.settings);

        alert('Data imported successfully!');
        window.location.reload();
      } catch {
        alert('Failed to import data. Please check the file format.');
      }
    };
    reader.readAsText(file);
  };

  const handleClearData = () => {
    if (
      confirm(
        'Are you sure you want to delete ALL data? This cannot be undone!'
      )
    ) {
      if (confirm('Really? All your workout history will be lost forever!')) {
        storage.clearAll();
        alert('All data has been cleared.');
        window.location.reload();
      }
    }
  };

  return (
    <div className="py-6">
      <header className="page-header">
        <h1 className="page-title">Settings</h1>
      </header>

      <div className="card mb-4">
        <h3 className="mb-3" style={{ fontWeight: 600 }}>Weight Unit</h3>
        <div className="flex gap-2">
          <button
            className={`btn flex-1 ${unit === 'lbs' ? 'btn-primary' : 'btn-secondary'}`}
            onClick={() => handleUnitChange('lbs')}
          >
            Pounds (lbs)
          </button>
          <button
            className={`btn flex-1 ${unit === 'kg' ? 'btn-primary' : 'btn-secondary'}`}
            onClick={() => handleUnitChange('kg')}
          >
            Kilograms (kg)
          </button>
        </div>
      </div>

      <div className="card mb-4">
        <h3 className="mb-3" style={{ fontWeight: 600 }}>Data Management</h3>
        <p className="text-muted mb-4" style={{ fontSize: '0.875rem' }}>
          You have {workoutCount} workout{workoutCount !== 1 ? 's' : ''} saved.
        </p>

        <div className="flex flex-col gap-2">
          <button className="btn btn-secondary" onClick={handleExportData}>
            <Download size={18} />
            Export Data
          </button>

          <label className="btn btn-secondary" style={{ cursor: 'pointer' }}>
            <Upload size={18} />
            Import Data
            <input
              type="file"
              accept=".json"
              onChange={handleImportData}
              style={{ display: 'none' }}
            />
          </label>
        </div>
      </div>

      <div className="card">
        <h3 className="mb-3 text-danger" style={{ fontWeight: 600 }}>
          Danger Zone
        </h3>
        <p className="text-muted mb-4" style={{ fontSize: '0.875rem' }}>
          Once you delete your data, there is no going back. Please be certain.
        </p>
        <button className="btn btn-danger" onClick={handleClearData}>
          <Trash2 size={18} />
          Delete All Data
        </button>
      </div>

      <div className="text-center mt-8 text-muted" style={{ fontSize: '0.75rem' }}>
        <p>Beast Mode v1.0.0</p>
        <p className="mt-1">Made with determination</p>
      </div>
    </div>
  );
}
