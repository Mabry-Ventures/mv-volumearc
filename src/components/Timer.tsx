'use client';

import { useEffect } from 'react';
import { Play, Pause, RotateCcw } from 'lucide-react';
import { useTimer } from '@/hooks/useTimer';
import { SegmentedControl } from '@/components/ui/SegmentedControl';

const PRESETS = [30, 60, 90, 120, 180] as const;

interface TimerProps {
  autoStartSeconds?: number | null;
}

export const Timer = ({ autoStartSeconds = null }: TimerProps) => {
  const timer = useTimer({
    initialTime: 90,
    onComplete: () => {
      if (typeof window !== 'undefined' && 'vibrate' in navigator) {
        navigator.vibrate([200, 100, 200]);
      }
    },
  });

  useEffect(() => {
    if (typeof autoStartSeconds === 'number' && autoStartSeconds > 0) {
      timer.start(autoStartSeconds);
    }
  }, [autoStartSeconds, timer.start]);

  return (
    <div className="timer">
      <div className="timer-display">{timer.formattedTime}</div>

      <div className="timer-progress">
        <div className="timer-progress-bar" style={{ width: `${timer.progress}%` }} />
      </div>

      <div className="flex justify-center gap-2 mt-3">
        {timer.isRunning ? (
          <button type="button" className="btn btn-secondary" onClick={timer.pause}>
            <Pause size={18} />
            Pause
          </button>
        ) : (
          <button type="button" className="btn btn-primary" onClick={() => timer.start()}>
            <Play size={18} />
            {timer.timeRemaining < timer.duration ? 'Resume' : 'Start'}
          </button>
        )}
        <button type="button" className="btn btn-ghost" onClick={timer.reset} aria-label="Reset timer">
          <RotateCcw size={18} />
        </button>
      </div>

      <div className="mt-3">
        <SegmentedControl
          ariaLabel="Rest timer presets"
          value={`${timer.duration}` as `${number}`}
          options={PRESETS.map(seconds => ({
            value: `${seconds}` as `${number}`,
            label: seconds >= 60 ? `${seconds / 60}m` : `${seconds}s`,
          }))}
          onChange={value => timer.setTime(Number(value))}
        />
      </div>
    </div>
  );
};
