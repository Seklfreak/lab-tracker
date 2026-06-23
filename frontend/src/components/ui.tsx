import { clsx } from "clsx";
import type {
  ButtonHTMLAttributes,
  InputHTMLAttributes,
  SelectHTMLAttributes,
  ReactNode,
} from "react";

export function Button({
  className,
  variant = "primary",
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: "primary" | "ghost" | "danger";
}) {
  return (
    <button
      className={clsx(
        "inline-flex items-center justify-center gap-2 rounded-md px-3 py-2 text-sm font-medium transition disabled:opacity-50 disabled:cursor-not-allowed",
        variant === "primary" && "bg-accent text-white hover:bg-accent/90",
        variant === "ghost" &&
          "border border-border bg-panel2 text-text hover:bg-border/40",
        variant === "danger" && "bg-bad/90 text-white hover:bg-bad",
        className,
      )}
      {...props}
    />
  );
}

export function Input({ className, ...props }: InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      className={clsx(
        "w-full rounded-md border border-border bg-panel2 px-2.5 py-1.5 text-sm outline-none focus:border-accent",
        className,
      )}
      {...props}
    />
  );
}

export function Select({
  className,
  children,
  ...props
}: SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select
      className={clsx(
        "w-full rounded-md border border-border bg-panel2 px-2.5 py-1.5 text-sm outline-none focus:border-accent",
        className,
      )}
      {...props}
    >
      {children}
    </select>
  );
}

export function Card({
  className,
  children,
}: {
  className?: string;
  children: ReactNode;
}) {
  return (
    <div
      className={clsx(
        "rounded-xl border border-border bg-panel p-4 shadow-sm",
        className,
      )}
    >
      {children}
    </div>
  );
}

export function Badge({
  children,
  tone = "muted",
}: {
  children: ReactNode;
  tone?: "good" | "warn" | "bad" | "muted";
}) {
  return (
    <span
      className={clsx(
        "rounded-full px-2 py-0.5 text-xs font-semibold",
        tone === "good" && "bg-good/15 text-good",
        tone === "warn" && "bg-warn/15 text-warn",
        tone === "bad" && "bg-bad/15 text-bad",
        tone === "muted" && "bg-border/40 text-muted",
      )}
    >
      {children}
    </span>
  );
}

export function Spinner({ label }: { label?: string }) {
  return (
    <div className="flex items-center gap-3 text-muted">
      <div className="h-5 w-5 animate-spin rounded-full border-2 border-border border-t-accent" />
      {label && <span className="text-sm">{label}</span>}
    </div>
  );
}
