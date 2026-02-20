import type { DesignTokenSet } from '@/types';

export const beastDesignTokens: DesignTokenSet = {
  color: {
    bg: '#070b12',
    bgElevated: '#101826',
    fg: '#f6f7fb',
    muted: '#90a1b9',
    accent: '#ff7b2c',
    border: '#263248',
    success: '#18d49b',
    warning: '#f7b955',
    danger: '#ff5e6a',
  },
  radius: {
    sm: 8,
    md: 12,
    lg: 18,
    xl: 24,
    pill: 999,
  },
  spacing: {
    xs: 4,
    sm: 8,
    md: 12,
    lg: 16,
    xl: 24,
    xxl: 32,
  },
  motion: {
    fastMs: 120,
    normalMs: 220,
    slowMs: 320,
  },
};
