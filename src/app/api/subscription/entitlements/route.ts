import { NextResponse } from 'next/server';
import { getActorIdFromRequest } from '@/lib/server/actor';
import { getEntitlementForActor } from '@/lib/server/entitlements';
import { usageLedger } from '@/lib/server/usageLedger';
import { featureFlags } from '@/lib/flags';

export const runtime = 'nodejs';

export async function GET(request: Request) {
  if (!featureFlags.monetizationControls) {
    return NextResponse.json(
      { error: 'Subscription entitlements are currently disabled.' },
      { status: 503 }
    );
  }

  const actorId = getActorIdFromRequest(request);
  const entitlement = getEntitlementForActor(actorId);
  const usage = usageLedger.get(actorId);

  return NextResponse.json({
    actorId,
    entitlement,
    usage,
    canSpendMoreToday: usage.totalUsd < entitlement.maxDailyAiUsd,
    generatedAt: new Date().toISOString(),
  });
}
