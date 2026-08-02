import type { Result } from "./api";

export interface DuplicateGroup {
  analytes: { id: string; name: string }[];
}

/** Canonical key for an unordered analyte pair (order-independent). */
export function pairKey(a: string, b: string): string {
  return a < b ? `${a}|${b}` : `${b}|${a}`;
}

// Qualifier words a lab tacks onto the same marker; ignored when comparing names
// so "Glucose" and "Glucose, Fasting" read as the same core marker.
const QUALIFIERS = new Set([
  "fasting", "nonfasting", "random", "serum", "plasma", "blood", "whole",
  "total", "calc", "calculated", "calculation", "est", "estimated", "measured",
  "level", "levels", "test", "panel", "auto",
]);

function tokens(name: string): string[] {
  return name
    .toLowerCase()
    .replace(/\(.*?\)/g, " ") // drop parentheticals like "(calc)"
    .split(/[^a-z0-9]+/)
    .filter((t) => t.length > 0 && !QUALIFIERS.has(t));
}

/**
 * Heuristic "these might be the same marker" grouping over a profile's analytes.
 * Conservative to avoid noise: two analytes group when their significant-token
 * sets are equal, or one set is a subset of the other sharing the same lead token
 * and category. Catches "Glucose" / "Glucose, Fasting" and "Vitamin D" /
 * "Vitamin D, 25-Hydroxy" without flagging "Vitamin B" vs "Vitamin B12". It only
 * suggests — the admin confirms each merge — so a stray pairing is harmless.
 *
 * `ignored` is a set of `pairKey` values the admin marked "not duplicates"; those
 * edges are skipped, so a dismissed suggestion stays gone even as data changes.
 */
export function findDuplicateGroups(results: Result[], ignored?: Set<string>): DuplicateGroup[] {
  const items = new Map<string, { id: string; name: string; category: string | null; toks: string[]; set: Set<string> }>();
  for (const r of results) {
    if (items.has(r.analyteId)) continue;
    const toks = tokens(r.analyteName);
    if (toks.length === 0) continue;
    items.set(r.analyteId, { id: r.analyteId, name: r.analyteName, category: r.category ?? null, toks, set: new Set(toks) });
  }
  const arr = [...items.values()];

  // Union-find over related analytes.
  const parent = new Map(arr.map((a) => [a.id, a.id]));
  const find = (x: string): string => {
    let p = parent.get(x)!;
    while (p !== parent.get(p)!) p = parent.get(p)!;
    parent.set(x, p);
    return p;
  };
  const union = (a: string, b: string) => parent.set(find(a), find(b));

  const eqSet = (a: Set<string>, b: Set<string>) => a.size === b.size && [...a].every((t) => b.has(t));
  const subset = (a: Set<string>, b: Set<string>) => a.size < b.size && [...a].every((t) => b.has(t));

  for (let i = 0; i < arr.length; i++) {
    for (let j = i + 1; j < arr.length; j++) {
      const a = arr[i];
      const b = arr[j];
      if (ignored?.has(pairKey(a.id, b.id))) continue;
      const related =
        eqSet(a.set, b.set) ||
        (a.category === b.category && a.toks[0] === b.toks[0] && (subset(a.set, b.set) || subset(b.set, a.set)));
      if (related) union(a.id, b.id);
    }
  }

  const groups = new Map<string, { id: string; name: string }[]>();
  for (const a of arr) {
    const root = find(a.id);
    const g = groups.get(root) ?? [];
    g.push({ id: a.id, name: a.name });
    groups.set(root, g);
  }
  return [...groups.values()]
    .filter((g) => g.length >= 2)
    .map((analytes) => ({ analytes: analytes.sort((x, y) => x.name.localeCompare(y.name)) }));
}
