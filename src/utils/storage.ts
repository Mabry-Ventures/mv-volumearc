import type {
  AiUserPreferences,
  Exercise,
  ExerciseCategory,
  MuscleGroup,
  NotificationPreference,
  PersonalRecord,
  Workout,
  WorkoutAiSummary,
  WorkoutUxPreferences,
  WorkoutTemplate,
} from '@/types';

const STORAGE_KEYS = {
  WORKOUTS: 'beast-mode-workouts',
  TEMPLATES: 'beast-mode-templates',
  PERSONAL_RECORDS: 'beast-mode-prs',
  CURRENT_WORKOUT: 'beast-mode-current',
  SETTINGS: 'beast-mode-settings',
  AI_PREFERENCES: 'beast-mode-ai-preferences',
  AI_CACHE: 'beast-mode-ai-cache',
  WORKOUT_UX_PREFERENCES: 'beast-mode-workout-ux-preferences',
  NOTIFICATION_PREFERENCES: 'beast-mode-notification-preferences',
} as const;

const DEFAULT_SETTINGS = { unit: 'lbs' as const };
const DEFAULT_AI_PREFERENCES: AiUserPreferences = {
  coachingStyle: 'encouraging',
  verbosity: 'balanced',
  riskSensitivity: 'medium',
  autoApplySuggestions: false,
  shareFullHistory: true,
  enableSpeechLogging: true,
  dailyBudgetUsd: 2,
};
const DEFAULT_WORKOUT_UX_PREFERENCES: WorkoutUxPreferences = {
  compactMode: false,
  enableHaptics: true,
  autoStartRestTimer: true,
  restTimerDefaultSeconds: 90,
  showPreviousValues: true,
};
const DEFAULT_NOTIFICATION_PREFERENCES: NotificationPreference = {
  webPushEnabled: false,
  emailEnabled: false,
  streakRescueEnabled: true,
  nextWorkoutReminderEnabled: true,
  reminderHourLocal: 18,
};

const VALID_EXERCISE_CATEGORIES: ExerciseCategory[] = [
  'barbell',
  'dumbbell',
  'machine',
  'bodyweight',
  'cable',
  'cardio',
];

const VALID_MUSCLE_GROUPS: MuscleGroup[] = [
  'chest',
  'back',
  'shoulders',
  'biceps',
  'triceps',
  'legs',
  'glutes',
  'core',
  'forearms',
  'calves',
];

type UnknownRecord = Record<string, unknown>;

const isObject = (value: unknown): value is UnknownRecord =>
  typeof value === 'object' && value !== null;

const isString = (value: unknown): value is string => typeof value === 'string';

const isFiniteNumber = (value: unknown): value is number =>
  typeof value === 'number' && Number.isFinite(value);

const isBoolean = (value: unknown): value is boolean => typeof value === 'boolean';

const isUnit = (value: unknown): value is 'lbs' | 'kg' =>
  value === 'lbs' || value === 'kg';

const isExerciseCategory = (value: unknown): value is ExerciseCategory =>
  isString(value) && VALID_EXERCISE_CATEGORIES.includes(value as ExerciseCategory);

const isMuscleGroup = (value: unknown): value is MuscleGroup =>
  isString(value) && VALID_MUSCLE_GROUPS.includes(value as MuscleGroup);

const isExercise = (value: unknown): value is Exercise => {
  if (!isObject(value)) return false;

  if (!isString(value.id) || !isString(value.name)) return false;
  if (!isExerciseCategory(value.category)) return false;
  if (!Array.isArray(value.muscleGroups) || !value.muscleGroups.every(isMuscleGroup)) {
    return false;
  }

  return value.description === undefined || isString(value.description);
};

const isWorkoutSet = (value: unknown): boolean => {
  if (!isObject(value)) return false;

  if (!isString(value.id)) return false;
  if (!isFiniteNumber(value.reps) || value.reps < 0) return false;
  if (!isFiniteNumber(value.weight) || value.weight < 0) return false;
  if (!isUnit(value.unit)) return false;
  if (!isBoolean(value.completed)) return false;

  if (value.rpe !== undefined && (!isFiniteNumber(value.rpe) || value.rpe < 1 || value.rpe > 10)) {
    return false;
  }

  return true;
};

const isWorkoutExercise = (value: unknown): boolean => {
  if (!isObject(value)) return false;

  if (!isString(value.id)) return false;
  if (!isExercise(value.exercise)) return false;
  if (!Array.isArray(value.sets) || !value.sets.every(isWorkoutSet)) return false;

  return value.notes === undefined || isString(value.notes);
};

const isWorkout = (value: unknown): value is Workout => {
  if (!isObject(value)) return false;

  if (!isString(value.id) || !isString(value.name) || !isString(value.date)) return false;
  if (!Array.isArray(value.exercises) || !value.exercises.every(isWorkoutExercise)) return false;
  if (!isBoolean(value.completed)) return false;

  if (value.duration !== undefined && (!isFiniteNumber(value.duration) || value.duration < 0)) {
    return false;
  }

  if (value.notes !== undefined && !isString(value.notes)) return false;
  if (value.aiSummary !== undefined && !isWorkoutAiSummary(value.aiSummary)) return false;

  return true;
};

const isTemplateExercise = (value: unknown): boolean => {
  if (!isObject(value)) return false;

  return (
    isExercise(value.exercise) &&
    isFiniteNumber(value.targetSets) &&
    value.targetSets >= 0 &&
    isFiniteNumber(value.targetReps) &&
    value.targetReps >= 0
  );
};

const isWorkoutTemplate = (value: unknown): value is WorkoutTemplate => {
  if (!isObject(value)) return false;

  return (
    isString(value.id) &&
    isString(value.name) &&
    Array.isArray(value.exercises) &&
    value.exercises.every(isTemplateExercise)
  );
};

const normalizePersonalRecord = (value: unknown): PersonalRecord | null => {
  if (!isObject(value)) return null;

  const exercise = isExercise(value.exercise)
    ? value.exercise
    : isExercise(value.odeum)
      ? value.odeum
      : null;

  if (!exercise) return null;
  if (!isString(value.id)) return null;
  if (!isFiniteNumber(value.weight) || value.weight < 0) return null;
  if (!isFiniteNumber(value.reps) || value.reps < 0) return null;
  if (!isString(value.date) || !isString(value.workoutId)) return null;

  return {
    id: value.id,
    exercise,
    weight: value.weight,
    reps: value.reps,
    date: value.date,
    workoutId: value.workoutId,
  };
};

const isSettings = (value: unknown): value is { unit: 'lbs' | 'kg' } =>
  isObject(value) && isUnit(value.unit);

const isWorkoutAiSummary = (value: unknown): value is WorkoutAiSummary => {
  if (!isObject(value)) return false;
  if (!isString(value.generatedAt)) return false;
  if (!isString(value.model)) return false;
  if (!isString(value.summary)) return false;
  if (!Array.isArray(value.keyWins) || !value.keyWins.every(isString)) return false;
  if (!Array.isArray(value.prCandidates)) return false;
  if (
    !isObject(value.nextSessionRecommendation) ||
    !isString(value.nextSessionRecommendation.focus) ||
    !isString(value.nextSessionRecommendation.rationale) ||
    !Array.isArray(value.nextSessionRecommendation.adjustments) ||
    !value.nextSessionRecommendation.adjustments.every(isString)
  ) {
    return false;
  }

  return true;
};

const isAiUserPreferences = (value: unknown): value is AiUserPreferences => {
  if (!isObject(value)) return false;

  const validCoachingStyle =
    value.coachingStyle === 'direct' ||
    value.coachingStyle === 'encouraging' ||
    value.coachingStyle === 'technical';
  const validVerbosity =
    value.verbosity === 'brief' ||
    value.verbosity === 'balanced' ||
    value.verbosity === 'detailed';
  const validRiskSensitivity =
    value.riskSensitivity === 'low' ||
    value.riskSensitivity === 'medium' ||
    value.riskSensitivity === 'high';

  return (
    validCoachingStyle &&
    validVerbosity &&
    validRiskSensitivity &&
    isBoolean(value.autoApplySuggestions) &&
    isBoolean(value.shareFullHistory) &&
    isBoolean(value.enableSpeechLogging) &&
    isFiniteNumber(value.dailyBudgetUsd) &&
    value.dailyBudgetUsd >= 0
  );
};

const isAiCache = (value: unknown): value is Record<string, unknown> => {
  if (!isObject(value)) return false;
  if (!('updatedAt' in value) || !isString(value.updatedAt)) return false;
  return true;
};

const isWorkoutUxPreferences = (value: unknown): value is WorkoutUxPreferences => {
  if (!isObject(value)) return false;

  return (
    isBoolean(value.compactMode) &&
    isBoolean(value.enableHaptics) &&
    isBoolean(value.autoStartRestTimer) &&
    isFiniteNumber(value.restTimerDefaultSeconds) &&
    value.restTimerDefaultSeconds >= 15 &&
    value.restTimerDefaultSeconds <= 300 &&
    isBoolean(value.showPreviousValues)
  );
};

const isNotificationPreference = (value: unknown): value is NotificationPreference => {
  if (!isObject(value)) return false;

  return (
    isBoolean(value.webPushEnabled) &&
    isBoolean(value.emailEnabled) &&
    isBoolean(value.streakRescueEnabled) &&
    isBoolean(value.nextWorkoutReminderEnabled) &&
    isFiniteNumber(value.reminderHourLocal) &&
    value.reminderHourLocal >= 0 &&
    value.reminderHourLocal <= 23
  );
};

const readRaw = (key: string): unknown => {
  if (typeof window === 'undefined') return null;

  const data = localStorage.getItem(key);
  if (data === null) return null;

  try {
    return JSON.parse(data);
  } catch {
    localStorage.removeItem(key);
    return null;
  }
};

const writeRaw = (key: string, value: unknown): void => {
  if (typeof window === 'undefined') return;
  localStorage.setItem(key, JSON.stringify(value));
};

const readValidatedArray = <T>(
  key: string,
  validator: (value: unknown) => value is T
): T[] => {
  const parsed = readRaw(key);
  if (parsed === null) return [];

  if (!Array.isArray(parsed)) {
    localStorage.removeItem(key);
    return [];
  }

  const valid = parsed.filter(validator);
  if (valid.length !== parsed.length) {
    writeRaw(key, valid);
  }

  return valid;
};

const readPersonalRecords = (): PersonalRecord[] => {
  const parsed = readRaw(STORAGE_KEYS.PERSONAL_RECORDS);
  if (parsed === null) return [];

  if (!Array.isArray(parsed)) {
    localStorage.removeItem(STORAGE_KEYS.PERSONAL_RECORDS);
    return [];
  }

  const normalized = parsed
    .map(normalizePersonalRecord)
    .filter((record): record is PersonalRecord => record !== null);

  if (normalized.length !== parsed.length) {
    writeRaw(STORAGE_KEYS.PERSONAL_RECORDS, normalized);
  }

  return normalized;
};

const toValidatedArray = <T>(
  value: unknown,
  validator: (entry: unknown) => entry is T
): T[] | null => {
  if (!Array.isArray(value)) return null;
  return value.every(validator) ? value : null;
};

const toValidatedPersonalRecords = (value: unknown): PersonalRecord[] | null => {
  if (!Array.isArray(value)) return null;

  const normalized = value.map(normalizePersonalRecord);
  if (normalized.some(record => record === null)) return null;

  return normalized as PersonalRecord[];
};

export const storage = {
  // Workouts
  getWorkouts: (): Workout[] => {
    return readValidatedArray(STORAGE_KEYS.WORKOUTS, isWorkout);
  },

  saveWorkouts: (workouts: Workout[]): void => {
    if (typeof window === 'undefined') return;
    writeRaw(STORAGE_KEYS.WORKOUTS, workouts);
  },

  addWorkout: (workout: Workout): void => {
    const workouts = storage.getWorkouts();
    workouts.push(workout);
    storage.saveWorkouts(workouts);
  },

  updateWorkout: (workout: Workout): void => {
    const workouts = storage.getWorkouts();
    const index = workouts.findIndex(w => w.id === workout.id);
    if (index !== -1) {
      workouts[index] = workout;
      storage.saveWorkouts(workouts);
    }
  },

  deleteWorkout: (id: string): void => {
    const workouts = storage.getWorkouts().filter(w => w.id !== id);
    storage.saveWorkouts(workouts);
  },

  // Templates
  getTemplates: (): WorkoutTemplate[] => {
    return readValidatedArray(STORAGE_KEYS.TEMPLATES, isWorkoutTemplate);
  },

  saveTemplates: (templates: WorkoutTemplate[]): void => {
    if (typeof window === 'undefined') return;
    writeRaw(STORAGE_KEYS.TEMPLATES, templates);
  },

  addTemplate: (template: WorkoutTemplate): void => {
    const templates = storage.getTemplates();
    templates.push(template);
    storage.saveTemplates(templates);
  },

  deleteTemplate: (id: string): void => {
    const templates = storage.getTemplates().filter(t => t.id !== id);
    storage.saveTemplates(templates);
  },

  // Personal Records
  getPersonalRecords: (): PersonalRecord[] => {
    return readPersonalRecords();
  },

  savePersonalRecords: (records: PersonalRecord[]): void => {
    if (typeof window === 'undefined') return;
    writeRaw(STORAGE_KEYS.PERSONAL_RECORDS, records);
  },

  // Current Workout (in progress)
  getCurrentWorkout: (): Workout | null => {
    const parsed = readRaw(STORAGE_KEYS.CURRENT_WORKOUT);

    if (parsed === null) return null;

    if (!isWorkout(parsed)) {
      localStorage.removeItem(STORAGE_KEYS.CURRENT_WORKOUT);
      return null;
    }

    return parsed;
  },

  saveCurrentWorkout: (workout: Workout | null): void => {
    if (typeof window === 'undefined') return;
    if (workout) {
      writeRaw(STORAGE_KEYS.CURRENT_WORKOUT, workout);
    } else {
      localStorage.removeItem(STORAGE_KEYS.CURRENT_WORKOUT);
    }
  },

  // Settings
  getSettings: (): { unit: 'lbs' | 'kg' } => {
    const parsed = readRaw(STORAGE_KEYS.SETTINGS);

    if (parsed === null) return DEFAULT_SETTINGS;

    if (!isSettings(parsed)) {
      localStorage.removeItem(STORAGE_KEYS.SETTINGS);
      return DEFAULT_SETTINGS;
    }

    return parsed;
  },

  saveSettings: (settings: { unit: 'lbs' | 'kg' }): void => {
    if (typeof window === 'undefined') return;
    writeRaw(STORAGE_KEYS.SETTINGS, settings);
  },

  getAiPreferences: (): AiUserPreferences => {
    const parsed = readRaw(STORAGE_KEYS.AI_PREFERENCES);
    if (parsed === null) return DEFAULT_AI_PREFERENCES;

    if (!isAiUserPreferences(parsed)) {
      localStorage.removeItem(STORAGE_KEYS.AI_PREFERENCES);
      return DEFAULT_AI_PREFERENCES;
    }

    return parsed;
  },

  saveAiPreferences: (preferences: AiUserPreferences): void => {
    if (typeof window === 'undefined') return;
    writeRaw(STORAGE_KEYS.AI_PREFERENCES, preferences);
  },

  getAiCache: (): Record<string, unknown> => {
    const parsed = readRaw(STORAGE_KEYS.AI_CACHE);
    if (parsed === null) return { updatedAt: new Date().toISOString() };

    if (!isAiCache(parsed)) {
      localStorage.removeItem(STORAGE_KEYS.AI_CACHE);
      return { updatedAt: new Date().toISOString() };
    }

    return parsed;
  },

  saveAiCache: (cache: Record<string, unknown>): void => {
    if (typeof window === 'undefined') return;
    writeRaw(STORAGE_KEYS.AI_CACHE, cache);
  },

  getWorkoutUxPreferences: (): WorkoutUxPreferences => {
    const parsed = readRaw(STORAGE_KEYS.WORKOUT_UX_PREFERENCES);
    if (parsed === null) return DEFAULT_WORKOUT_UX_PREFERENCES;

    if (!isWorkoutUxPreferences(parsed)) {
      localStorage.removeItem(STORAGE_KEYS.WORKOUT_UX_PREFERENCES);
      return DEFAULT_WORKOUT_UX_PREFERENCES;
    }

    return parsed;
  },

  saveWorkoutUxPreferences: (preferences: WorkoutUxPreferences): void => {
    if (typeof window === 'undefined') return;
    writeRaw(STORAGE_KEYS.WORKOUT_UX_PREFERENCES, preferences);
  },

  getNotificationPreferences: (): NotificationPreference => {
    const parsed = readRaw(STORAGE_KEYS.NOTIFICATION_PREFERENCES);
    if (parsed === null) return DEFAULT_NOTIFICATION_PREFERENCES;

    if (!isNotificationPreference(parsed)) {
      localStorage.removeItem(STORAGE_KEYS.NOTIFICATION_PREFERENCES);
      return DEFAULT_NOTIFICATION_PREFERENCES;
    }

    return parsed;
  },

  saveNotificationPreferences: (preferences: NotificationPreference): void => {
    if (typeof window === 'undefined') return;
    writeRaw(STORAGE_KEYS.NOTIFICATION_PREFERENCES, preferences);
  },

  // Import backup data after strict validation.
  importData: (payload: unknown): boolean => {
    if (!isObject(payload)) return false;

    const hasSupportedFields =
      'workouts' in payload ||
      'templates' in payload ||
      'personalRecords' in payload ||
      'settings' in payload ||
      'aiPreferences' in payload ||
      'aiCache' in payload ||
      'workoutUxPreferences' in payload ||
      'notificationPreferences' in payload;

    if (!hasSupportedFields) return false;

    let validatedWorkouts: Workout[] | null = null;
    let validatedTemplates: WorkoutTemplate[] | null = null;
    let validatedPersonalRecords: PersonalRecord[] | null = null;
    let validatedSettings: { unit: 'lbs' | 'kg' } | null = null;
    let validatedAiPreferences: AiUserPreferences | null = null;
    let validatedAiCache: Record<string, unknown> | null = null;
    let validatedWorkoutUxPreferences: WorkoutUxPreferences | null = null;
    let validatedNotificationPreferences: NotificationPreference | null = null;

    if ('workouts' in payload) {
      validatedWorkouts = toValidatedArray(payload.workouts, isWorkout);
      if (validatedWorkouts === null) return false;
    }

    if ('templates' in payload) {
      validatedTemplates = toValidatedArray(payload.templates, isWorkoutTemplate);
      if (validatedTemplates === null) return false;
    }

    if ('personalRecords' in payload) {
      validatedPersonalRecords = toValidatedPersonalRecords(payload.personalRecords);
      if (validatedPersonalRecords === null) return false;
    }

    if ('settings' in payload) {
      if (!isSettings(payload.settings)) return false;
      validatedSettings = payload.settings;
    }

    if ('aiPreferences' in payload) {
      if (!isAiUserPreferences(payload.aiPreferences)) return false;
      validatedAiPreferences = payload.aiPreferences;
    }

    if ('aiCache' in payload) {
      if (!isAiCache(payload.aiCache)) return false;
      validatedAiCache = payload.aiCache;
    }

    if ('workoutUxPreferences' in payload) {
      if (!isWorkoutUxPreferences(payload.workoutUxPreferences)) return false;
      validatedWorkoutUxPreferences = payload.workoutUxPreferences;
    }

    if ('notificationPreferences' in payload) {
      if (!isNotificationPreference(payload.notificationPreferences)) return false;
      validatedNotificationPreferences = payload.notificationPreferences;
    }

    if (validatedWorkouts !== null) {
      storage.saveWorkouts(validatedWorkouts);
    }

    if (validatedTemplates !== null) {
      storage.saveTemplates(validatedTemplates);
    }

    if (validatedPersonalRecords !== null) {
      storage.savePersonalRecords(validatedPersonalRecords);
    }

    if (validatedSettings !== null) {
      storage.saveSettings(validatedSettings);
    }

    if (validatedAiPreferences !== null) {
      storage.saveAiPreferences(validatedAiPreferences);
    }

    if (validatedAiCache !== null) {
      storage.saveAiCache(validatedAiCache);
    }

    if (validatedWorkoutUxPreferences !== null) {
      storage.saveWorkoutUxPreferences(validatedWorkoutUxPreferences);
    }

    if (validatedNotificationPreferences !== null) {
      storage.saveNotificationPreferences(validatedNotificationPreferences);
    }

    return true;
  },

  // Clear all data
  clearAll: (): void => {
    if (typeof window === 'undefined') return;
    Object.values(STORAGE_KEYS).forEach(key => {
      localStorage.removeItem(key);
    });
  },
};
