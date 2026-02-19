'use client';

import { useCallback, useState } from 'react';
import type { AiRiskAnalysisRequest, AiRiskAnalysisResponse } from '@/types';

type HookState = {
  data: AiRiskAnalysisResponse | null;
  isLoading: boolean;
  error: string | null;
};

export const useRiskAnalysis = () => {
  const [state, setState] = useState<HookState>({
    data: null,
    isLoading: false,
    error: null,
  });

  const analyzeRisk = useCallback(async (request: AiRiskAnalysisRequest) => {
    setState(prev => ({ ...prev, isLoading: true, error: null }));

    try {
      const response = await fetch('/api/ai/risk-analysis', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(request),
      });

      const payload = (await response.json()) as AiRiskAnalysisResponse | { error?: string };
      if (!response.ok) {
        throw new Error(
          'error' in payload && typeof payload.error === 'string'
            ? payload.error
            : 'Failed to analyze training risk.'
        );
      }

      const result = payload as AiRiskAnalysisResponse;
      setState({ data: result, isLoading: false, error: null });
      return result;
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to analyze training risk.';
      setState(prev => ({ ...prev, isLoading: false, error: message }));
      return null;
    }
  }, []);

  return {
    ...state,
    analyzeRisk,
  };
};
