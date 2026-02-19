'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { Plus, Check, X, Sparkles, Mic, MicOff, Wand2 } from 'lucide-react';
import { useWorkouts } from '@/hooks/useWorkouts';
import { useAiWorkoutPlan } from '@/hooks/useAiWorkoutPlan';
import { useLiveCoach } from '@/hooks/useLiveCoach';
import { usePostWorkoutAi } from '@/hooks/usePostWorkoutAi';
import { useNaturalLanguageLog } from '@/hooks/useNaturalLanguageLog';
import { Timer } from '@/components/Timer';
import { ExerciseSelector } from '@/components/ExerciseSelector';
import { WorkoutExerciseCard } from '@/components/WorkoutExerciseCard';
import { storage } from '@/utils/storage';
import { buildHistoryDigest, buildHistoryDigestLite } from '@/lib/ai/contextBuilder';
import type { WorkoutSet, Workout } from '@/types';

const getLastSet = (workout: Workout | null): WorkoutSet | null => {
  if (!workout) return null;

  const sets = workout.exercises.flatMap(exercise => exercise.sets);
  if (sets.length === 0) return null;
  return sets[sets.length - 1];
};

export default function WorkoutPage() {
  const router = useRouter();
  const {
    currentWorkout,
    isLoading,
    startWorkout,
    startWorkoutWithPlan,
    addExerciseToWorkout,
    removeExerciseFromWorkout,
    addSetToExercise,
    updateSet,
    removeSet,
    completeWorkout,
    cancelWorkout,
    applyParsedLogPatch,
  } = useWorkouts();

  const aiPlan = useAiWorkoutPlan();
  const liveCoach = useLiveCoach();
  const postWorkoutAi = usePostWorkoutAi();
  const naturalLanguageLog = useNaturalLanguageLog();

  const [showExerciseSelector, setShowExerciseSelector] = useState(false);
  const [workoutName, setWorkoutName] = useState('');
  const [goal, setGoal] = useState('Build strength');
  const [durationMinutes, setDurationMinutes] = useState(45);
  const [equipmentCsv, setEquipmentCsv] = useState('barbell, dumbbell, machine');
  const [constraintsCsv, setConstraintsCsv] = useState('');
  const [quickLogText, setQuickLogText] = useState('');
  const [showCompletionCard, setShowCompletionCard] = useState(false);
  const [isRecording, setIsRecording] = useState(false);
  const workoutNameInputId = 'workout-name';
  const goalInputId = 'ai-goal';
  const durationInputId = 'ai-duration-minutes';
  const equipmentInputId = 'ai-equipment';
  const constraintsInputId = 'ai-constraints';

  const recorderRef = useRef<MediaRecorder | null>(null);
  const recordingChunksRef = useRef<Blob[]>([]);

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

  useEffect(() => {
    if (!currentWorkout || currentWorkout.exercises.length === 0) return;

    const currentDigest = getCurrentDigest();
    liveCoach.queueSuggestion(
      {
        activeWorkout: currentWorkout,
        lastSet,
        fullHistoryDigestLite: buildHistoryDigestLite(currentDigest),
      },
      400
    );
  }, [currentWorkout, lastSet, liveCoach, getCurrentDigest]);

  const handleStartWorkout = () => {
    const name = workoutName.trim() || undefined;
    startWorkout(name);
  };

  const handleGeneratePlan = async () => {
    await aiPlan.generatePlan({
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
  };

  const handleStartFromAiPlan = () => {
    if (!aiPlan.data) return;

    startWorkoutWithPlan(
      workoutName.trim() || aiPlan.data.workoutName,
      aiPlan.data.exercises
    );
  };

  const handleCompleteWorkout = async () => {
    const completed = completeWorkout();
    if (!completed) return;

    const digest = buildHistoryDigest(
      storage.getWorkouts(),
      storage.getSettings().unit
    );

    const summary = await postWorkoutAi.generateSummary({
      completedWorkout: completed,
      fullHistoryDigest: digest,
    });

    if (summary) {
      storage.updateWorkout({ ...completed, aiSummary: summary });
      setShowCompletionCard(true);
      return;
    }

    router.push('/history');
  };

  const handleCancelWorkout = () => {
    if (confirm('Are you sure you want to cancel this workout? All progress will be lost.')) {
      cancelWorkout();
    }
  };

  const handleRequestLiveSuggestion = async () => {
    if (!currentWorkout) return;

    await liveCoach.requestSuggestion({
        activeWorkout: currentWorkout,
        lastSet,
        fullHistoryDigestLite: buildHistoryDigestLite(getCurrentDigest()),
      });
  };

  const handleParseQuickLog = async () => {
    if (!currentWorkout) return;

    await naturalLanguageLog.parseTextLog({
      text: quickLogText,
      sessionContext: currentWorkout,
    });
  };

  const handleApplyParsedLog = () => {
    if (!naturalLanguageLog.parseResult) return;
    applyParsedLogPatch(naturalLanguageLog.parseResult);
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
    } catch {
      window.alert('Unable to access microphone.');
    }
  };

  const stopRecording = () => {
    recorderRef.current?.stop();
    setIsRecording(false);
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
        <div className="card mb-4">
          <h2 className="mb-2" style={{ fontSize: '1.5rem', fontWeight: 700 }}>
            AI Post-Workout Summary
          </h2>
          <p className="mb-3">{postWorkoutAi.data.summary}</p>

          <h3 className="mb-2" style={{ fontWeight: 600 }}>Key Wins</h3>
          <ul className="mb-3" style={{ paddingLeft: '1.25rem' }}>
            {postWorkoutAi.data.keyWins.map(win => (
              <li key={win}>{win}</li>
            ))}
          </ul>

          <h3 className="mb-2" style={{ fontWeight: 600 }}>Next Session Focus</h3>
          <p className="mb-3">{postWorkoutAi.data.nextSessionRecommendation.focus}</p>

          <div className="flex gap-2">
            <button
              type="button"
              className="btn btn-primary"
              onClick={() => router.push('/history')}
            >
              View History
            </button>
            <button
              type="button"
              className="btn btn-secondary"
              onClick={() => {
                setShowCompletionCard(false);
                router.push('/');
              }}
            >
              Back Home
            </button>
          </div>
        </div>
      </div>
    );
  }

  // No active workout - show start screen
  if (!currentWorkout) {
    return (
      <div className="py-6">
        <header className="page-header">
          <h1 className="page-title">New Workout</h1>
        </header>

        <div className="card mb-6">
          <label className="label" htmlFor={workoutNameInputId}>
            Workout Name (optional)
          </label>
          <input
            id={workoutNameInputId}
            type="text"
            className="input"
            placeholder={`Workout ${new Date().toLocaleDateString()}`}
            value={workoutName}
            onChange={event => setWorkoutName(event.target.value)}
          />
        </div>

        <button
          type="button"
          className="btn btn-primary btn-lg btn-block mb-4"
          onClick={handleStartWorkout}
        >
          Start Empty Workout
        </button>

        <div className="card mb-4">
          <h2 className="mb-2" style={{ fontWeight: 700 }}>
            <Sparkles size={18} style={{ display: 'inline', marginRight: '0.5rem' }} />
            AI Workout Builder
          </h2>

          <label className="label" htmlFor={goalInputId}>Goal</label>
          <input
            id={goalInputId}
            type="text"
            className="input mb-3"
            value={goal}
            onChange={event => setGoal(event.target.value)}
          />

          <label className="label" htmlFor={durationInputId}>Duration (minutes)</label>
          <input
            id={durationInputId}
            type="number"
            className="input mb-3"
            min={15}
            max={180}
            value={durationMinutes}
            onChange={event => setDurationMinutes(Number(event.target.value) || 45)}
          />

          <label className="label" htmlFor={equipmentInputId}>Equipment (comma separated)</label>
          <input
            id={equipmentInputId}
            type="text"
            className="input mb-3"
            value={equipmentCsv}
            onChange={event => setEquipmentCsv(event.target.value)}
          />

          <label className="label" htmlFor={constraintsInputId}>Constraints (comma separated)</label>
          <input
            id={constraintsInputId}
            type="text"
            className="input mb-3"
            placeholder="shoulder-friendly, no jumping"
            value={constraintsCsv}
            onChange={event => setConstraintsCsv(event.target.value)}
          />

          <button
            type="button"
            className="btn btn-secondary"
            onClick={handleGeneratePlan}
            disabled={aiPlan.isLoading}
          >
            <Wand2 size={16} />
            {aiPlan.isLoading ? 'Generating...' : 'Generate AI Plan'}
          </button>

          {aiPlan.error && (
            <p className="text-danger mt-3" style={{ fontSize: '0.875rem' }}>
              {aiPlan.error}
            </p>
          )}

          {aiPlan.data && (
            <div className="mt-4">
              <h3 className="mb-2" style={{ fontWeight: 600 }}>{aiPlan.data.workoutName}</h3>
              <div className="text-muted mb-3" style={{ fontSize: '0.875rem' }}>
                {aiPlan.data.exercises.length} exercises generated
              </div>
              <button
                type="button"
                className="btn btn-primary"
                onClick={handleStartFromAiPlan}
              >
                Start From AI Plan
              </button>
            </div>
          )}
        </div>

        <p className="text-muted text-center mt-4" style={{ fontSize: '0.875rem' }}>
          Add exercises as you go, or start from an AI-generated plan
        </p>
      </div>
    );
  }

  // Active workout
  return (
    <div className="py-6">
      <header className="flex justify-between items-center mb-6">
        <div>
          <h1 style={{ fontSize: '1.5rem', fontWeight: 700 }}>
            {currentWorkout.name}
          </h1>
          <p className="text-muted" style={{ fontSize: '0.875rem' }}>
            Started {new Date(currentWorkout.date).toLocaleTimeString([], {
              hour: '2-digit',
              minute: '2-digit',
            })}
          </p>
        </div>
        <button type="button" className="btn btn-ghost btn-sm" onClick={handleCancelWorkout}>
          <X size={20} />
        </button>
      </header>

      <Timer />

      <div className="card mt-4 mb-4">
        <div className="flex justify-between items-center mb-2">
          <h3 style={{ fontWeight: 600 }}>Live Coach</h3>
          <button
            type="button"
            className="btn btn-secondary btn-sm"
            onClick={handleRequestLiveSuggestion}
            disabled={liveCoach.isLoading}
          >
            {liveCoach.isLoading ? 'Thinking...' : 'Refresh Suggestion'}
          </button>
        </div>

        {liveCoach.error && <p className="text-danger">{liveCoach.error}</p>}

        {liveCoach.data ? (
          <div>
            <p className="mb-2">
              Next Set: {liveCoach.data.nextSet.weight} {liveCoach.data.nextSet.unit} x{' '}
              {liveCoach.data.nextSet.reps}, rest {liveCoach.data.nextSet.restSeconds}s
            </p>
            <p className="text-muted" style={{ fontSize: '0.875rem' }}>
              Confidence: {Math.round(liveCoach.data.confidence * 100)}%
            </p>
            {liveCoach.data.rationale.length > 0 && (
              <ul style={{ paddingLeft: '1.25rem', marginTop: '0.5rem' }}>
                {liveCoach.data.rationale.map(item => (
                  <li key={item}>{item}</li>
                ))}
              </ul>
            )}
          </div>
        ) : (
          <p className="text-muted" style={{ fontSize: '0.875rem' }}>
            Complete a few sets to improve suggestion quality.
          </p>
        )}
      </div>

      <div className="card mb-4">
        <h3 className="mb-2" style={{ fontWeight: 600 }}>Quick Log (Text or Voice)</h3>
        <textarea
          className="input mb-2"
          value={quickLogText}
          onChange={event => setQuickLogText(event.target.value)}
          placeholder="Example: Bench press 3x5 at 185, last set RPE 9"
          rows={3}
          style={{ resize: 'vertical' }}
        />

        <div className="flex gap-2 mb-2">
          <button
            type="button"
            className="btn btn-secondary btn-sm"
            onClick={handleParseQuickLog}
            disabled={naturalLanguageLog.isParsing}
          >
            {naturalLanguageLog.isParsing ? 'Parsing...' : 'Parse Log'}
          </button>

          <button
            type="button"
            className={`btn btn-sm ${isRecording ? 'btn-danger' : 'btn-ghost'}`}
            onClick={isRecording ? stopRecording : startRecording}
            disabled={naturalLanguageLog.isTranscribing}
          >
            {isRecording ? <MicOff size={16} /> : <Mic size={16} />}
            {isRecording ? 'Stop Recording' : 'Record Note'}
          </button>
        </div>

        {naturalLanguageLog.error && (
          <p className="text-danger" style={{ fontSize: '0.875rem' }}>
            {naturalLanguageLog.error}
          </p>
        )}

        {naturalLanguageLog.parseResult && (
          <div className="mt-2">
            <p className="text-muted" style={{ fontSize: '0.875rem' }}>
              Parse confidence: {Math.round(naturalLanguageLog.parseResult.confidence * 100)}%
            </p>
            <p style={{ fontSize: '0.875rem', marginTop: '0.25rem' }}>
              Parsed exercises: {naturalLanguageLog.parseResult.exercises.length}
            </p>
            <button
              type="button"
              className="btn btn-primary btn-sm mt-2"
              onClick={handleApplyParsedLog}
              disabled={naturalLanguageLog.parseResult.exercises.length === 0}
            >
              Apply Parsed Patch
            </button>
          </div>
        )}
      </div>

      <div className="mt-6">
        {currentWorkout.exercises.map(exercise => (
          <WorkoutExerciseCard
            key={exercise.id}
            workoutExercise={exercise}
            onAddSet={() => addSetToExercise(exercise.id)}
            onUpdateSet={(setId, updates) => updateSet(exercise.id, setId, updates)}
            onRemoveSet={setId => removeSet(exercise.id, setId)}
            onRemoveExercise={() => removeExerciseFromWorkout(exercise.id)}
          />
        ))}
      </div>

      <button
        type="button"
        className="btn btn-secondary btn-block mb-4"
        onClick={() => setShowExerciseSelector(true)}
      >
        <Plus size={20} />
        Add Exercise
      </button>

      {currentWorkout.exercises.length > 0 && (
        <button
          type="button"
          className="btn btn-primary btn-lg btn-block"
          onClick={() => {
            void handleCompleteWorkout();
          }}
          disabled={postWorkoutAi.isLoading}
        >
          <Check size={20} />
          {postWorkoutAi.isLoading ? 'Finishing Workout...' : 'Complete Workout'}
        </button>
      )}

      <ExerciseSelector
        isOpen={showExerciseSelector}
        onClose={() => setShowExerciseSelector(false)}
        onSelect={addExerciseToWorkout}
      />
    </div>
  );
}
