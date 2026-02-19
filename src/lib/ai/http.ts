import { NextResponse } from 'next/server';
import { costGuard } from '@/lib/ai/costGuard';
import { rateLimit } from '@/lib/ai/rateLimit';

export const getClientIp = (request: Request): string => {
  const forwardedFor = request.headers.get('x-forwarded-for');
  if (forwardedFor) {
    return forwardedFor.split(',')[0].trim();
  }
  return request.headers.get('x-real-ip') || 'unknown';
};

export const jsonError = (message: string, status = 400) =>
  NextResponse.json({ error: message }, { status });

export const enforceRateAndBudget = async (
  request: Request,
  endpoint: Parameters<typeof costGuard.getOutputTokenLimit>[0],
  inputSize: number,
  requestedBudgetUsd?: number
): Promise<NextResponse | null> => {
  const ip = getClientIp(request);

  const rate = await rateLimit.check(`${endpoint}:${ip}`);
  if (!rate.allowed) {
    return jsonError('Rate limit exceeded. Please try again shortly.', 429);
  }

  if (!costGuard.canSpendForIp(ip, inputSize, requestedBudgetUsd)) {
    return jsonError('Daily AI budget reached for this client IP.', 429);
  }

  return null;
};
