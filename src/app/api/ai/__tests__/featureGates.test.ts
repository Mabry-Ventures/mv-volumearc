/** @jest-environment node */

import { POST as liveCoachPost } from '@/app/api/ai/live-coach/route';
import { POST as parseLogPost } from '@/app/api/ai/parse-log/route';
import { POST as postWorkoutPost } from '@/app/api/ai/post-workout/route';
import { POST as riskAnalysisPost } from '@/app/api/ai/risk-analysis/route';
import { POST as transcribePost } from '@/app/api/ai/transcribe/route';
import { POST as workoutPlanPost } from '@/app/api/ai/workout-plan/route';
import { aiFlags } from '@/lib/ai/flags';

describe('AI route feature gates', () => {
  const originalFlags = { ...aiFlags };

  beforeEach(() => {
    Object.assign(aiFlags, originalFlags);
  });

  afterAll(() => {
    Object.assign(aiFlags, originalFlags);
  });

  it('blocks workout-plan when feature flag is off', async () => {
    aiFlags.workoutPlan = false;
    const response = await workoutPlanPost(new Request('http://localhost/api/ai/workout-plan', { method: 'POST' }));
    expect(response.status).toBe(503);
  });

  it('blocks live-coach when feature flag is off', async () => {
    aiFlags.liveCoach = false;
    const response = await liveCoachPost(new Request('http://localhost/api/ai/live-coach', { method: 'POST' }));
    expect(response.status).toBe(503);
  });

  it('blocks post-workout when feature flag is off', async () => {
    aiFlags.postWorkout = false;
    const response = await postWorkoutPost(new Request('http://localhost/api/ai/post-workout', { method: 'POST' }));
    expect(response.status).toBe(503);
  });

  it('blocks risk-analysis when feature flag is off', async () => {
    aiFlags.riskAnalysis = false;
    const response = await riskAnalysisPost(new Request('http://localhost/api/ai/risk-analysis', { method: 'POST' }));
    expect(response.status).toBe(503);
  });

  it('blocks parse-log when feature flag is off', async () => {
    aiFlags.logParser = false;
    const response = await parseLogPost(new Request('http://localhost/api/ai/parse-log', { method: 'POST' }));
    expect(response.status).toBe(503);
  });

  it('blocks transcribe when feature flag is off', async () => {
    aiFlags.transcribe = false;
    const response = await transcribePost(new Request('http://localhost/api/ai/transcribe', { method: 'POST' }));
    expect(response.status).toBe(503);
  });
});

