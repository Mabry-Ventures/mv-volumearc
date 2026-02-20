import { NextResponse } from 'next/server';
import { aiFlags } from '@/lib/ai/flags';
import { enforceRateAndBudget, jsonError } from '@/lib/ai/http';
import { openaiClient } from '@/lib/ai/openaiClient';
import { getActorIdFromRequest } from '@/lib/server/actor';
import { telemetryStore } from '@/lib/server/telemetryStore';

export const runtime = 'nodejs';

const MAX_AUDIO_BYTES = 8 * 1024 * 1024;

export async function POST(request: Request) {
  const actorId = getActorIdFromRequest(request);
  const startedAt = Date.now();

  if (!aiFlags.transcribe) {
    return jsonError('Transcription AI feature is disabled.', 503);
  }

  let formData: FormData;
  try {
    formData = await request.formData();
  } catch {
    return jsonError('Invalid form payload.');
  }

  const file = formData.get('audio');
  const locale = formData.get('locale');

  if (!(file instanceof File)) {
    return jsonError('Missing audio file.');
  }

  if (file.size > MAX_AUDIO_BYTES) {
    return jsonError('Audio file too large. Maximum supported size is 8 MB.');
  }

  const guard = await enforceRateAndBudget(
    request,
    'transcribe',
    file.size
  );
  if (guard) return guard;

  const result = await openaiClient.transcribeAudio(
    file,
    typeof locale === 'string' ? locale : undefined
  );

  if (!result) {
    telemetryStore.recordAiFallback({
      actorId,
      endpoint: 'transcribe',
      reason: openaiClient.isConfigured() ? 'transcription_failed' : 'ai_unavailable',
    });
    telemetryStore.recordAiLatency({
      actorId,
      endpoint: 'transcribe',
      model: 'gpt-4o-mini-transcribe',
      latencyMs: Date.now() - startedAt,
    });
    return NextResponse.json({
      actorId,
      text: '',
      confidence: 0,
      fallbackReason: openaiClient.isConfigured() ? 'transcription_failed' : 'ai_unavailable',
    });
  }

  telemetryStore.recordAiLatency({
    actorId,
    endpoint: 'transcribe',
    model: 'gpt-4o-mini-transcribe',
    latencyMs: Date.now() - startedAt,
  });

  return NextResponse.json({
    actorId,
    text: result.text,
    confidence: result.text.length > 0 ? 0.8 : 0,
    durationSeconds: result.durationSeconds,
  });
}
