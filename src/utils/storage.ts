import { Workout, WorkoutTemplate, PersonalRecord } from '@/types';

const STORAGE_KEYS = {
  WORKOUTS: 'beast-mode-workouts',
  TEMPLATES: 'beast-mode-templates',
  PERSONAL_RECORDS: 'beast-mode-prs',
  CURRENT_WORKOUT: 'beast-mode-current',
  SETTINGS: 'beast-mode-settings',
};

export const storage = {
  // Workouts
  getWorkouts: (): Workout[] => {
    if (typeof window === 'undefined') return [];
    const data = localStorage.getItem(STORAGE_KEYS.WORKOUTS);
    return data ? JSON.parse(data) : [];
  },

  saveWorkouts: (workouts: Workout[]): void => {
    if (typeof window === 'undefined') return;
    localStorage.setItem(STORAGE_KEYS.WORKOUTS, JSON.stringify(workouts));
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
    if (typeof window === 'undefined') return [];
    const data = localStorage.getItem(STORAGE_KEYS.TEMPLATES);
    return data ? JSON.parse(data) : [];
  },

  saveTemplates: (templates: WorkoutTemplate[]): void => {
    if (typeof window === 'undefined') return;
    localStorage.setItem(STORAGE_KEYS.TEMPLATES, JSON.stringify(templates));
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
    if (typeof window === 'undefined') return [];
    const data = localStorage.getItem(STORAGE_KEYS.PERSONAL_RECORDS);
    return data ? JSON.parse(data) : [];
  },

  savePersonalRecords: (records: PersonalRecord[]): void => {
    if (typeof window === 'undefined') return;
    localStorage.setItem(STORAGE_KEYS.PERSONAL_RECORDS, JSON.stringify(records));
  },

  // Current Workout (in progress)
  getCurrentWorkout: (): Workout | null => {
    if (typeof window === 'undefined') return null;
    const data = localStorage.getItem(STORAGE_KEYS.CURRENT_WORKOUT);
    return data ? JSON.parse(data) : null;
  },

  saveCurrentWorkout: (workout: Workout | null): void => {
    if (typeof window === 'undefined') return;
    if (workout) {
      localStorage.setItem(STORAGE_KEYS.CURRENT_WORKOUT, JSON.stringify(workout));
    } else {
      localStorage.removeItem(STORAGE_KEYS.CURRENT_WORKOUT);
    }
  },

  // Settings
  getSettings: (): { unit: 'lbs' | 'kg' } => {
    if (typeof window === 'undefined') return { unit: 'lbs' };
    const data = localStorage.getItem(STORAGE_KEYS.SETTINGS);
    return data ? JSON.parse(data) : { unit: 'lbs' };
  },

  saveSettings: (settings: { unit: 'lbs' | 'kg' }): void => {
    if (typeof window === 'undefined') return;
    localStorage.setItem(STORAGE_KEYS.SETTINGS, JSON.stringify(settings));
  },

  // Clear all data
  clearAll: (): void => {
    if (typeof window === 'undefined') return;
    Object.values(STORAGE_KEYS).forEach(key => {
      localStorage.removeItem(key);
    });
  },
};
