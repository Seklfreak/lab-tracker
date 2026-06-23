/** @type {import('tailwindcss').Config} */
export default {
  darkMode: "class",
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        bg: "#0b0f17",
        panel: "#121826",
        panel2: "#1a2234",
        border: "#26304a",
        muted: "#8b97b3",
        text: "#e6ebf5",
        accent: "#5b9cff",
        good: "#3fb27f",
        warn: "#e0a458",
        bad: "#e06c75",
      },
    },
  },
  plugins: [],
};
