'use client';

import { useCallback, useState } from 'react';
import type { AiHistoryDigest, ProgressionBlock } from '@/types';

type HookState = {
  data: ProgressionBlock | null;
  isLoading: boolean;
  error: string | null;
};

export const useProgressionPlan = () => {
  const [state, setState] = useState<HookState>({
    data: null,
    isLoading: false,
    error: null,
  });

  const generateProgressionPlan = useCallback(async (fullHistoryDigest: AiHistoryDigest) => {
    setState(prev => ({ ...prev, isLoading: true, error: null }));

    try {
      const response = await fetch('/api/ai/progression-plan', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ fullHistoryDigest }),
      });

      const payload = (await response.json()) as
        | { progression: ProgressionBlock; error?: never }
        | { error: string };

      if (!response.ok || 'error' in payload) {
        throw new Error('error' in payload ? payload.error : 'Failed to generate progression plan.');
      }

      setState({ data: payload.progression, isLoading: false, error: null });
      return payload.progression;
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to generate progression plan.';
      setState(prev => ({ ...prev, isLoading: false, error: message }));
      return null;
    }
  }, []);

  return {
    ...state,
    generateProgressionPlan,
  };
};
