/** @type {import('tailwindcss').Config} */
const c = (name) => `rgb(var(--c-${name}) / <alpha-value>)`;

export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        bg: c("bg"),
        panel: c("panel"),
        panel2: c("panel2"),
        border: c("border"),
        muted: c("muted"),
        text: c("text"),
        accent: c("accent"),
        good: c("good"),
        warn: c("warn"),
        bad: c("bad"),
      },
    },
  },
  plugins: [],
};
