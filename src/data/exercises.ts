import { Exercise } from '@/types';

export const defaultExercises: Exercise[] = [
  // Chest
  {
    id: 'bench-press',
    name: 'Bench Press',
    category: 'barbell',
    muscleGroups: ['chest', 'triceps', 'shoulders'],
    description: 'Lie on bench, lower bar to chest, press up'
  },
  {
    id: 'incline-bench-press',
    name: 'Incline Bench Press',
    category: 'barbell',
    muscleGroups: ['chest', 'shoulders', 'triceps'],
    description: 'Bench press on incline bench targeting upper chest'
  },
  {
    id: 'dumbbell-flyes',
    name: 'Dumbbell Flyes',
    category: 'dumbbell',
    muscleGroups: ['chest'],
    description: 'Lie on bench, arc dumbbells from sides to above chest'
  },
  {
    id: 'push-ups',
    name: 'Push-Ups',
    category: 'bodyweight',
    muscleGroups: ['chest', 'triceps', 'shoulders'],
    description: 'Classic bodyweight chest exercise'
  },

  // Back
  {
    id: 'deadlift',
    name: 'Deadlift',
    category: 'barbell',
    muscleGroups: ['back', 'legs', 'glutes'],
    description: 'Lift barbell from floor to hip level'
  },
  {
    id: 'barbell-row',
    name: 'Barbell Row',
    category: 'barbell',
    muscleGroups: ['back', 'biceps'],
    description: 'Bend over, pull barbell to lower chest'
  },
  {
    id: 'pull-ups',
    name: 'Pull-Ups',
    category: 'bodyweight',
    muscleGroups: ['back', 'biceps'],
    description: 'Hang from bar, pull chin above bar'
  },
  {
    id: 'lat-pulldown',
    name: 'Lat Pulldown',
    category: 'cable',
    muscleGroups: ['back', 'biceps'],
    description: 'Pull cable bar down to chest level'
  },

  // Shoulders
  {
    id: 'overhead-press',
    name: 'Overhead Press',
    category: 'barbell',
    muscleGroups: ['shoulders', 'triceps'],
    description: 'Press barbell from shoulders to overhead'
  },
  {
    id: 'lateral-raises',
    name: 'Lateral Raises',
    category: 'dumbbell',
    muscleGroups: ['shoulders'],
    description: 'Raise dumbbells to sides until parallel to floor'
  },
  {
    id: 'face-pulls',
    name: 'Face Pulls',
    category: 'cable',
    muscleGroups: ['shoulders', 'back'],
    description: 'Pull cable rope to face level'
  },

  // Arms
  {
    id: 'barbell-curl',
    name: 'Barbell Curl',
    category: 'barbell',
    muscleGroups: ['biceps'],
    description: 'Curl barbell from thighs to shoulders'
  },
  {
    id: 'dumbbell-curl',
    name: 'Dumbbell Curl',
    category: 'dumbbell',
    muscleGroups: ['biceps'],
    description: 'Curl dumbbells alternating or together'
  },
  {
    id: 'tricep-pushdown',
    name: 'Tricep Pushdown',
    category: 'cable',
    muscleGroups: ['triceps'],
    description: 'Push cable down, extending elbows'
  },
  {
    id: 'skull-crushers',
    name: 'Skull Crushers',
    category: 'barbell',
    muscleGroups: ['triceps'],
    description: 'Lie on bench, lower bar to forehead, extend'
  },

  // Legs
  {
    id: 'squat',
    name: 'Squat',
    category: 'barbell',
    muscleGroups: ['legs', 'glutes', 'core'],
    description: 'Bar on back, squat down and up'
  },
  {
    id: 'leg-press',
    name: 'Leg Press',
    category: 'machine',
    muscleGroups: ['legs', 'glutes'],
    description: 'Press platform away using legs'
  },
  {
    id: 'lunges',
    name: 'Lunges',
    category: 'dumbbell',
    muscleGroups: ['legs', 'glutes'],
    description: 'Step forward, lower back knee toward floor'
  },
  {
    id: 'leg-curl',
    name: 'Leg Curl',
    category: 'machine',
    muscleGroups: ['legs'],
    description: 'Curl weight using hamstrings'
  },
  {
    id: 'leg-extension',
    name: 'Leg Extension',
    category: 'machine',
    muscleGroups: ['legs'],
    description: 'Extend legs against resistance'
  },
  {
    id: 'calf-raises',
    name: 'Calf Raises',
    category: 'machine',
    muscleGroups: ['calves'],
    description: 'Rise up on toes against resistance'
  },

  // Core
  {
    id: 'plank',
    name: 'Plank',
    category: 'bodyweight',
    muscleGroups: ['core'],
    description: 'Hold body in straight line on forearms and toes'
  },
  {
    id: 'crunches',
    name: 'Crunches',
    category: 'bodyweight',
    muscleGroups: ['core'],
    description: 'Lie on back, curl shoulders toward hips'
  },
  {
    id: 'hanging-leg-raises',
    name: 'Hanging Leg Raises',
    category: 'bodyweight',
    muscleGroups: ['core'],
    description: 'Hang from bar, raise legs to parallel'
  },

  // Cardio
  {
    id: 'treadmill',
    name: 'Treadmill',
    category: 'cardio',
    muscleGroups: ['legs'],
    description: 'Walking or running on treadmill'
  },
  {
    id: 'cycling',
    name: 'Stationary Bike',
    category: 'cardio',
    muscleGroups: ['legs'],
    description: 'Cycling on stationary bike'
  },
  {
    id: 'rowing',
    name: 'Rowing Machine',
    category: 'cardio',
    muscleGroups: ['back', 'legs', 'core'],
    description: 'Full body cardio on rowing machine'
  }
];

export const getExercisesByCategory = (category: string): Exercise[] => {
  return defaultExercises.filter(e => e.category === category);
};

export const getExercisesByMuscle = (muscle: string): Exercise[] => {
  return defaultExercises.filter(e => e.muscleGroups.includes(muscle as any));
};

export const getExerciseById = (id: string): Exercise | undefined => {
  return defaultExercises.find(e => e.id === id);
};
