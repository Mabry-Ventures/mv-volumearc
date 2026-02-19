'use client';

import { useState, useEffect, useCallback, useRef } from 'react';

interface UseTimerOptions {
  initialTime?: number; // in seconds
  onComplete?: () => void;
}

export const useTimer = (options: UseTimerOptions = {}) => {
  const { initialTime = 90, onComplete } = options;
  const [timeRemaining, setTimeRemaining] = useState(initialTime);
  const [isRunning, setIsRunning] = useState(false);
  const [duration, setDuration] = useState(initialTime);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const onCompleteRef = useRef<UseTimerOptions['onComplete']>(onComplete);

  const clearTimer = useCallback(() => {
    if (intervalRef.current) {
      clearInterval(intervalRef.current);
      intervalRef.current = null;
    }
  }, []);

  useEffect(() => {
    onCompleteRef.current = onComplete;
  }, [onComplete]);

  useEffect(() => {
    if (!isRunning) {
      clearTimer();
      return;
    }

    intervalRef.current = setInterval(() => {
      setTimeRemaining(prev => {
        if (prev <= 1) {
          clearTimer();
          setIsRunning(false);
          onCompleteRef.current?.();
          return 0;
        }
        return prev - 1;
      });
    }, 1000);

    return clearTimer;
  }, [isRunning, clearTimer]);

  useEffect(() => clearTimer, [clearTimer]);

  const start = useCallback((seconds?: number) => {
    clearTimer();

    if (seconds !== undefined) {
      const nextDuration = Math.max(0, seconds);
      setDuration(nextDuration);
      setTimeRemaining(nextDuration);
      setIsRunning(nextDuration > 0);
      return;
    }

    if (timeRemaining <= 0) {
      setTimeRemaining(duration);
    }

    setIsRunning(true);
  }, [clearTimer, timeRemaining, duration]);

  const pause = useCallback(() => {
    clearTimer();
    setIsRunning(false);
  }, [clearTimer]);

  const resume = useCallback(() => {
    if (timeRemaining > 0) {
      clearTimer();
      setIsRunning(true);
    }
  }, [timeRemaining, clearTimer]);

  const reset = useCallback(() => {
    clearTimer();
    setIsRunning(false);
    setTimeRemaining(duration);
  }, [duration, clearTimer]);

  const stop = useCallback(() => {
    clearTimer();
    setIsRunning(false);
    setTimeRemaining(0);
  }, [clearTimer]);

  const setTime = useCallback((seconds: number) => {
    const nextDuration = Math.max(0, seconds);
    clearTimer();
    setDuration(nextDuration);
    setTimeRemaining(nextDuration);
    setIsRunning(false);
  }, [clearTimer]);

  const formatTime = (seconds: number): string => {
    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  };

  return {
    timeRemaining,
    isRunning,
    duration,
    formattedTime: formatTime(timeRemaining),
    progress: duration > 0 ? ((duration - timeRemaining) / duration) * 100 : 0,
    start,
    pause,
    resume,
    reset,
    stop,
    setTime,
  };
};
