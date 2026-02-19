'use client';

import { useEffect, useState } from 'react';
import { Trash2, Download, Upload, Sparkles } from 'lucide-react';
import { storage } from '@/utils/storage';
import type { AiUserPreferences } from '@/types';

const MAX_IMPORT_FILE_SIZE_BYTES = 5 * 1024 * 1024;

const aiFeatureFlags = [
  { label: 'Workout Plan', value: process.env.NEXT_PUBLIC_AI_ENABLE_WORKOUT_PLAN !== 'false' },
  { label: 'Live Coach', value: process.env.NEXT_PUBLIC_AI_ENABLE_LIVE_COACH !== 'false' },
  { label: 'Post Workout', value: process.env.NEXT_PUBLIC_AI_ENABLE_POST_WORKOUT !== 'false' },
  { label: 'Risk Analysis', value: process.env.NEXT_PUBLIC_AI_ENABLE_RISK_ANALYSIS !== 'false' },
  { label: 'Log Parser', value: process.env.NEXT_PUBLIC_AI_ENABLE_LOG_PARSER !== 'false' },
  { label: 'Transcription', value: process.env.NEXT_PUBLIC_AI_ENABLE_TRANSCRIBE !== 'false' },
];

export default function SettingsPage() {
  const [unit, setUnit] = useState<'lbs' | 'kg'>('lbs');
  const [workoutCount, setWorkoutCount] = useState(0);
  const [aiPreferences, setAiPreferences] = useState<AiUserPreferences | null>(null);

  useEffect(() => {
    const settings = storage.getSettings();
    setUnit(settings.unit);
    setWorkoutCount(storage.getWorkouts().length);
    setAiPreferences(storage.getAiPreferences());
  }, []);

  const saveAiPreferences = (next: AiUserPreferences) => {
    setAiPreferences(next);
    storage.saveAiPreferences(next);
  };

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
      aiPreferences: storage.getAiPreferences(),
      aiCache: storage.getAiCache(),
      exportedAt: new Date().toISOString(),
    };

    const blob = new Blob([JSON.stringify(data, null, 2)], {
      type: 'application/json',
    });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = `beast-mode-backup-${new Date().toISOString().split('T')[0]}.json`;
    document.body.appendChild(anchor);
    anchor.click();
    document.body.removeChild(anchor);
    URL.revokeObjectURL(url);
  };

  const handleImportData = (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;

    if (file.size > MAX_IMPORT_FILE_SIZE_BYTES) {
      alert('Import file is too large. Please use a backup under 5 MB.');
      event.target.value = '';
      return;
    }

    const reader = new FileReader();
    reader.onload = e => {
      try {
        const data = JSON.parse(String(e.target?.result ?? ''));
        const imported = storage.importData(data);
        if (!imported) {
          alert('Failed to import data. Please check the file format.');
          event.target.value = '';
          return;
        }

        alert('Data imported successfully!');
        event.target.value = '';
        window.location.reload();
      } catch {
        alert('Failed to import data. Please check the file format.');
        event.target.value = '';
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
            type="button"
            className={`btn flex-1 ${unit === 'lbs' ? 'btn-primary' : 'btn-secondary'}`}
            onClick={() => handleUnitChange('lbs')}
          >
            Pounds (lbs)
          </button>
          <button
            type="button"
            className={`btn flex-1 ${unit === 'kg' ? 'btn-primary' : 'btn-secondary'}`}
            onClick={() => handleUnitChange('kg')}
          >
            Kilograms (kg)
          </button>
        </div>
      </div>

      {aiPreferences && (
        <div className="card mb-4">
          <h3 className="mb-3" style={{ fontWeight: 600 }}>
            <Sparkles size={18} style={{ display: 'inline', marginRight: '0.5rem' }} />
            AI Preferences
          </h3>

          <label className="label" htmlFor="ai-coaching-style">Coaching Style</label>
          <select
            id="ai-coaching-style"
            className="input mb-3"
            value={aiPreferences.coachingStyle}
            onChange={event =>
              saveAiPreferences({
                ...aiPreferences,
                coachingStyle: event.target.value as AiUserPreferences['coachingStyle'],
              })
            }
          >
            <option value="direct">Direct</option>
            <option value="encouraging">Encouraging</option>
            <option value="technical">Technical</option>
          </select>

          <label className="label" htmlFor="ai-verbosity">Response Verbosity</label>
          <select
            id="ai-verbosity"
            className="input mb-3"
            value={aiPreferences.verbosity}
            onChange={event =>
              saveAiPreferences({
                ...aiPreferences,
                verbosity: event.target.value as AiUserPreferences['verbosity'],
              })
            }
          >
            <option value="brief">Brief</option>
            <option value="balanced">Balanced</option>
            <option value="detailed">Detailed</option>
          </select>

          <label className="label" htmlFor="ai-risk-sensitivity">Risk Sensitivity</label>
          <select
            id="ai-risk-sensitivity"
            className="input mb-3"
            value={aiPreferences.riskSensitivity}
            onChange={event =>
              saveAiPreferences({
                ...aiPreferences,
                riskSensitivity: event.target.value as AiUserPreferences['riskSensitivity'],
              })
            }
          >
            <option value="low">Low</option>
            <option value="medium">Medium</option>
            <option value="high">High</option>
          </select>

          <label className="label" htmlFor="ai-daily-budget">Daily AI Budget (USD)</label>
          <input
            id="ai-daily-budget"
            type="number"
            className="input mb-3"
            min={0}
            max={100}
            step={0.1}
            value={aiPreferences.dailyBudgetUsd}
            onChange={event =>
              saveAiPreferences({
                ...aiPreferences,
                dailyBudgetUsd: Math.max(0, Number(event.target.value) || 0),
              })
            }
          />

          <div className="flex flex-col gap-2">
            <label className="flex items-center gap-2">
              <input
                type="checkbox"
                checked={aiPreferences.autoApplySuggestions}
                onChange={event =>
                  saveAiPreferences({
                    ...aiPreferences,
                    autoApplySuggestions: event.target.checked,
                  })
                }
              />
              Auto-apply AI suggestions
            </label>

            <label className="flex items-center gap-2">
              <input
                type="checkbox"
                checked={aiPreferences.shareFullHistory}
                onChange={event =>
                  saveAiPreferences({
                    ...aiPreferences,
                    shareFullHistory: event.target.checked,
                  })
                }
              />
              Share full history context with AI
            </label>

            <label className="flex items-center gap-2">
              <input
                type="checkbox"
                checked={aiPreferences.enableSpeechLogging}
                onChange={event =>
                  saveAiPreferences({
                    ...aiPreferences,
                    enableSpeechLogging: event.target.checked,
                  })
                }
              />
              Enable speech logging
            </label>
          </div>

          <div className="mt-4">
            <p className="text-muted" style={{ fontSize: '0.75rem' }}>
              Feature Flags
            </p>
            <div className="grid grid-cols-2 gap-2 mt-2">
              {aiFeatureFlags.map(flag => (
                <div key={flag.label} className="card" style={{ padding: '0.5rem' }}>
                  <div style={{ fontSize: '0.75rem' }}>{flag.label}</div>
                  <div style={{ fontWeight: 600 }}>{flag.value ? 'Enabled' : 'Disabled'}</div>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}

      <div className="card mb-4">
        <h3 className="mb-3" style={{ fontWeight: 600 }}>Data Management</h3>
        <p className="text-muted mb-4" style={{ fontSize: '0.875rem' }}>
          You have {workoutCount} workout{workoutCount !== 1 ? 's' : ''} saved.
        </p>

        <div className="flex flex-col gap-2">
          <button type="button" className="btn btn-secondary" onClick={handleExportData}>
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
        <button type="button" className="btn btn-danger" onClick={handleClearData}>
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
