import { NextResponse } from 'next/server';
import { telemetryStore } from '@/lib/server/telemetryStore';

export const runtime = 'nodejs';

export async function GET() {
  return NextResponse.json(telemetryStore.getDashboardSummary());
}
