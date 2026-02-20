'use client';

import { useEffect, useState } from 'react';
import { Trash2, Download, Upload, Sparkles, SlidersHorizontal, ShieldCheck } from 'lucide-react';
import { storage } from '@/utils/storage';
import { Button, Card, Input, SegmentedControl } from '@/components';
import type { AiUserPreferences, WorkoutUxPreferences } from '@/types';

const MAX_IMPORT_FILE_SIZE_BYTES = 5 * 1024 * 1024;

const aiFeatureFlags = [
  { label: 'Workout Plan', value: process.env.NEXT_PUBLIC_AI_ENABLE_WORKOUT_PLAN !== 'false' },
  { label: 'Live Coach', value: process.env.NEXT_PUBLIC_AI_ENABLE_LIVE_COACH !== 'false' },
  { label: 'Post Workout', value: process.env.NEXT_PUBLIC_AI_ENABLE_POST_WORKOUT !== 'false' },
  { label: 'Risk Analysis', value: process.env.NEXT_PUBLIC_AI_ENABLE_RISK_ANALYSIS !== 'false' },
  { label: 'Log Parser', value: process.env.NEXT_PUBLIC_AI_ENABLE_LOG_PARSER !== 'false' },
  { label: 'Transcription', value: process.env.NEXT_PUBLIC_AI_ENABLE_TRANSCRIBE !== 'false' },
];

const riskOptions: Array<{ value: AiUserPreferences['riskSensitivity']; label: string }> = [
  { value: 'low', label: 'Low' },
  { value: 'medium', label: 'Medium' },
  { value: 'high', label: 'High' },
];

const coachingOptions: Array<{ value: AiUserPreferences['coachingStyle']; label: string }> = [
  { value: 'direct', label: 'Direct' },
  { value: 'encouraging', label: 'Encouraging' },
  { value: 'technical', label: 'Technical' },
];

const verbosityOptions: Array<{ value: AiUserPreferences['verbosity']; label: string }> = [
  { value: 'brief', label: 'Brief' },
  { value: 'balanced', label: 'Balanced' },
  { value: 'detailed', label: 'Detailed' },
];

export default function SettingsPage() {
  const [unit, setUnit] = useState<'lbs' | 'kg'>('lbs');
  const [workoutCount, setWorkoutCount] = useState(0);
  const [aiPreferences, setAiPreferences] = useState<AiUserPreferences | null>(null);
  const [uxPreferences, setUxPreferences] = useState<WorkoutUxPreferences | null>(null);

  useEffect(() => {
    const settings = storage.getSettings();
    setUnit(settings.unit);
    setWorkoutCount(storage.getWorkouts().length);
    setAiPreferences(storage.getAiPreferences());
    setUxPreferences(storage.getWorkoutUxPreferences());
  }, []);

  const saveAiPreferences = (next: AiUserPreferences) => {
    setAiPreferences(next);
    storage.saveAiPreferences(next);
  };

  const saveUxPreferences = (next: WorkoutUxPreferences) => {
    setUxPreferences(next);
    storage.saveWorkoutUxPreferences(next);
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
      workoutUxPreferences: storage.getWorkoutUxPreferences(),
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
    if (confirm('Are you sure you want to delete ALL data? This cannot be undone!')) {
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
        <p className="text-muted" style={{ fontSize: '0.85rem' }}>
          Configure AI coaching style, workout speed controls, and privacy defaults.
        </p>
      </header>

      <Card className="mb-4" elevated>
        <h3 className="mb-3" style={{ fontWeight: 700 }}>Weight Unit</h3>
        <div className="flex gap-2">
          <Button
            variant={unit === 'lbs' ? 'primary' : 'secondary'}
            block
            onClick={() => handleUnitChange('lbs')}
          >
            Pounds (lbs)
          </Button>
          <Button
            variant={unit === 'kg' ? 'primary' : 'secondary'}
            block
            onClick={() => handleUnitChange('kg')}
          >
            Kilograms (kg)
          </Button>
        </div>
      </Card>

      {uxPreferences && (
        <Card className="mb-4" elevated>
          <h3 className="mb-3" style={{ fontWeight: 700 }}>
            <SlidersHorizontal size={18} style={{ display: 'inline', marginRight: '0.5rem' }} />
            Workout UX Preferences
          </h3>

          <div className="grid grid-cols-2 gap-2 mb-3">
            <label className="card" style={{ padding: '0.75rem' }}>
              <span style={{ fontWeight: 640, fontSize: '0.85rem' }}>Compact Mode</span>
              <p className="text-muted" style={{ fontSize: '0.75rem', marginTop: '0.2rem' }}>
                Reduce spacing for faster set logging.
              </p>
              <input
                type="checkbox"
                checked={uxPreferences.compactMode}
                onChange={event =>
                  saveUxPreferences({
                    ...uxPreferences,
                    compactMode: event.target.checked,
                  })
                }
                style={{ marginTop: '0.45rem' }}
              />
            </label>

            <label className="card" style={{ padding: '0.75rem' }}>
              <span style={{ fontWeight: 640, fontSize: '0.85rem' }}>Show Previous Values</span>
              <p className="text-muted" style={{ fontSize: '0.75rem', marginTop: '0.2rem' }}>
                Keep last session values visible inline.
              </p>
              <input
                type="checkbox"
                checked={uxPreferences.showPreviousValues}
                onChange={event =>
                  saveUxPreferences({
                    ...uxPreferences,
                    showPreviousValues: event.target.checked,
                  })
                }
                style={{ marginTop: '0.45rem' }}
              />
            </label>

            <label className="card" style={{ padding: '0.75rem' }}>
              <span style={{ fontWeight: 640, fontSize: '0.85rem' }}>Haptic Feedback</span>
              <p className="text-muted" style={{ fontSize: '0.75rem', marginTop: '0.2rem' }}>
                Trigger quick vibration on set completion.
              </p>
              <input
                type="checkbox"
                checked={uxPreferences.enableHaptics}
                onChange={event =>
                  saveUxPreferences({
                    ...uxPreferences,
                    enableHaptics: event.target.checked,
                  })
                }
                style={{ marginTop: '0.45rem' }}
              />
            </label>

            <label className="card" style={{ padding: '0.75rem' }}>
              <span style={{ fontWeight: 640, fontSize: '0.85rem' }}>Auto Rest Timer</span>
              <p className="text-muted" style={{ fontSize: '0.75rem', marginTop: '0.2rem' }}>
                Start timer automatically after completing sets.
              </p>
              <input
                type="checkbox"
                checked={uxPreferences.autoStartRestTimer}
                onChange={event =>
                  saveUxPreferences({
                    ...uxPreferences,
                    autoStartRestTimer: event.target.checked,
                  })
                }
                style={{ marginTop: '0.45rem' }}
              />
            </label>
          </div>

          <Input
            id="ux-rest-timer-default"
            label="Default Rest Timer (seconds)"
            type="number"
            min={15}
            max={300}
            value={uxPreferences.restTimerDefaultSeconds}
            onChange={event =>
              saveUxPreferences({
                ...uxPreferences,
                restTimerDefaultSeconds: Math.max(15, Math.min(300, Number(event.target.value) || 90)),
              })
            }
          />
        </Card>
      )}

      {aiPreferences && (
        <Card className="mb-4" elevated>
          <h3 className="mb-3" style={{ fontWeight: 700 }}>
            <Sparkles size={18} style={{ display: 'inline', marginRight: '0.5rem' }} />
            AI Preferences
          </h3>

          <label className="label" htmlFor="ai-coaching-style">Coaching Style</label>
          <SegmentedControl
            ariaLabel="AI coaching style"
            value={aiPreferences.coachingStyle}
            options={coachingOptions}
            onChange={value => saveAiPreferences({ ...aiPreferences, coachingStyle: value })}
          />

          <div className="mt-3">
            <label className="label" htmlFor="ai-verbosity">Response Verbosity</label>
            <SegmentedControl
              ariaLabel="AI response verbosity"
              value={aiPreferences.verbosity}
              options={verbosityOptions}
              onChange={value => saveAiPreferences({ ...aiPreferences, verbosity: value })}
            />
          </div>

          <div className="mt-3">
            <label className="label" htmlFor="ai-risk-sensitivity">Risk Sensitivity</label>
            <SegmentedControl
              ariaLabel="AI risk sensitivity"
              value={aiPreferences.riskSensitivity}
              options={riskOptions}
              onChange={value => saveAiPreferences({ ...aiPreferences, riskSensitivity: value })}
            />
          </div>

          <Input
            id="ai-daily-budget"
            label="Daily AI Budget (USD)"
            type="number"
            className="mt-3"
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

          <div className="grid grid-cols-2 gap-2 mt-3">
            <label className="card" style={{ padding: '0.75rem' }}>
              <span style={{ fontWeight: 640, fontSize: '0.85rem' }}>Auto-apply AI suggestions</span>
              <input
                type="checkbox"
                checked={aiPreferences.autoApplySuggestions}
                onChange={event =>
                  saveAiPreferences({
                    ...aiPreferences,
                    autoApplySuggestions: event.target.checked,
                  })
                }
                style={{ marginTop: '0.45rem' }}
              />
            </label>

            <label className="card" style={{ padding: '0.75rem' }}>
              <span style={{ fontWeight: 640, fontSize: '0.85rem' }}>Enable speech logging</span>
              <input
                type="checkbox"
                checked={aiPreferences.enableSpeechLogging}
                onChange={event =>
                  saveAiPreferences({
                    ...aiPreferences,
                    enableSpeechLogging: event.target.checked,
                  })
                }
                style={{ marginTop: '0.45rem' }}
              />
            </label>

            <label className="card" style={{ padding: '0.75rem' }}>
              <span style={{ fontWeight: 640, fontSize: '0.85rem' }}>Share full history context</span>
              <input
                type="checkbox"
                checked={aiPreferences.shareFullHistory}
                onChange={event =>
                  saveAiPreferences({
                    ...aiPreferences,
                    shareFullHistory: event.target.checked,
                  })
                }
                style={{ marginTop: '0.45rem' }}
              />
            </label>

            <div className="card" style={{ padding: '0.75rem' }}>
              <span style={{ fontWeight: 640, fontSize: '0.85rem' }}>Feature Flags</span>
              <p className="text-muted" style={{ fontSize: '0.75rem', marginTop: '0.2rem' }}>
                Runtime visibility for AI endpoints.
              </p>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-2 mt-2">
            {aiFeatureFlags.map(flag => (
              <div key={flag.label} className="card" style={{ padding: '0.5rem' }}>
                <div style={{ fontSize: '0.75rem' }}>{flag.label}</div>
                <div style={{ fontWeight: 600 }}>{flag.value ? 'Enabled' : 'Disabled'}</div>
              </div>
            ))}
          </div>
        </Card>
      )}

      <Card className="mb-4" elevated>
        <h3 className="mb-3" style={{ fontWeight: 700 }}>Data Management</h3>
        <p className="text-muted mb-3" style={{ fontSize: '0.875rem' }}>
          You have {workoutCount} workout{workoutCount !== 1 ? 's' : ''} saved.
        </p>

        <div className="flex flex-col gap-2">
          <Button variant="secondary" onClick={handleExportData}>
            <Download size={18} />
            Export Data
          </Button>

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

        <div className="card mt-3" style={{ padding: '0.75rem' }}>
          <p style={{ fontWeight: 650, marginBottom: '0.2rem' }}>
            <ShieldCheck size={16} style={{ display: 'inline', marginRight: '0.35rem' }} />
            Privacy Defaults
          </p>
          <p className="text-muted" style={{ fontSize: '0.8rem' }}>
            Your workout history is local-first. AI calls are server-routed and controlled by your feature flags and budget.
          </p>
        </div>
      </Card>

      <Card>
        <h3 className="mb-3 text-danger" style={{ fontWeight: 700 }}>
          Danger Zone
        </h3>
        <p className="text-muted mb-4" style={{ fontSize: '0.875rem' }}>
          Once you delete your data, there is no going back. Please be certain.
        </p>
        <Button variant="danger" onClick={handleClearData}>
          <Trash2 size={18} />
          Delete All Data
        </Button>
      </Card>

      <div className="text-center mt-8 text-muted" style={{ fontSize: '0.75rem' }}>
        <p>Beast Mode v1.0.0</p>
        <p className="mt-1">Made with determination</p>
      </div>
    </div>
  );
}
