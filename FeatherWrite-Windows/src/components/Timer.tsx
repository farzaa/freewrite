import { useState, useEffect, useCallback, forwardRef, useImperativeHandle } from 'react';
import '../styles/Timer.css';

interface TimerProps {
  initialMinutes?: number;
  onTimerEnd?: () => void;
}

export interface TimerHandle {
  resetTimer: () => void;
}

const Timer = forwardRef<TimerHandle, TimerProps>(({ initialMinutes = 15, onTimerEnd }, ref) => {
  const [timeLeft, setTimeLeft] = useState(initialMinutes * 60);
  const [isRunning, setIsRunning] = useState(false);
  const [opacity, setOpacity] = useState(1);

  const toggleTimer = useCallback(() => {
    setIsRunning(prevState => !prevState);
  }, []);

  const resetTimer = useCallback(() => {
    setTimeLeft(initialMinutes * 60);
    setIsRunning(false);
    setOpacity(1);
  }, [initialMinutes]);

  useImperativeHandle(ref, () => ({
    resetTimer
  }));

  const adjustTime = useCallback((event: WheelEvent) => {
    if (!isRunning) {
      const delta = event.deltaY > 0 ? -1 : 1;
      setTimeLeft(prev => Math.max(1 * 60, Math.min(60 * 60, prev + delta * 60)));
      event.preventDefault();
    }
  }, [isRunning]);

  useEffect(() => {
    let interval: number;
    
    if (isRunning && timeLeft > 0) {
      interval = window.setInterval(() => {
        setTimeLeft(prev => {
          const newTime = prev - 1;
          setOpacity(newTime / (initialMinutes * 60));
          return newTime;
        });
      }, 1000);
    } else if (timeLeft === 0) {
      setIsRunning(false);
      window.electron?.showNotification(
        'Timer Complete',
        'Your writing session has ended. Time to review your work!'
      );
      onTimerEnd?.();
    }

    return () => clearInterval(interval);
  }, [isRunning, timeLeft, initialMinutes, onTimerEnd]);

  useEffect(() => {
    const timerElement = document.querySelector('.timer');
    if (timerElement) {
      const wheelHandler = (e: WheelEvent) => adjustTime(e);
      timerElement.addEventListener('wheel', wheelHandler as EventListener);
      return () => timerElement.removeEventListener('wheel', wheelHandler as EventListener);
    }
  }, [adjustTime]);

  const minutes = Math.floor(timeLeft / 60);
  const seconds = timeLeft % 60;

  return (
    <div 
      className={`timer ${isRunning ? 'running' : ''}`}
      style={{ opacity }}
      onClick={toggleTimer}
      title={!isRunning ? "Click to start timer" : "Click to pause timer"}
    >
      {String(minutes).padStart(2, '0')}:{String(seconds).padStart(2, '0')}
    </div>
  );
});

Timer.displayName = 'Timer';

export default Timer;