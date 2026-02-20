export interface Exercise {
  id: string;
  name: string;
  category: ExerciseCategory;
  muscleGroups: MuscleGroup[];
  description?: string;
}

export type ExerciseCategory =
  | 'barbell'
  | 'dumbbell'
  | 'machine'
  | 'bodyweight'
  | 'cable'
  | 'cardio';

export type MuscleGroup =
  | 'chest'
  | 'back'
  | 'shoulders'
  | 'biceps'
  | 'triceps'
  | 'legs'
  | 'glutes'
  | 'core'
  | 'forearms'
  | 'calves';

export interface WorkoutSet {
  id: string;
  reps: number;
  weight: number;
  unit: 'lbs' | 'kg';
  completed: boolean;
  rpe?: number; // Rate of Perceived Exertion (1-10)
}

export interface AiTokenUsage {
  inputTokens: number;
  outputTokens: number;
  totalTokens: number;
}

export interface WorkoutAiSummary {
  generatedAt: string;
  model: string;
  summary: string;
  keyWins: string[];
  prCandidates: Array<{
    exerciseId: string;
    exerciseName: string;
    previousBest?: {
      weight: number;
      reps: number;
      unit: 'lbs' | 'kg';
      date?: string;
    };
    newBest: {
      weight: number;
      reps: number;
      unit: 'lbs' | 'kg';
    };
  }>;
  nextSessionRecommendation: {
    focus: string;
    rationale: string;
    adjustments: string[];
  };
  tokenUsage?: AiTokenUsage;
}

export interface WorkoutExercise {
  id: string;
  exercise: Exercise;
  sets: WorkoutSet[];
  notes?: string;
}

export interface Workout {
  id: string;
  name: string;
  date: string; // ISO date string
  exercises: WorkoutExercise[];
  duration?: number; // in minutes
  notes?: string;
  completed: boolean;
  aiSummary?: WorkoutAiSummary;
}

export interface WorkoutTemplate {
  id: string;
  name: string;
  exercises: {
    exercise: Exercise;
    targetSets: number;
    targetReps: number;
  }[];
}

export interface PersonalRecord {
  id: string;
  exercise: Exercise;
  // Legacy typo maintained for import compatibility.
  odeum?: Exercise;
  weight: number;
  reps: number;
  date: string;
  workoutId: string;
}

export interface UserStats {
  totalWorkouts: number;
  totalVolume: number; // total weight lifted
  currentStreak: number;
  longestStreak: number;
  favoriteExercise?: Exercise;
}

export interface AppState {
  workouts: Workout[];
  templates: WorkoutTemplate[];
  personalRecords: PersonalRecord[];
  currentWorkout: Workout | null;
}

export interface DesignTokenSet {
  color: {
    bg: string;
    bgElevated: string;
    fg: string;
    muted: string;
    accent: string;
    border: string;
    success: string;
    warning: string;
    danger: string;
  };
  radius: {
    sm: number;
    md: number;
    lg: number;
    xl: number;
    pill: number;
  };
  spacing: {
    xs: number;
    sm: number;
    md: number;
    lg: number;
    xl: number;
    xxl: number;
  };
  motion: {
    fastMs: number;
    normalMs: number;
    slowMs: number;
  };
}

export type WorkoutFlowStage =
  | 'home'
  | 'workout_start'
  | 'workout_active'
  | 'exercise_edit'
  | 'workout_complete'
  | 'history'
  | 'stats'
  | 'settings';

export type SetActionType =
  | 'set_complete_toggle'
  | 'set_add'
  | 'set_remove'
  | 'set_duplicate'
  | 'set_edit'
  | 'set_apply_live_coach';

export interface UiInteractionEvent {
  id: string;
  version: string;
  stage: WorkoutFlowStage;
  action: string;
  elapsedMs?: number;
  metadata?: Record<string, string | number | boolean | null>;
  actorId?: string;
  createdAt: string;
}

export interface CoachSuggestionApplyResult {
  suggestionId: string;
  actionability: 'apply' | 'review';
  applied: boolean;
  reason?: string;
}

export interface WorkoutUxPreferences {
  compactMode: boolean;
  enableHaptics: boolean;
  autoStartRestTimer: boolean;
  restTimerDefaultSeconds: number;
  showPreviousValues: boolean;
}

export interface WorkoutQuickAction {
  id: string;
  label: string;
  command: string;
  category: 'logging' | 'navigation' | 'coaching';
}

export interface AiUserPreferences {
  coachingStyle: 'direct' | 'encouraging' | 'technical';
  verbosity: 'brief' | 'balanced' | 'detailed';
  riskSensitivity: 'low' | 'medium' | 'high';
  autoApplySuggestions: boolean;
  shareFullHistory: boolean;
  enableSpeechLogging: boolean;
  dailyBudgetUsd: number;
}

export interface AiHistoryDigest {
  generatedAt: string;
  unit: 'lbs' | 'kg';
  schemaVersion: string;
  promptVersion: string;
  totalWorkouts: number;
  completedWorkouts: number;
  currentStreak: number;
  longestStreak: number;
  totalVolume: number;
  averageDurationMinutes: number;
  rollingVolume: {
    days7: number;
    days30: number;
    days90: number;
  };
  exerciseTrends: Array<{
    exerciseId: string;
    exerciseName: string;
    sessions: number;
    volume7d: number;
    volume30d: number;
    topSet?: {
      weight: number;
      reps: number;
      unit: 'lbs' | 'kg';
      date: string;
    };
    latestSet?: {
      weight: number;
      reps: number;
      unit: 'lbs' | 'kg';
      date: string;
    };
  }>;
  fatigueSignals: {
    plateauScore: number;
    overtrainingScore: number;
    lowPerformanceRuns: number;
    highRpeCount: number;
  };
  recentWorkouts: Workout[];
}

export interface AiSuggestion {
  recommendation: string;
  confidence: number;
  rationale: string[];
  fallbackReason?: string;
  tokenUsage?: AiTokenUsage;
}

export interface AiPlanExercise {
  exerciseId: string;
  exerciseName: string;
  category: ExerciseCategory;
  muscleGroups: MuscleGroup[];
  sets: number;
  reps: number;
  targetWeight: number;
  unit: 'lbs' | 'kg';
  restSeconds: number;
  notes?: string;
}

export interface AiWorkoutPlanRequest {
  goal: string;
  durationMinutes: number;
  equipment: string[];
  constraints: string[];
  fullHistoryDigest: AiHistoryDigest;
}

export interface AiWorkoutPlanResponse {
  workoutName: string;
  estimatedSessionMinutes?: number;
  warmup: string[];
  exercises: AiPlanExercise[];
  cooldown: string[];
  notes: string[];
  tokenUsage?: AiTokenUsage;
  fallbackReason?: string;
}

export interface AiLiveCoachRequest {
  activeWorkout: Workout;
  lastSet: WorkoutSet | null;
  fatigueSignals?: {
    soreness?: number;
    sleepHours?: number;
    stress?: number;
  };
  fullHistoryDigestLite: Pick<
    AiHistoryDigest,
    'unit' | 'rollingVolume' | 'exerciseTrends' | 'fatigueSignals'
  >;
}

export interface AiLiveCoachResponse {
  nextSet: {
    weight: number;
    reps: number;
    restSeconds: number;
    unit: 'lbs' | 'kg';
  };
  actionability?: 'apply' | 'review';
  confidence: number;
  rationale: string[];
  caution?: string;
  tokenUsage?: AiTokenUsage;
  fallbackReason?: string;
}

export interface AiPostWorkoutRequest {
  completedWorkout: Workout;
  fullHistoryDigest: AiHistoryDigest;
}

export type AiPostWorkoutResponse = WorkoutAiSummary;

export interface AiRiskAnalysisRequest {
  fullHistoryDigest: AiHistoryDigest;
  trendWindows: Array<7 | 30 | 90>;
}

export interface AiRiskAnalysisResponse {
  plateauRisk: {
    score: number;
    level: 'low' | 'medium' | 'high';
    reasons: string[];
  };
  overtrainingRisk: {
    score: number;
    level: 'low' | 'medium' | 'high';
    reasons: string[];
  };
  recommendedActions: string[];
  tokenUsage?: AiTokenUsage;
  fallbackReason?: string;
}

export interface AiParseLogRequest {
  text: string;
  sessionContext?: Workout | null;
}

export interface AiParsedSet {
  reps: number;
  weight: number;
  unit: 'lbs' | 'kg';
  completed?: boolean;
  rpe?: number;
}

export interface AiParsedExercise {
  exerciseId?: string;
  exerciseName: string;
  category?: ExerciseCategory;
  muscleGroups?: MuscleGroup[];
  sets: AiParsedSet[];
  notes?: string;
}

export interface AiParseLogResponse {
  confidence: number;
  requiresReview?: boolean;
  exercises: AiParsedExercise[];
  notes: string[];
  tokenUsage?: AiTokenUsage;
  fallbackReason?: string;
}

export interface AiTranscriptionResponse {
  text: string;
  confidence: number;
  durationSeconds?: number;
  fallbackReason?: string;
}

export interface WorkoutFunnelEvent {
  id: string;
  actorId: string;
  stage:
    | 'workout_started'
    | 'first_set_completed'
    | 'workout_completed'
    | 'workout_cancelled';
  createdAt: string;
  metadata?: Record<string, string | number | boolean | null>;
}

export interface AiLatencyEvent {
  id: string;
  actorId: string;
  endpoint:
    | 'workout-plan'
    | 'live-coach'
    | 'post-workout'
    | 'risk-analysis'
    | 'parse-log'
    | 'transcribe'
    | 'progression-plan';
  model: string;
  latencyMs: number;
  createdAt: string;
}

export interface AiFallbackEvent {
  id: string;
  actorId: string;
  endpoint:
    | 'workout-plan'
    | 'live-coach'
    | 'post-workout'
    | 'risk-analysis'
    | 'parse-log'
    | 'transcribe'
    | 'progression-plan';
  reason: string;
  createdAt: string;
}

export interface SyncOperation {
  id: string;
  deviceId: string;
  entityType: 'workout' | 'template' | 'preference';
  entityId: string;
  op: 'upsert' | 'delete';
  payload?: unknown;
  clientUpdatedAt: string;
  serverReceivedAt?: string;
}

export interface SyncCheckpoint {
  actorId: string;
  cursor: number;
  lastSyncedAt: string;
}

export type DeviceId = string;

export interface ConflictRecord {
  id: string;
  actorId: string;
  entityType: SyncOperation['entityType'];
  entityId: string;
  keptOperationId: string;
  droppedOperationId: string;
  reason: string;
  resolvedAt: string;
}

export interface AiEvalCase {
  id: string;
  category:
    | 'workout-plan-schema'
    | 'live-coach-quality'
    | 'parse-log-accuracy'
    | 'risk-consistency';
  input: unknown;
  expected: unknown;
  threshold?: number;
}

export interface AiEvalResult {
  caseId: string;
  category: AiEvalCase['category'];
  passed: boolean;
  score: number;
  details: string;
}

export interface ProgressionDecisionReason {
  code:
    | 'volume_up'
    | 'volume_down'
    | 'plateau_risk'
    | 'recovery_low'
    | 'stable_progress'
    | 'technique_focus';
  detail: string;
}

export interface TargetSetUpdate {
  exerciseId: string;
  exerciseName: string;
  currentTarget: {
    reps: number;
    weight: number;
    unit: 'lbs' | 'kg';
  };
  nextTarget: {
    reps: number;
    weight: number;
    unit: 'lbs' | 'kg';
  };
  confidence: number;
  reasons: ProgressionDecisionReason[];
}

export interface ProgressionBlock {
  generatedAt: string;
  blockName: string;
  durationWeeks: number;
  updates: TargetSetUpdate[];
  deloadRecommended: boolean;
  notes: string[];
}

export interface Entitlement {
  tier: 'free' | 'pro' | 'team';
  aiEnabled: boolean;
  liveCoachEnabled: boolean;
  syncEnabled: boolean;
  maxDailyAiUsd: number;
  maxMonthlyAiUsd: number;
  supportLevel: 'community' | 'priority';
}

export interface NotificationPreference {
  webPushEnabled: boolean;
  emailEnabled: boolean;
  streakRescueEnabled: boolean;
  nextWorkoutReminderEnabled: boolean;
  reminderHourLocal: number;
}

export interface RecoverySignal {
  recordedAt: string;
  score: number;
  source: 'manual' | 'apple-health' | 'google-fit' | 'wearable';
}

export interface SleepSignal {
  recordedAt: string;
  durationHours: number;
  qualityScore?: number;
  source: 'manual' | 'apple-health' | 'google-fit' | 'wearable';
}

export interface HrSignal {
  recordedAt: string;
  restingHr?: number;
  hrvMs?: number;
  source: 'manual' | 'apple-health' | 'google-fit' | 'wearable';
}
