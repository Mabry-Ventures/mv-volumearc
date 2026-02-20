const isEnabled = (value: string | undefined, defaultValue = true): boolean => {
  if (value === undefined) return defaultValue;
  return value === '1' || value.toLowerCase() === 'true';
};

export const featureFlags = {
  telemetryIngest: isEnabled(process.env.FEATURE_TELEMETRY_INGEST, true),
  cloudSyncAlpha: isEnabled(process.env.FEATURE_CLOUD_SYNC_ALPHA, false),
  progressionAutopilot: isEnabled(process.env.FEATURE_PROGRESSION_AUTOPILOT, true),
  retentionLoops: isEnabled(process.env.FEATURE_RETENTION_LOOPS, true),
  healthIntegrations: isEnabled(process.env.FEATURE_HEALTH_INTEGRATIONS, false),
  monetizationControls: isEnabled(process.env.FEATURE_MONETIZATION_CONTROLS, true),
};

