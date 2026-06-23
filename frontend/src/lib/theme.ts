import { useEffect, useState } from "react";

export interface ThemeColors {
  border: string;
  muted: string;
  panel: string;
  text: string;
  accent: string;
  good: string;
}

function read(): ThemeColors {
  const s = getComputedStyle(document.documentElement);
  const v = (n: string) => `rgb(${s.getPropertyValue(`--c-${n}`).trim()})`;
  return {
    border: v("border"),
    muted: v("muted"),
    panel: v("panel"),
    text: v("text"),
    accent: v("accent"),
    good: v("good"),
  };
}

// useThemeColors resolves the current CSS-variable palette into concrete color
// strings for libraries (like Recharts) that can't consume CSS variables, and
// re-reads when the OS color scheme changes.
export function useThemeColors(): ThemeColors {
  const [colors, setColors] = useState<ThemeColors>(read);

  useEffect(() => {
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    const update = () => setColors(read());
    mq.addEventListener("change", update);
    return () => mq.removeEventListener("change", update);
  }, []);

  return colors;
}
