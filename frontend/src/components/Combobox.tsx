import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { clsx } from "clsx";
import { Check, ChevronsUpDown } from "lucide-react";

export interface ComboOption {
  value: string;
  label: string;
  hint?: string | null;
}

// Combobox is a searchable, keyboard-navigable select. The dropdown is rendered
// in a portal with fixed positioning so it isn't clipped by scrolling/overflow
// containers (e.g. the review table).
export function Combobox({
  value,
  options,
  onChange,
  className,
  placeholder = "Select…",
}: {
  value: string;
  options: ComboOption[];
  onChange: (value: string) => void;
  className?: string;
  placeholder?: string;
}) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [hi, setHi] = useState(0);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const panelRef = useRef<HTMLDivElement>(null);
  const [rect, setRect] = useState<{ top: number; left: number; width: number } | null>(null);

  const selected = options.find((o) => o.value === value);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return options;
    return options.filter(
      (o) =>
        o.label.toLowerCase().includes(q) ||
        (o.hint ? o.hint.toLowerCase().includes(q) : false),
    );
  }, [options, query]);

  useLayoutEffect(() => {
    if (open && triggerRef.current) {
      const r = triggerRef.current.getBoundingClientRect();
      setRect({ top: r.bottom + 4, left: r.left, width: r.width });
      setHi(0);
    }
  }, [open]);

  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => {
      const t = e.target as Node;
      if (triggerRef.current?.contains(t) || panelRef.current?.contains(t)) return;
      setOpen(false);
    };
    // Any scroll (incl. the table's horizontal scroll) would misplace the
    // fixed panel — close instead of trying to track it.
    const onScroll = () => setOpen(false);
    document.addEventListener("mousedown", onDown);
    window.addEventListener("scroll", onScroll, true);
    window.addEventListener("resize", onScroll);
    return () => {
      document.removeEventListener("mousedown", onDown);
      window.removeEventListener("scroll", onScroll, true);
      window.removeEventListener("resize", onScroll);
    };
  }, [open]);

  const choose = (v: string) => {
    onChange(v);
    setOpen(false);
    setQuery("");
  };

  return (
    <>
      <button
        type="button"
        ref={triggerRef}
        onClick={() => setOpen((o) => !o)}
        className={clsx(
          "flex w-full items-center justify-between gap-2 rounded-md border border-border bg-panel2 px-2.5 py-1.5 text-left text-sm outline-none focus:border-accent",
          className,
        )}
      >
        <span className="truncate">{selected ? selected.label : placeholder}</span>
        <ChevronsUpDown size={14} className="shrink-0 text-muted" />
      </button>

      {open &&
        rect &&
        createPortal(
          <div
            ref={panelRef}
            style={{ position: "fixed", top: rect.top, left: rect.left, width: Math.max(rect.width, 260) }}
            className="z-50 overflow-hidden rounded-md border border-border bg-panel shadow-lg"
          >
            <div className="p-1.5">
              <input
                autoFocus
                value={query}
                onChange={(e) => {
                  setQuery(e.target.value);
                  setHi(0);
                }}
                onKeyDown={(e) => {
                  if (e.key === "ArrowDown") {
                    e.preventDefault();
                    setHi((h) => Math.min(h + 1, filtered.length - 1));
                  } else if (e.key === "ArrowUp") {
                    e.preventDefault();
                    setHi((h) => Math.max(h - 1, 0));
                  } else if (e.key === "Enter") {
                    e.preventDefault();
                    if (filtered[hi]) choose(filtered[hi].value);
                  } else if (e.key === "Escape") {
                    setOpen(false);
                  }
                }}
                placeholder="Search…"
                className="w-full rounded border border-border bg-panel2 px-2 py-1 text-sm outline-none focus:border-accent"
              />
            </div>
            <div className="max-h-64 overflow-y-auto pb-1">
              {filtered.length === 0 && (
                <div className="px-3 py-2 text-sm text-muted">No matches</div>
              )}
              {filtered.map((o, i) => (
                <button
                  type="button"
                  key={o.value}
                  onMouseEnter={() => setHi(i)}
                  onClick={() => choose(o.value)}
                  className={clsx(
                    "flex w-full items-center justify-between gap-2 px-3 py-1.5 text-left text-sm",
                    i === hi && "bg-accent/15",
                  )}
                >
                  <span className="flex items-center gap-1.5 truncate">
                    {o.value === value && <Check size={13} className="shrink-0 text-accent" />}
                    <span className={clsx("truncate", o.value === value && "text-accent")}>
                      {o.label}
                    </span>
                  </span>
                  {o.hint && <span className="shrink-0 text-xs text-muted">{o.hint}</span>}
                </button>
              ))}
            </div>
          </div>,
          document.body,
        )}
    </>
  );
}
