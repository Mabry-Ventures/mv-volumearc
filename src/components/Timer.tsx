'use client';

import { Play, Pause, RotateCcw } from 'lucide-react';
import { useTimer } from '@/hooks/useTimer';

const PRESETS = [30, 60, 90, 120, 180];

export const Timer = () => {
  const timer = useTimer({
    initialTime: 90,
    onComplete: () => {
      // Could add sound/vibration here
      if (typeof window !== 'undefined' && 'vibrate' in navigator) {
        navigator.vibrate([200, 100, 200]);
      }
    },
  });

  return (
    <div className="timer">
      <div className="timer-display">{timer.formattedTime}</div>

      <div className="timer-progress">
        <div
          className="timer-progress-bar"
          style={{ width: `${timer.progress}%` }}
        />
      </div>

      <div className="flex justify-center gap-2 mt-4">
        {timer.isRunning ? (
          <button type="button" className="btn btn-secondary" onClick={timer.pause}>
            <Pause size={20} />
            Pause
          </button>
        ) : (
          <button type="button" className="btn btn-primary" onClick={() => timer.start()}>
            <Play size={20} />
            {timer.timeRemaining < timer.duration ? 'Resume' : 'Start'}
          </button>
        )}
        <button type="button" className="btn btn-ghost" onClick={timer.reset}>
          <RotateCcw size={20} />
        </button>
      </div>

      <div className="timer-presets">
        {PRESETS.map(seconds => (
          <button
            type="button"
            key={seconds}
            className="timer-preset"
            onClick={() => timer.setTime(seconds)}
          >
            {seconds >= 60 ? `${seconds / 60}m` : `${seconds}s`}
          </button>
        ))}
      </div>
    </div>
  );
};
