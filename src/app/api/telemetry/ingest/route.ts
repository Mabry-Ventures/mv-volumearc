import { NextResponse } from 'next/server';
import type { UiInteractionEvent, WorkoutFunnelEvent } from '@/types';
import { telemetryStore } from '@/lib/server/telemetryStore';
import { getActorIdFromRequest } from '@/lib/server/actor';
import { featureFlags } from '@/lib/flags';
import { telemetryExporter } from '@/lib/server/telemetryExporter';

export const runtime = 'nodejs';

const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null;

const isUiInteractionEvent = (value: unknown): value is UiInteractionEvent => {
  if (!isObject(value)) return false;
  return (
    typeof value.id === 'string' &&
    typeof value.stage === 'string' &&
    typeof value.action === 'string' &&
    typeof value.createdAt === 'string'
  );
};

const isWorkoutFunnelEvent = (value: unknown): value is WorkoutFunnelEvent => {
  if (!isObject(value)) return false;
  return (
    typeof value.id === 'string' &&
    typeof value.actorId === 'string' &&
    typeof value.stage === 'string' &&
    typeof value.createdAt === 'string'
  );
};

export async function POST(request: Request) {
  if (!featureFlags.telemetryIngest) {
    return NextResponse.json({ error: 'Telemetry ingestion is currently disabled.' }, { status: 503 });
  }

  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return NextResponse.json({ error: 'Invalid telemetry payload.' }, { status: 400 });
  }

  if (!isObject(payload)) {
    return NextResponse.json({ error: 'Telemetry payload must be an object.' }, { status: 400 });
  }

  const uiEvents = Array.isArray(payload.uiEvents)
    ? payload.uiEvents.filter(isUiInteractionEvent)
    : [];

  const funnelEvents = Array.isArray(payload.funnelEvents)
    ? payload.funnelEvents.filter(isWorkoutFunnelEvent)
    : [];

  if (uiEvents.length === 0 && funnelEvents.length === 0) {
    return NextResponse.json(
      { error: 'No valid telemetry events supplied.' },
      { status: 400 }
    );
  }

  const actorId = getActorIdFromRequest(request);

  const acceptedUi = telemetryStore.ingestUiEvents(uiEvents, actorId);
  const acceptedFunnel = telemetryStore.ingestFunnelEvents(funnelEvents);
  void telemetryExporter.exportDashboard('telemetry-ingest', actorId);

  return NextResponse.json({
    acceptedUi,
    acceptedFunnel,
    actorId,
    receivedAt: new Date().toISOString(),
  });
}
