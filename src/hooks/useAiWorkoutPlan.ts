'use client';

import { useCallback, useState } from 'react';
import type { AiWorkoutPlanRequest, AiWorkoutPlanResponse } from '@/types';

type HookState = {
  data: AiWorkoutPlanResponse | null;
  isLoading: boolean;
  error: string | null;
};

export const useAiWorkoutPlan = () => {
  const [state, setState] = useState<HookState>({
    data: null,
    isLoading: false,
    error: null,
  });

  const generatePlan = useCallback(async (request: AiWorkoutPlanRequest) => {
    setState(prev => ({ ...prev, isLoading: true, error: null }));

    try {
      const response = await fetch('/api/ai/workout-plan', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(request),
      });

      const payload = (await response.json()) as AiWorkoutPlanResponse | { error?: string };
      if (!response.ok) {
        throw new Error(
          'error' in payload && typeof payload.error === 'string'
            ? payload.error
            : 'Failed to generate workout plan.'
        );
      }

      setState({ data: payload as AiWorkoutPlanResponse, isLoading: false, error: null });
      return payload as AiWorkoutPlanResponse;
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to generate workout plan.';
      setState(prev => ({ ...prev, isLoading: false, error: message }));
      return null;
    }
  }, []);

  return {
    ...state,
    generatePlan,
  };
};
