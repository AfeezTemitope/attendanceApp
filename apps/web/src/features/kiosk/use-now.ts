import { useEffect, useState } from 'react';

/** Current time, re-rendering at the start of every second. */
export function useNow(): Date {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    let timer: ReturnType<typeof setTimeout>;
    const tick = () => {
      setNow(new Date());
      timer = setTimeout(tick, 1_000 - (Date.now() % 1_000));
    };
    timer = setTimeout(tick, 1_000 - (Date.now() % 1_000));
    return () => clearTimeout(timer);
  }, []);
  return now;
}
