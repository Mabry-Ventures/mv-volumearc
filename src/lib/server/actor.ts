import { headers } from 'next/headers';

const normalize = (value: string | null | undefined): string | null => {
  if (!value) return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
};

export const getActorIdFromRequest = (request: Request): string => {
  const userId = normalize(request.headers.get('x-user-id'));
  if (userId) return `user:${userId}`;

  const deviceId = normalize(request.headers.get('x-device-id'));
  if (deviceId) return `device:${deviceId}`;

  const forwardedFor = normalize(request.headers.get('x-forwarded-for'));
  if (forwardedFor) {
    const ip = forwardedFor.split(',')[0]?.trim();
    if (ip) return `ip:${ip}`;
  }

  const realIp = normalize(request.headers.get('x-real-ip'));
  if (realIp) return `ip:${realIp}`;

  return 'anonymous';
};

export const getActorIdFromServerHeaders = async (): Promise<string> => {
  const h = await headers();

  const userId = normalize(h.get('x-user-id'));
  if (userId) return `user:${userId}`;

  const deviceId = normalize(h.get('x-device-id'));
  if (deviceId) return `device:${deviceId}`;

  const forwardedFor = normalize(h.get('x-forwarded-for'));
  if (forwardedFor) {
    const ip = forwardedFor.split(',')[0]?.trim();
    if (ip) return `ip:${ip}`;
  }

  const realIp = normalize(h.get('x-real-ip'));
  if (realIp) return `ip:${realIp}`;

  return 'anonymous';
};
