import tseslint from "typescript-eslint";
import reactHooks from "eslint-plugin-react-hooks";
import globals from "globals";

// Focused lint: parse TS/TSX and enforce the Rules of Hooks (the class of bug
// that TypeScript and `vite build` can't catch). Intentionally minimal — not a
// full style ruleset — so it stays signal, not noise.
export default tseslint.config(
  { ignores: ["dist/**"] },
  {
    files: ["src/**/*.{ts,tsx}"],
    languageOptions: {
      parser: tseslint.parser,
      parserOptions: { ecmaFeatures: { jsx: true }, sourceType: "module" },
      globals: { ...globals.browser },
    },
    plugins: { "react-hooks": reactHooks, "@typescript-eslint": tseslint.plugin },
    rules: {
      "react-hooks/rules-of-hooks": "error",
      "react-hooks/exhaustive-deps": "warn",
      // The codebase already opts out of `any` in a couple of spots via
      // disable directives; keep the rule on so those stay honest.
      "@typescript-eslint/no-explicit-any": "error",
    },
  },
);
