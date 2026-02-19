'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import type { AiLiveCoachRequest, AiLiveCoachResponse } from '@/types';

type HookState = {
  data: AiLiveCoachResponse | null;
  isLoading: boolean;
  error: string | null;
};

export const useLiveCoach = () => {
  const [state, setState] = useState<HookState>({
    data: null,
    isLoading: false,
    error: null,
  });
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const requestSuggestion = useCallback(async (request: AiLiveCoachRequest) => {
    setState(prev => ({ ...prev, isLoading: true, error: null }));

    try {
      const response = await fetch('/api/ai/live-coach', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(request),
      });

      const payload = (await response.json()) as AiLiveCoachResponse | { error?: string };
      if (!response.ok) {
        throw new Error(
          'error' in payload && typeof payload.error === 'string'
            ? payload.error
            : 'Failed to fetch live suggestion.'
        );
      }

      const result = payload as AiLiveCoachResponse;
      setState({ data: result, isLoading: false, error: null });
      return result;
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to fetch live suggestion.';
      setState(prev => ({ ...prev, isLoading: false, error: message }));
      return null;
    }
  }, []);

  const queueSuggestion = useCallback(
    (request: AiLiveCoachRequest, delayMs = 350) => {
      if (debounceRef.current) {
        clearTimeout(debounceRef.current);
      }

      debounceRef.current = setTimeout(() => {
        void requestSuggestion(request);
      }, delayMs);
    },
    [requestSuggestion]
  );

  useEffect(() => {
    return () => {
      if (debounceRef.current) {
        clearTimeout(debounceRef.current);
      }
    };
  }, []);

  return {
    ...state,
    requestSuggestion,
    queueSuggestion,
  };
};
