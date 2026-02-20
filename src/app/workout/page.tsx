'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import {
  Plus,
  Check,
  X,
  Sparkles,
  Mic,
  MicOff,
  Wand2,
  ChevronDown,
  ChevronUp,
  Save,
  Share2,
  CalendarPlus,
  Zap,
} from 'lucide-react';
import { v4 as uuidv4 } from 'uuid';
import { useWorkouts } from '@/hooks/useWorkouts';
import { useAiWorkoutPlan } from '@/hooks/useAiWorkoutPlan';
import { useLiveCoach } from '@/hooks/useLiveCoach';
import { usePostWorkoutAi } from '@/hooks/usePostWorkoutAi';
import { useNaturalLanguageLog } from '@/hooks/useNaturalLanguageLog';
import { useProgressionPlan } from '@/hooks/useProgressionPlan';
import { Timer } from '@/components/Timer';
import { ExerciseSelector } from '@/components/ExerciseSelector';
import { WorkoutExerciseCard } from '@/components/WorkoutExerciseCard';
import { Button, Card, Input, ProgressRing, Toast } from '@/components';
import { storage } from '@/utils/storage';
import { buildHistoryDigest, buildHistoryDigestLite } from '@/lib/ai/contextBuilder';
import { uiAnalytics } from '@/lib/analytics';
import type { WorkoutSet, Workout, WorkoutTemplate, AiLiveCoachResponse } from '@/types';

const getLastSet = (workout: Workout | null): WorkoutSet | null => {
  if (!workout) return null;

  const sets = workout.exercises.flatMap(exercise => exercise.sets);
  if (sets.length === 0) return null;
  return sets[sets.length - 1];
};

const getElapsedMinutes = (startedAtIso: string): number => {
  const elapsedMs = Date.now() - new Date(startedAtIso).getTime();
  return Math.max(0, Math.round(elapsedMs / 60000));
};

const formatElapsed = (minutes: number): string => {
  const hours = Math.floor(minutes / 60);
  const mins = minutes % 60;
  if (hours > 0) return `${hours}h ${mins}m`;
  return `${mins}m`;
};

const buildPreviousSetLookup = (workouts: Workout[]) => {
  const lookup = new Map<string, Array<{ weight: number; reps: number; unit: 'lbs' | 'kg' }>>();

  const completed = workouts.filter(workout => workout.completed);
  const ordered = [...completed].sort(
    (a, b) => new Date(b.date).getTime() - new Date(a.date).getTime()
  );

  ordered.forEach(workout => {
    workout.exercises.forEach(exercise => {
      if (lookup.has(exercise.exercise.id)) return;

      lookup.set(
        exercise.exercise.id,
        exercise.sets.map(set => ({ weight: set.weight, reps: set.reps, unit: set.unit }))
      );
    });
  });

  return lookup;
};

const getCompletionProgress = (workout: Workout | null): number => {
  if (!workout) return 0;

  const allSets = workout.exercises.flatMap(exercise => exercise.sets);
  if (allSets.length === 0) return 0;

  const completedSets = allSets.filter(set => set.completed).length;
  return Math.round((completedSets / allSets.length) * 100);
};

export default function WorkoutPage() {
  const router = useRouter();
  const {
    workouts,
    currentWorkout,
    isLoading,
    startWorkout,
    startWorkoutWithPlan,
    addExerciseToWorkout,
    removeExerciseFromWorkout,
    addSetToExercise,
    updateSet,
    removeSet,
    duplicateSet,
    completeWorkout,
    cancelWorkout,
    applyParsedLogPatch,
  } = useWorkouts();

  const aiPlan = useAiWorkoutPlan();
  const liveCoach = useLiveCoach();
  const postWorkoutAi = usePostWorkoutAi();
  const naturalLanguageLog = useNaturalLanguageLog();
  const progressionPlan = useProgressionPlan();

  const [showExerciseSelector, setShowExerciseSelector] = useState(false);
  const [workoutName, setWorkoutName] = useState('');
  const [goal, setGoal] = useState('Build strength');
  const [durationMinutes, setDurationMinutes] = useState(45);
  const [equipmentCsv, setEquipmentCsv] = useState('barbell, dumbbell, machine');
  const [constraintsCsv, setConstraintsCsv] = useState('');
  const [quickLogText, setQuickLogText] = useState('');
  const [showCompletionCard, setShowCompletionCard] = useState(false);
  const [isRecording, setIsRecording] = useState(false);
  const [toastMessage, setToastMessage] = useState('');
  const [restTimerKickSeconds, setRestTimerKickSeconds] = useState<number | null>(null);
  const [isCoachCollapsed, setIsCoachCollapsed] = useState(true);

  const workoutNameInputId = 'workout-name';
  const goalInputId = 'ai-goal';
  const durationInputId = 'ai-duration-minutes';
  const equipmentInputId = 'ai-equipment';
  const constraintsInputId = 'ai-constraints';

  const recorderRef = useRef<MediaRecorder | null>(null);
  const recordingChunksRef = useRef<Blob[]>([]);

  const aiPreferences = useMemo(() => storage.getAiPreferences(), []);
  const uxPreferences = useMemo(() => storage.getWorkoutUxPreferences(), []);

  useEffect(() => {
    if (currentWorkout) {
      setWorkoutName(currentWorkout.name);
    }
  }, [currentWorkout]);

  const getCurrentDigest = useCallback(() => {
    const settings = storage.getSettings();
    return buildHistoryDigest(storage.getWorkouts(), settings.unit);
  }, []);

  const lastSet = useMemo(() => getLastSet(currentWorkout), [currentWorkout]);

  const previousSetLookup = useMemo(() => buildPreviousSetLookup(workouts), [workouts]);

  const sessionProgress = useMemo(() => getCompletionProgress(currentWorkout), [currentWorkout]);

  useEffect(() => {
    if (!currentWorkout || currentWorkout.exercises.length === 0) return;

    const digest = getCurrentDigest();
    liveCoach.queueSuggestion(
      {
        activeWorkout: currentWorkout,
        lastSet,
        fullHistoryDigestLite: buildHistoryDigestLite(digest),
      },
      350
    );
  }, [currentWorkout, lastSet, liveCoach, getCurrentDigest]);

  useEffect(() => {
    if (!currentWorkout || workouts.length === 0) return;
    void progressionPlan.generateProgressionPlan(getCurrentDigest());
  }, [currentWorkout, workouts.length, progressionPlan.generateProgressionPlan, getCurrentDigest]);

  useEffect(() => {
    if (!naturalLanguageLog.parseResult || !aiPreferences.autoApplySuggestions) return;

    if (naturalLanguageLog.parseResult.requiresReview) return;

    applyParsedLogPatch(naturalLanguageLog.parseResult);
    setToastMessage('AI log patch auto-applied.');
  }, [naturalLanguageLog.parseResult, aiPreferences.autoApplySuggestions, applyParsedLogPatch]);

  useEffect(() => {
    if (!toastMessage) return;

    const timeout = setTimeout(() => setToastMessage(''), 1800);
    return () => clearTimeout(timeout);
  }, [toastMessage]);

  const handleStartWorkout = () => {
    const name = workoutName.trim() || undefined;
    startWorkout(name);
    uiAnalytics.track({ stage: 'workout_start', action: 'quick_start_tap' });
  };

  const handleGeneratePlan = async () => {
    const result = await aiPlan.generatePlan({
      goal: goal.trim(),
      durationMinutes: Math.max(15, durationMinutes),
      equipment: equipmentCsv
        .split(',')
        .map(item => item.trim())
        .filter(Boolean),
      constraints: constraintsCsv
        .split(',')
        .map(item => item.trim())
        .filter(Boolean),
      fullHistoryDigest: getCurrentDigest(),
    });

    if (result) {
      setIsCoachCollapsed(false);
      uiAnalytics.track({ stage: 'workout_start', action: 'ai_plan_generated' });
    }
  };

  const handleStartFromAiPlan = () => {
    if (!aiPlan.data) return;

    startWorkoutWithPlan(workoutName.trim() || aiPlan.data.workoutName, aiPlan.data.exercises);
    uiAnalytics.track({ stage: 'workout_start', action: 'ai_plan_applied' });
  };

  const handleCompleteWorkout = async () => {
    const completed = completeWorkout();
    if (!completed) return;

    const digest = buildHistoryDigest(storage.getWorkouts(), storage.getSettings().unit);

    const summary = await postWorkoutAi.generateSummary({
      completedWorkout: completed,
      fullHistoryDigest: digest,
    });

    if (summary) {
      storage.updateWorkout({ ...completed, aiSummary: summary });
      setShowCompletionCard(true);
      uiAnalytics.track({ stage: 'workout_complete', action: 'summary_generated' });
      return;
    }

    router.push('/history');
  };

  const handleCancelWorkout = () => {
    if (confirm('Are you sure you want to cancel this workout? All progress will be lost.')) {
      cancelWorkout();
      uiAnalytics.track({ stage: 'workout_active', action: 'workout_cancelled' });
    }
  };

  const applySuggestionToCurrentSet = (suggestion: AiLiveCoachResponse) => {
    if (!currentWorkout) return;

    const exercise = currentWorkout.exercises[currentWorkout.exercises.length - 1];
    if (!exercise) return;

    const targetSet = exercise.sets.find(set => !set.completed) || exercise.sets[exercise.sets.length - 1];
    if (!targetSet) return;

    updateSet(exercise.id, targetSet.id, {
      weight: suggestion.nextSet.weight,
      reps: suggestion.nextSet.reps,
      unit: suggestion.nextSet.unit,
    });

    uiAnalytics.trackSetAction('set_apply_live_coach', {
      confidence: suggestion.confidence,
      actionability: suggestion.actionability || 'review',
    });
    setToastMessage('Live coach suggestion applied.');
  };

  const handleRequestLiveSuggestion = async () => {
    if (!currentWorkout) return;

    const result = await liveCoach.requestSuggestion({
      activeWorkout: currentWorkout,
      lastSet,
      fullHistoryDigestLite: buildHistoryDigestLite(getCurrentDigest()),
    });

    if (result) {
      setIsCoachCollapsed(false);
      uiAnalytics.track({ stage: 'workout_active', action: 'live_suggestion_requested' });
    }
  };

  const handleParseQuickLog = async () => {
    if (!currentWorkout) return;

    const result = await naturalLanguageLog.parseTextLog({
      text: quickLogText,
      sessionContext: currentWorkout,
    });

    if (result) {
      uiAnalytics.track({
        stage: 'workout_active',
        action: 'quick_log_parsed',
        metadata: { confidence: result.confidence, requiresReview: result.requiresReview ?? true },
      });
    }
  };

  const handleApplyParsedLog = () => {
    if (!naturalLanguageLog.parseResult) return;

    applyParsedLogPatch(naturalLanguageLog.parseResult);
    setToastMessage('Parsed workout patch applied.');
  };

  const handleSaveTemplate = () => {
    if (!postWorkoutAi.data) return;

    const sourceWorkout = storage
      .getWorkouts()
      .filter(workout => workout.completed)
      .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime())[0];

    if (!sourceWorkout) return;

    const template: WorkoutTemplate = {
      id: uuidv4(),
      name: `${sourceWorkout.name} Template`,
      exercises: sourceWorkout.exercises.map(exercise => ({
        exercise: exercise.exercise,
        targetSets: exercise.sets.length,
        targetReps:
          exercise.sets.length > 0
            ? Math.round(
                exercise.sets.reduce((sum, set) => sum + set.reps, 0) / exercise.sets.length
              )
            : 8,
      })),
    };

    storage.addTemplate(template);
    setToastMessage('Saved as template.');
  };

  const handleShareSummary = async () => {
    if (!postWorkoutAi.data) return;

    const text = `${postWorkoutAi.data.summary}\n\nFocus: ${postWorkoutAi.data.nextSessionRecommendation.focus}`;

    if (navigator.share) {
      try {
        await navigator.share({
          title: 'Beast Mode Summary',
          text,
        });
        return;
      } catch {
        // Ignore cancelled share.
      }
    }

    await navigator.clipboard.writeText(text);
    setToastMessage('Summary copied to clipboard.');
  };

  const handleScheduleNext = () => {
    const next = new Date();
    next.setDate(next.getDate() + 1);
    setToastMessage(`Next session target: ${next.toLocaleDateString()}`);
  };

  const handleSetCompleted = (set: WorkoutSet) => {
    const restSeconds =
      liveCoach.data?.nextSet.restSeconds || uxPreferences.restTimerDefaultSeconds || 90;
    if (uxPreferences.autoStartRestTimer) {
      setRestTimerKickSeconds(restSeconds);
      setToastMessage(`Rest timer started (${restSeconds}s).`);
    }

    if (uxPreferences.enableHaptics && typeof window !== 'undefined' && 'vibrate' in navigator) {
      navigator.vibrate(30);
    }

    uiAnalytics.track({
      stage: 'workout_active',
      action: 'set_completed',
      metadata: {
        reps: set.reps,
        weight: set.weight,
      },
    });
  };

  const handleApplyProgressionTargets = () => {
    if (!currentWorkout || !progressionPlan.data) return;

    progressionPlan.data.updates.forEach(update => {
      const exercise = currentWorkout.exercises.find(
        current => current.exercise.id === update.exerciseId
      );
      if (!exercise) return;

      const targetSet = exercise.sets.find(set => !set.completed) || exercise.sets[0];
      if (!targetSet) return;

      updateSet(exercise.id, targetSet.id, {
        weight: update.nextTarget.weight,
        reps: update.nextTarget.reps,
        unit: update.nextTarget.unit,
      });
    });

    setToastMessage('Progression targets applied to current workout.');
  };

  const startRecording = async () => {
    if (!navigator.mediaDevices?.getUserMedia) {
      window.alert('Audio recording is not supported in this browser.');
      return;
    }

    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const recorder = new MediaRecorder(stream);
      recordingChunksRef.current = [];

      recorder.ondataavailable = event => {
        if (event.data.size > 0) {
          recordingChunksRef.current.push(event.data);
        }
      };

      recorder.onstop = async () => {
        const blob = new Blob(recordingChunksRef.current, {
          type: recorder.mimeType || 'audio/webm',
        });

        const transcript = await naturalLanguageLog.transcribeAudio(blob, navigator.language);
        if (transcript?.text) {
          setQuickLogText(transcript.text);
          if (currentWorkout) {
            await naturalLanguageLog.parseTextLog({
              text: transcript.text,
              sessionContext: currentWorkout,
            });
          }
        }

        stream.getTracks().forEach(track => {
          track.stop();
        });
      };

      recorder.start();
      recorderRef.current = recorder;
      setIsRecording(true);
      uiAnalytics.track({ stage: 'workout_active', action: 'voice_record_started' });
    } catch {
      window.alert('Unable to access microphone.');
    }
  };

  const stopRecording = () => {
    recorderRef.current?.stop();
    setIsRecording(false);
    uiAnalytics.track({ stage: 'workout_active', action: 'voice_record_stopped' });
  };

  if (isLoading) {
    return (
      <div className="py-6 text-center">
        <p className="text-muted">Loading...</p>
      </div>
    );
  }

  if (showCompletionCard && postWorkoutAi.data) {
    return (
      <div className="py-6">
        <Card className="mb-4" elevated>
          <h2 className="mb-2" style={{ fontSize: '1.45rem', fontWeight: 760 }}>
            Session Complete
          </h2>
          <p className="mb-3">{postWorkoutAi.data.summary}</p>

          <h3 className="mb-2" style={{ fontWeight: 680 }}>Key Wins</h3>
          <ul className="mb-3" style={{ paddingLeft: '1.25rem' }}>
            {postWorkoutAi.data.keyWins.map(win => (
              <li key={win}>{win}</li>
            ))}
          </ul>

          <h3 className="mb-2" style={{ fontWeight: 680 }}>Next Session Focus</h3>
          <p className="mb-3">{postWorkoutAi.data.nextSessionRecommendation.focus}</p>

          <div className="workflow-chip-row mb-3">
            <span className="workflow-chip">PR Tracking Active</span>
            <span className="workflow-chip">Volume Badge</span>
            <span className="workflow-chip">Consistency Badge</span>
          </div>

          <div className="workflow-chip-row mb-3">
            <Button variant="secondary" size="sm" onClick={handleSaveTemplate}>
              <Save size={15} />
              Save as Template
            </Button>
            <Button variant="secondary" size="sm" onClick={() => { void handleShareSummary(); }}>
              <Share2 size={15} />
              Share
            </Button>
            <Button variant="secondary" size="sm" onClick={handleScheduleNext}>
              <CalendarPlus size={15} />
              Schedule Next
            </Button>
          </div>

          <div className="flex gap-2">
            <Button variant="primary" onClick={() => router.push('/history')}>
              View History
            </Button>
            <Button variant="ghost" onClick={() => router.push('/')}>
              Back Home
            </Button>
          </div>
        </Card>
      </div>
    );
  }

  if (!currentWorkout) {
    return (
      <div className="py-6">
        <header className="page-header">
          <h1 className="page-title">New Workout</h1>
          <p className="text-muted" style={{ marginTop: '0.25rem', fontSize: '0.85rem' }}>
            Fastest route to your first completed set.
          </p>
        </header>

        <Card className="mb-4" elevated>
          <Input
            id={workoutNameInputId}
            label="Workout Name (optional)"
            type="text"
            className="mb-3"
            placeholder={`Workout ${new Date().toLocaleDateString()}`}
            value={workoutName}
            onChange={event => setWorkoutName(event.target.value)}
          />

          <Button variant="primary" size="lg" block className="mb-2" onClick={handleStartWorkout}>
            <Zap size={18} />
            Start Empty Workout
          </Button>

          <div className="workflow-chip-row">
            {storage.getTemplates().slice(0, 3).map(template => (
              <span key={template.id} className="workflow-chip">
                {template.name}
              </span>
            ))}
          </div>
        </Card>

        <Card className="mb-4" elevated>
          <h2 className="mb-2" style={{ fontWeight: 700 }}>
            <Sparkles size={18} style={{ display: 'inline', marginRight: '0.5rem' }} />
            AI Builder
          </h2>

          <Input
            id={goalInputId}
            label="Goal"
            type="text"
            className="mb-3"
            value={goal}
            onChange={event => setGoal(event.target.value)}
          />

          <Input
            id={durationInputId}
            label="Duration (minutes)"
            type="number"
            className="mb-3"
            min={15}
            max={180}
            value={durationMinutes}
            onChange={event => setDurationMinutes(Number(event.target.value) || 45)}
          />

          <Input
            id={equipmentInputId}
            label="Equipment (comma separated)"
            type="text"
            className="mb-3"
            value={equipmentCsv}
            onChange={event => setEquipmentCsv(event.target.value)}
          />

          <Input
            id={constraintsInputId}
            label="Constraints (comma separated)"
            type="text"
            className="mb-3"
            placeholder="shoulder-friendly, low impact"
            value={constraintsCsv}
            onChange={event => setConstraintsCsv(event.target.value)}
          />

          <Button variant="secondary" onClick={handleGeneratePlan} disabled={aiPlan.isLoading}>
            <Wand2 size={16} />
            {aiPlan.isLoading ? 'Generating...' : 'Generate AI Plan'}
          </Button>

          {aiPlan.error && (
            <p className="text-danger mt-3" style={{ fontSize: '0.85rem' }}>
              {aiPlan.error}
            </p>
          )}

          {aiPlan.data && (
            <div className="mt-3">
              <h3 className="mb-2" style={{ fontWeight: 680 }}>{aiPlan.data.workoutName}</h3>
              <p className="text-muted" style={{ fontSize: '0.82rem' }}>
                {aiPlan.data.estimatedSessionMinutes || durationMinutes} min estimated, {aiPlan.data.exercises.length} exercises
              </p>
              <Button variant="primary" className="mt-2" onClick={handleStartFromAiPlan}>
                Start From AI Plan
              </Button>
            </div>
          )}
        </Card>
      </div>
    );
  }

  const elapsedMinutes = getElapsedMinutes(currentWorkout.date);
  const totalSets = currentWorkout.exercises.reduce((sum, exercise) => sum + exercise.sets.length, 0);
  const completedSets = currentWorkout.exercises.reduce(
    (sum, exercise) => sum + exercise.sets.filter(set => set.completed).length,
    0
  );

  return (
    <div className={`py-6 ${uxPreferences.compactMode ? 'compact-mode' : ''}`.trim()}>
      <div className="workout-topbar">
        <div className="flex justify-between items-center">
          <div>
            <h1 style={{ fontSize: '1.2rem', fontWeight: 740 }}>{currentWorkout.name}</h1>
            <div className="workout-topbar-metrics mt-1">
              <span className="metric-pill">Elapsed {formatElapsed(elapsedMinutes)}</span>
              <span className="metric-pill">{completedSets}/{totalSets} sets</span>
              <span className="metric-pill">{sessionProgress}% complete</span>
            </div>
          </div>

          <div className="flex items-center gap-2">
            <ProgressRing value={sessionProgress} size={56} label={`${sessionProgress}%`} />
            <Button variant="ghost" size="sm" onClick={handleCancelWorkout} aria-label="Cancel workout">
              <X size={18} />
            </Button>
          </div>
        </div>
      </div>

      <Timer autoStartSeconds={restTimerKickSeconds} />

      <Card className="mt-4 mb-4" elevated>
        <div className="flex justify-between items-center mb-2">
          <h3 style={{ fontWeight: 700 }}>Live Coach</h3>
          <div className="flex gap-2">
            <Button
              variant="ghost"
              size="sm"
              onClick={() => setIsCoachCollapsed(prev => !prev)}
              aria-label="Toggle live coach"
            >
              {isCoachCollapsed ? <ChevronDown size={16} /> : <ChevronUp size={16} />}
            </Button>
            <Button
              variant="secondary"
              size="sm"
              onClick={handleRequestLiveSuggestion}
              disabled={liveCoach.isLoading}
            >
              {liveCoach.isLoading ? 'Thinking...' : 'Refresh'}
            </Button>
          </div>
        </div>

        {!isCoachCollapsed && (
          <>
            {liveCoach.error && <p className="text-danger">{liveCoach.error}</p>}

            {liveCoach.data ? (
              <>
                <p className="mb-2" style={{ fontWeight: 650 }}>
                  Next Set: {liveCoach.data.nextSet.weight} {liveCoach.data.nextSet.unit} x {liveCoach.data.nextSet.reps}
                </p>
                <p className="text-muted" style={{ fontSize: '0.82rem' }}>
                  Rest {liveCoach.data.nextSet.restSeconds}s, confidence {Math.round(liveCoach.data.confidence * 100)}%
                </p>
                {liveCoach.data.rationale.length > 0 && (
                  <ul style={{ paddingLeft: '1.25rem', marginTop: '0.5rem' }}>
                    {liveCoach.data.rationale.map(item => (
                      <li key={item}>{item}</li>
                    ))}
                  </ul>
                )}
                <div className="mt-2">
                  <Button
                    variant="primary"
                    size="sm"
                    onClick={() => {
                      if (liveCoach.data) {
                        applySuggestionToCurrentSet(liveCoach.data);
                      }
                    }}
                    disabled={(liveCoach.data.actionability || 'review') !== 'apply'}
                  >
                    Apply Suggestion
                  </Button>
                </div>
              </>
            ) : (
              <p className="text-muted" style={{ fontSize: '0.84rem' }}>
                Complete a set to unlock personalized suggestions.
              </p>
            )}
          </>
        )}
      </Card>

      <Card className="mb-4" elevated>
        <div className="flex justify-between items-center mb-2">
          <h3 style={{ fontWeight: 700 }}>Progression Autopilot</h3>
          <Button
            variant="secondary"
            size="sm"
            onClick={() => {
              void progressionPlan.generateProgressionPlan(getCurrentDigest());
            }}
            disabled={progressionPlan.isLoading}
          >
            {progressionPlan.isLoading ? 'Updating...' : 'Refresh'}
          </Button>
        </div>
        {progressionPlan.error && (
          <p className="text-danger" style={{ fontSize: '0.82rem' }}>
            {progressionPlan.error}
          </p>
        )}
        {progressionPlan.data ? (
          <>
            <p className="text-muted" style={{ fontSize: '0.82rem' }}>
              {progressionPlan.data.blockName} • {progressionPlan.data.updates.length} target updates
            </p>
            <Button
              variant="primary"
              size="sm"
              className="mt-2"
              onClick={handleApplyProgressionTargets}
            >
              Apply Progression Targets
            </Button>
          </>
        ) : (
          <p className="text-muted" style={{ fontSize: '0.82rem' }}>
            Generate targets from your full history to auto-adjust loads and reps.
          </p>
        )}
      </Card>

      <Card className="mb-4" elevated>
        <h3 className="mb-2" style={{ fontWeight: 700 }}>Quick Log (Text or Voice)</h3>
        <textarea
          className="input mb-2"
          value={quickLogText}
          onChange={event => setQuickLogText(event.target.value)}
          placeholder="Bench 3x5 185, row 3x10 95, RPE 8"
          rows={3}
          style={{ resize: 'vertical' }}
        />

        <div className="flex gap-2 mb-2">
          <Button
            variant="secondary"
            size="sm"
            onClick={handleParseQuickLog}
            disabled={naturalLanguageLog.isParsing}
          >
            {naturalLanguageLog.isParsing ? 'Parsing...' : 'Parse Log'}
          </Button>

          <Button
            variant={isRecording ? 'danger' : 'ghost'}
            size="sm"
            onClick={isRecording ? stopRecording : startRecording}
            disabled={naturalLanguageLog.isTranscribing}
          >
            {isRecording ? <MicOff size={16} /> : <Mic size={16} />}
            {isRecording ? 'Stop Recording' : 'Record Note'}
          </Button>
        </div>

        {naturalLanguageLog.error && (
          <p className="text-danger" style={{ fontSize: '0.84rem' }}>
            {naturalLanguageLog.error}
          </p>
        )}

        {naturalLanguageLog.parseResult && (
          <div className="mt-2">
            <p className="text-muted" style={{ fontSize: '0.82rem' }}>
              Confidence {Math.round(naturalLanguageLog.parseResult.confidence * 100)}% | parsed {naturalLanguageLog.parseResult.exercises.length} exercises
            </p>
            <p className="text-muted" style={{ fontSize: '0.78rem', marginTop: '0.2rem' }}>
              {naturalLanguageLog.parseResult.requiresReview ? 'Review required before apply.' : 'Safe to apply immediately.'}
            </p>
            <Button
              variant="primary"
              size="sm"
              className="mt-2"
              onClick={handleApplyParsedLog}
              disabled={naturalLanguageLog.parseResult.exercises.length === 0}
            >
              Apply Parsed Patch
            </Button>
          </div>
        )}
      </Card>

      <div className="mt-4">
        {currentWorkout.exercises.map(exercise => (
          <WorkoutExerciseCard
            key={exercise.id}
            workoutExercise={exercise}
            previousSets={
              uxPreferences.showPreviousValues
                ? previousSetLookup.get(exercise.exercise.id) || []
                : []
            }
            onAddSet={() => addSetToExercise(exercise.id)}
            onUpdateSet={(setId, updates) => updateSet(exercise.id, setId, updates)}
            onRemoveSet={setId => removeSet(exercise.id, setId)}
            onDuplicateSet={setId => duplicateSet(exercise.id, setId)}
            onSetCompleted={handleSetCompleted}
            onRemoveExercise={() => removeExerciseFromWorkout(exercise.id)}
          />
        ))}
      </div>

      <Button
        variant="secondary"
        block
        className="mb-3"
        onClick={() => setShowExerciseSelector(true)}
      >
        <Plus size={20} />
        Add Exercise
      </Button>

      {currentWorkout.exercises.length > 0 && (
        <Button
          variant="primary"
          size="lg"
          block
          onClick={() => {
            void handleCompleteWorkout();
          }}
          disabled={postWorkoutAi.isLoading}
        >
          <Check size={20} />
          {postWorkoutAi.isLoading ? 'Finishing Workout...' : 'Complete Workout'}
        </Button>
      )}

      <ExerciseSelector
        isOpen={showExerciseSelector}
        onClose={() => setShowExerciseSelector(false)}
        onSelect={addExerciseToWorkout}
      />

      <Toast message={toastMessage} tone="success" visible={toastMessage.length > 0} />
    </div>
  );
}
