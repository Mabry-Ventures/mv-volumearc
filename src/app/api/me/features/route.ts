import { NextResponse } from 'next/server';
import { aiFlags } from '@/lib/ai/flags';
import { getActorIdFromRequest } from '@/lib/server/actor';
import { getEntitlementForActor } from '@/lib/server/entitlements';
import { featureFlags } from '@/lib/flags';

export const runtime = 'nodejs';

export async function GET(request: Request) {
  const actorId = getActorIdFromRequest(request);
  const entitlement = getEntitlementForActor(actorId);

  return NextResponse.json({
    actorId,
    entitlement,
    featureFlags: {
      aiWorkoutPlan: aiFlags.workoutPlan,
      aiLiveCoach: aiFlags.liveCoach,
      aiPostWorkout: aiFlags.postWorkout,
      aiRiskAnalysis: aiFlags.riskAnalysis,
      aiLogParser: aiFlags.logParser,
      aiTranscribe: aiFlags.transcribe,
      aiProgressionPlan: aiFlags.progressionPlan,
      telemetryIngest: featureFlags.telemetryIngest,
      cloudSync: entitlement.syncEnabled && featureFlags.cloudSyncAlpha,
      progressionAutopilot: featureFlags.progressionAutopilot,
      retentionLoops: featureFlags.retentionLoops,
      healthIntegrations: featureFlags.healthIntegrations,
      monetizationControls: featureFlags.monetizationControls,
    },
    generatedAt: new Date().toISOString(),
  });
}
