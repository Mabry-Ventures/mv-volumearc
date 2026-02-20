import { act, renderHook, waitFor } from '@testing-library/react';
import { useAiWorkoutPlan } from '@/hooks/useAiWorkoutPlan';
import { useLiveCoach } from '@/hooks/useLiveCoach';
import { useNaturalLanguageLog } from '@/hooks/useNaturalLanguageLog';
import { usePostWorkoutAi } from '@/hooks/usePostWorkoutAi';
import { useProgressionPlan } from '@/hooks/useProgressionPlan';
import { useRiskAnalysis } from '@/hooks/useRiskAnalysis';
import { sampleDigest, sampleWorkout } from '@/test/fixtures/ai';

const originalFetch = global.fetch;

const mockJsonResponse = (payload: unknown, status = 200) =>
  ({
    ok: status >= 200 && status < 300,
    status,
    json: async () => payload,
  }) as Response;

describe('AI hooks', () => {
  beforeEach(() => {
    global.fetch = jest.fn();
  });

  afterEach(() => {
    global.fetch = originalFetch;
    jest.clearAllMocks();
    jest.useRealTimers();
  });

  it('useAiWorkoutPlan returns plan data on success', async () => {
    const payload = {
      workoutName: 'AI Upper',
      warmup: [],
      exercises: [],
      cooldown: [],
      notes: [],
    };
    (global.fetch as jest.Mock).mockResolvedValue(mockJsonResponse(payload));

    const { result } = renderHook(() => useAiWorkoutPlan());
    const resolved = await act(async () =>
      result.current.generatePlan({
        goal: 'strength',
        durationMinutes: 45,
        equipment: ['barbell'],
        constraints: [],
        fullHistoryDigest: sampleDigest,
      })
    );

    expect(resolved?.workoutName).toBe('AI Upper');
    await waitFor(() => expect(result.current.data?.workoutName).toBe('AI Upper'));
  });

  it('useLiveCoach queues suggestion with debounce', async () => {
    jest.useFakeTimers();
    (global.fetch as jest.Mock).mockResolvedValue(
      mockJsonResponse({
        nextSet: { weight: 200, reps: 5, restSeconds: 120, unit: 'lbs' },
        confidence: 0.8,
        rationale: ['steady progression'],
      })
    );

    const { result } = renderHook(() => useLiveCoach());

    act(() => {
      result.current.queueSuggestion(
        {
          activeWorkout: sampleWorkout,
          lastSet: { id: 'set-1', reps: 5, weight: 195, unit: 'lbs', completed: true },
          fullHistoryDigestLite: {
            unit: sampleDigest.unit,
            rollingVolume: sampleDigest.rollingVolume,
            exerciseTrends: sampleDigest.exerciseTrends,
            fatigueSignals: sampleDigest.fatigueSignals,
          },
        },
        300
      );
    });

    act(() => {
      jest.advanceTimersByTime(350);
    });

    await waitFor(() => expect(global.fetch).toHaveBeenCalledTimes(1));
    await waitFor(() => expect(result.current.data?.nextSet.weight).toBe(200));
  });

  it('usePostWorkoutAi captures API errors', async () => {
    (global.fetch as jest.Mock).mockResolvedValue(
      mockJsonResponse({ error: 'post-workout unavailable' }, 503)
    );

    const { result } = renderHook(() => usePostWorkoutAi());
    const resolved = await act(async () =>
      result.current.generateSummary({
        completedWorkout: sampleWorkout,
        fullHistoryDigest: sampleDigest,
      })
    );

    expect(resolved).toBeNull();
    await waitFor(() => expect(result.current.error).toContain('post-workout unavailable'));
  });

  it('useRiskAnalysis returns risk data', async () => {
    (global.fetch as jest.Mock).mockResolvedValue(
      mockJsonResponse({
        plateauRisk: { score: 0.4, level: 'medium', reasons: ['fatigue'] },
        overtrainingRisk: { score: 0.2, level: 'low', reasons: [] },
        recommendedActions: ['deload'],
      })
    );

    const { result } = renderHook(() => useRiskAnalysis());
    const resolved = await act(async () =>
      result.current.analyzeRisk({
        fullHistoryDigest: sampleDigest,
        trendWindows: [7, 30],
      })
    );

    expect(resolved?.plateauRisk.level).toBe('medium');
    await waitFor(() => expect(result.current.data?.recommendedActions[0]).toBe('deload'));
  });

  it('useNaturalLanguageLog parses text and transcribes audio', async () => {
    (global.fetch as jest.Mock)
      .mockResolvedValueOnce(
        mockJsonResponse({
          confidence: 0.9,
          exercises: [{ exerciseName: 'Bench Press', sets: [{ reps: 5, weight: 185, unit: 'lbs' }] }],
          notes: [],
        })
      )
      .mockResolvedValueOnce(mockJsonResponse({ text: 'bench five by five', confidence: 0.8 }));

    const { result } = renderHook(() => useNaturalLanguageLog());

    const parsed = await act(async () =>
      result.current.parseTextLog({
        text: 'Bench 185x5',
        sessionContext: sampleWorkout,
      })
    );
    expect(parsed?.confidence).toBe(0.9);

    const transcribed = await act(async () =>
      result.current.transcribeAudio(new Blob(['audio'], { type: 'audio/webm' }), 'en')
    );
    expect(transcribed?.text).toContain('bench');
  });

  it('useProgressionPlan returns progression block', async () => {
    (global.fetch as jest.Mock).mockResolvedValue(
      mockJsonResponse({
        progression: {
          generatedAt: '2026-02-10T12:00:00.000Z',
          blockName: 'progressive-overload',
          durationWeeks: 4,
          updates: [],
          deloadRecommended: false,
          notes: ['stay consistent'],
        },
      })
    );

    const { result } = renderHook(() => useProgressionPlan());
    const resolved = await act(async () => result.current.generateProgressionPlan(sampleDigest));

    expect(resolved?.blockName).toBe('progressive-overload');
    await waitFor(() => expect(result.current.data?.durationWeeks).toBe(4));
  });
});
