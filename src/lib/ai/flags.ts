const isEnabled = (value: string | undefined, defaultValue = true): boolean => {
  if (value === undefined) return defaultValue;
  return value === '1' || value.toLowerCase() === 'true';
};

export const aiFlags = {
  workoutPlan: isEnabled(process.env.AI_ENABLE_WORKOUT_PLAN),
  liveCoach: isEnabled(process.env.AI_ENABLE_LIVE_COACH),
  postWorkout: isEnabled(process.env.AI_ENABLE_POST_WORKOUT),
  riskAnalysis: isEnabled(process.env.AI_ENABLE_RISK_ANALYSIS),
  logParser: isEnabled(process.env.AI_ENABLE_LOG_PARSER),
  transcribe: isEnabled(process.env.AI_ENABLE_TRANSCRIBE),
};
