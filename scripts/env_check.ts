const requiredVars = [
  'OPENAI_API_KEY',
  'OPENAI_MODEL_PRIMARY',
  'OPENAI_MODEL_FAST',
  'OPENAI_MODEL_TRANSCRIBE',
  'UPSTASH_REDIS_REST_URL',
  'UPSTASH_REDIS_REST_TOKEN',
  'DATABASE_URL',
] as const;

const authVarGroup = ['AUTH_SECRET', 'NEXTAUTH_SECRET'] as const;
const warningVars = ['TELEMETRY_EXPORT_URL'] as const;

const isSet = (value: string | undefined): boolean => typeof value === 'string' && value.trim().length > 0;

const missing = requiredVars.filter(name => !isSet(process.env[name]));
const hasAuthSecret = authVarGroup.some(name => isSet(process.env[name]));

if (missing.length > 0 || !hasAuthSecret) {
  console.error('Environment validation failed.');
  if (missing.length > 0) {
    console.error(`Missing required vars: ${missing.join(', ')}`);
  }
  if (!hasAuthSecret) {
    console.error(`Missing auth secret: set one of ${authVarGroup.join(' or ')}`);
  }
  process.exit(1);
}

const warnings = warningVars.filter(name => !isSet(process.env[name]));

console.log('Environment validation passed.');
if (warnings.length > 0) {
  console.log(`Recommended but unset: ${warnings.join(', ')}`);
}

