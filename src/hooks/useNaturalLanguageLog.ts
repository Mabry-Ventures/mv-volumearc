'use client';

import { useCallback, useState } from 'react';
import type {
  AiParseLogRequest,
  AiParseLogResponse,
  AiTranscriptionResponse,
} from '@/types';

type HookState = {
  parseResult: AiParseLogResponse | null;
  transcript: AiTranscriptionResponse | null;
  isParsing: boolean;
  isTranscribing: boolean;
  error: string | null;
};

export const useNaturalLanguageLog = () => {
  const [state, setState] = useState<HookState>({
    parseResult: null,
    transcript: null,
    isParsing: false,
    isTranscribing: false,
    error: null,
  });

  const parseTextLog = useCallback(async (request: AiParseLogRequest) => {
    setState(prev => ({ ...prev, isParsing: true, error: null }));

    try {
      const response = await fetch('/api/ai/parse-log', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(request),
      });

      const payload = (await response.json()) as AiParseLogResponse | { error?: string };
      if (!response.ok) {
        throw new Error(
          'error' in payload && typeof payload.error === 'string'
            ? payload.error
            : 'Failed to parse workout log.'
        );
      }

      const result = payload as AiParseLogResponse;
      setState(prev => ({ ...prev, parseResult: result, isParsing: false, error: null }));
      return result;
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to parse workout log.';
      setState(prev => ({ ...prev, isParsing: false, error: message }));
      return null;
    }
  }, []);

  const transcribeAudio = useCallback(async (audio: Blob, locale?: string) => {
    setState(prev => ({ ...prev, isTranscribing: true, error: null }));

    try {
      const formData = new FormData();
      formData.append('audio', new File([audio], 'workout-log.webm', { type: audio.type || 'audio/webm' }));
      if (locale) {
        formData.append('locale', locale);
      }

      const response = await fetch('/api/ai/transcribe', {
        method: 'POST',
        body: formData,
      });

      const payload = (await response.json()) as AiTranscriptionResponse | { error?: string };
      if (!response.ok) {
        throw new Error(
          'error' in payload && typeof payload.error === 'string'
            ? payload.error
            : 'Failed to transcribe audio.'
        );
      }

      const result = payload as AiTranscriptionResponse;
      setState(prev => ({ ...prev, transcript: result, isTranscribing: false, error: null }));
      return result;
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to transcribe audio.';
      setState(prev => ({ ...prev, isTranscribing: false, error: message }));
      return null;
    }
  }, []);

  return {
    ...state,
    parseTextLog,
    transcribeAudio,
  };
};
