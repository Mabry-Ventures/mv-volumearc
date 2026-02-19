import { renderHook, act } from '@testing-library/react';
import { useTimer } from '@/hooks/useTimer';

describe('useTimer', () => {
  beforeEach(() => {
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('counts down and triggers completion', () => {
    const onComplete = jest.fn();
    const { result } = renderHook(() => useTimer({ initialTime: 3, onComplete }));

    act(() => {
      result.current.start();
    });

    act(() => {
      jest.advanceTimersByTime(1000);
    });
    expect(result.current.timeRemaining).toBe(2);

    act(() => {
      jest.advanceTimersByTime(2000);
    });

    expect(result.current.timeRemaining).toBe(0);
    expect(onComplete).toHaveBeenCalled();
  });

  it('pauses, resumes, and resets', () => {
    const { result } = renderHook(() => useTimer({ initialTime: 5 }));

    act(() => {
      result.current.start();
    });

    act(() => {
      jest.advanceTimersByTime(2000);
    });
    expect(result.current.timeRemaining).toBe(3);

    act(() => {
      result.current.pause();
    });

    act(() => {
      jest.advanceTimersByTime(2000);
    });
    expect(result.current.timeRemaining).toBe(3);

    act(() => {
      result.current.resume();
    });

    act(() => {
      jest.advanceTimersByTime(1000);
    });
    expect(result.current.timeRemaining).toBe(2);

    act(() => {
      result.current.reset();
    });
    expect(result.current.timeRemaining).toBe(5);
  });
});
