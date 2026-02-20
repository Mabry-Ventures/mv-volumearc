import { NextResponse } from 'next/server';
import { featureFlags } from '@/lib/flags';
import { getActorIdFromRequest } from '@/lib/server/actor';
import { healthConnectors, type HealthProvider } from '@/lib/server/healthConnectors';
import { integrationStore } from '@/lib/server/integrationStore';

export const runtime = 'nodejs';

const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null;

const isProvider = (value: unknown): value is HealthProvider =>
  value === 'oura' || value === 'generic-json';

const readBearerFromHeader = (request: Request): string | null => {
  const header = request.headers.get('authorization');
  if (!header) return null;
  if (!header.toLowerCase().startsWith('bearer ')) return null;
  return header.slice(7).trim() || null;
};

export async function POST(request: Request) {
  if (!featureFlags.healthIntegrations) {
    return NextResponse.json({ error: 'Health integrations are currently disabled.' }, { status: 503 });
  }

  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return NextResponse.json({ error: 'Invalid health sync payload.' }, { status: 400 });
  }

  if (!isObject(payload) || !isProvider(payload.provider)) {
    return NextResponse.json({ error: 'A supported provider is required.' }, { status: 400 });
  }

  const accessToken = readBearerFromHeader(request) || String(payload.accessToken || '').trim();
  if (!accessToken) {
    return NextResponse.json({ error: 'Bearer token or accessToken is required.' }, { status: 401 });
  }

  try {
    const pulled = await healthConnectors.pullSignals({
      provider: payload.provider,
      accessToken,
      startDate: typeof payload.startDate === 'string' ? payload.startDate : undefined,
      endDate: typeof payload.endDate === 'string' ? payload.endDate : undefined,
      genericUrl: typeof payload.genericUrl === 'string' ? payload.genericUrl : undefined,
    });

    const actorId = getActorIdFromRequest(request);
    const state = integrationStore.importSignals(actorId, pulled);
    const summary = integrationStore.getSummary(actorId);

    return NextResponse.json({
      actorId,
      provider: payload.provider,
      imported: {
        recovery: pulled.recovery.length,
        sleep: pulled.sleep.length,
        heart: pulled.heart.length,
      },
      retainedSignals: {
        recovery: state.recovery.length,
        sleep: state.sleep.length,
        heart: state.heart.length,
      },
      summary,
      syncedAt: new Date().toISOString(),
    });
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : 'Health sync failed.' },
      { status: 502 }
    );
  }
}

