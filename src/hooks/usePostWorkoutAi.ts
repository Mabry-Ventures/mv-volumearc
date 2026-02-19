'use client';

import { useCallback, useState } from 'react';
import type { AiPostWorkoutRequest, AiPostWorkoutResponse } from '@/types';

type HookState = {
  data: AiPostWorkoutResponse | null;
  isLoading: boolean;
  error: string | null;
};

export const usePostWorkoutAi = () => {
  const [state, setState] = useState<HookState>({
    data: null,
    isLoading: false,
    error: null,
  });

  const generateSummary = useCallback(async (request: AiPostWorkoutRequest) => {
    setState(prev => ({ ...prev, isLoading: true, error: null }));

    try {
      const response = await fetch('/api/ai/post-workout', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(request),
      });

      const payload = (await response.json()) as AiPostWorkoutResponse | { error?: string };
      if (!response.ok) {
        throw new Error(
          'error' in payload && typeof payload.error === 'string'
            ? payload.error
            : 'Failed to generate post-workout summary.'
        );
      }

      const result = payload as AiPostWorkoutResponse;
      setState({ data: result, isLoading: false, error: null });
      return result;
    } catch (error) {
      const message =
        error instanceof Error ? error.message : 'Failed to generate post-workout summary.';
      setState(prev => ({ ...prev, isLoading: false, error: message }));
      return null;
    }
  }, []);

  return {
    ...state,
    generateSummary,
  };
};
