import { getAccessToken, handleUnauthorized } from "./auth";

export interface Profile {
  id: string;
  name: string;
  dateOfBirth: string | null;
  isOwner: boolean;
}

export interface Member {
  userId: string;
  email: string | null;
  name: string | null;
  role: string;
  isOwner: boolean;
}

export interface Me {
  userId: string;
  email: string | null;
  name: string | null;
  isAdmin: boolean;
}

export interface AdminUser {
  id: string;
  email: string | null;
  name: string | null;
  oidcSub: string;
  createdAt: string;
  lastSeenAt: string;
  ownedCount: number;
  sharedCount: number;
}

export interface Analysis {
  content: string;
  generatedAt: string;
  basedOnCount: number;
  currentCount: number;
  stale: boolean;
}

export interface PanelSummary {
  content: string;
  generatedAt: string;
  basedOnCount: number;
}

export interface Analyte {
  id: string;
  name: string;
  defaultUnit: string | null;
  category: string | null;
  loinc: string | null;
  specimens: string[] | null;
}

export interface Result {
  id: string;
  reportId: string;
  analyteId: string;
  analyteName: string;
  category: string | null;
  rawTestName: string;
  valueText: string | null;
  valueNumeric: number | null;
  unit: string | null;
  referenceLow: number | null;
  referenceHigh: number | null;
  referenceText: string | null;
  note: string | null;
  observedDate: string | null;
  sourceLab: string | null;
  count?: number; // # of readings for this analyte (only on the dashboard "latest" list)
  isFavorite?: boolean;
}

export interface DraftResult {
  testName: string;
  value: string;
  valueNumeric: number | null;
  unit: string | null;
  referenceRange: string | null;
  referenceLow: number | null;
  referenceHigh: number | null;
  specimen: string | null;
  note: string | null;
  suggestedAnalyteId: string | null;
  suggestedAnalyteName: string | null;
  suggestedByAi: boolean;
}

export interface Draft {
  labName: string | null;
  collectedDate: string | null;
  reportedDate: string | null;
  results: DraftResult[];
}

export type ReportStatus = "parsing" | "parsed" | "saved" | "error";

export interface Report {
  id: string;
  profileId: string;
  originalFilename: string | null;
  sourceLab: string | null;
  status: ReportStatus;
  parseError: string | null;
  collectedDate: string | null;
  reportedDate: string | null;
  draft: Draft | null;
}

export interface ConfirmResultInput {
  analyteId: string | null;
  newAnalyteName: string | null;
  newAnalyteUnit: string | null;
  rawTestName: string;
  valueText: string | null;
  valueNumeric: number | null;
  unit: string | null;
  referenceLow: number | null;
  referenceHigh: number | null;
  referenceText: string | null;
  note: string | null;
  observedDate: string | null;
  learnAlias: boolean;
}

export interface UpdateResultInput {
  analyteId: string;
  valueText: string | null;
  valueNumeric: number | null;
  unit: string | null;
  referenceLow: number | null;
  referenceHigh: number | null;
  referenceText: string | null;
  note: string | null;
  observedDate: string | null;
}

export interface ConfirmInput {
  sourceLab: string | null;
  collectedDate: string | null;
  reportedDate: string | null;
  results: ConfirmResultInput[];
}

async function req<T>(url: string, init?: RequestInit): Promise<T> {
  const token = getAccessToken();
  const headers: HeadersInit = {
    ...(init?.headers ?? {}),
    ...(token ? { Authorization: `Bearer ${token}` } : {}),
  };
  const res = await fetch(url, { ...init, headers });
  if (res.status === 401) {
    handleUnauthorized(); // expired/missing token → re-login
    throw new Error("unauthorized");
  }
  if (!res.ok) {
    let msg = res.statusText;
    try {
      const body = await res.json();
      if (body?.error) msg = body.error;
    } catch {
      /* ignore */
    }
    throw new Error(msg);
  }
  if (res.status === 204) return undefined as T;
  return res.json() as Promise<T>;
}

const json = (body: unknown): RequestInit => ({
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify(body),
});

// Public health endpoint (no auth) — also carries the api build version, so the
// footer can read it without an authed request (a 401 would trigger re-login).
export const health = (): Promise<{ status: string; version?: string }> =>
  fetch("/health").then((r) => r.json());

export const api = {
  me: () => req<Me>("/api/me"),
  adminUsers: () => req<AdminUser[]>("/api/admin/users"),

  listProfiles: () => req<Profile[]>("/api/profiles"),
  createProfile: (name: string, dateOfBirth: string | null) =>
    req<Profile>("/api/profiles", json({ name, dateOfBirth })),
  deleteProfile: (id: string) =>
    req<void>(`/api/profiles/${id}`, { method: "DELETE" }),

  listMembers: (profileId: string) =>
    req<Member[]>(`/api/profiles/${profileId}/members`),
  addMember: (profileId: string, email: string) =>
    req<Member>(`/api/profiles/${profileId}/members`, json({ email })),
  removeMember: (profileId: string, userId: string) =>
    req<void>(`/api/profiles/${profileId}/members/${userId}`, { method: "DELETE" }),

  listAnalytes: () => req<Analyte[]>("/api/analytes"),
  listProfileAnalytes: (profileId: string) =>
    req<Analyte[]>(`/api/profiles/${profileId}/analytes`),

  latestResults: (profileId: string) =>
    req<Result[]>(`/api/profiles/${profileId}/results`),
  allResults: (profileId: string) =>
    req<Result[]>(`/api/profiles/${profileId}/results?all=true`),
  analyteTrend: (profileId: string, analyteId: string) =>
    req<Result[]>(`/api/profiles/${profileId}/results?analyte_id=${analyteId}`),

  uploadReport: async (profileId: string, file: File) => {
    const fd = new FormData();
    fd.append("file", file);
    return req<Report>(`/api/profiles/${profileId}/reports`, {
      method: "POST",
      body: fd,
    });
  },
  getReport: (id: string) => req<Report>(`/api/reports/${id}`),
  listReports: (profileId: string) =>
    req<Report[]>(`/api/profiles/${profileId}/reports`),
  confirmReport: (id: string, input: ConfirmInput) =>
    req<Report>(`/api/reports/${id}/confirm`, json(input)),
  reparseReport: (id: string) =>
    req<Report>(`/api/reports/${id}/reparse`, { method: "POST" }),
  deleteReport: (id: string) =>
    req<void>(`/api/reports/${id}`, { method: "DELETE" }),

  updateResult: (id: string, input: UpdateResultInput) =>
    req<void>(`/api/results/${id}`, json(input)),
  deleteResult: (id: string) => req<void>(`/api/results/${id}`, { method: "DELETE" }),

  getAnalysis: (profileId: string, analyteId: string) =>
    req<{ analysis: Analysis | null }>(`/api/profiles/${profileId}/analytes/${analyteId}/analysis`),
  generateAnalysis: (profileId: string, analyteId: string) =>
    req<{ analysis: Analysis }>(`/api/profiles/${profileId}/analytes/${analyteId}/analysis`, {
      method: "POST",
    }),

  generatePanelSummary: (profileId: string) =>
    req<PanelSummary>(`/api/profiles/${profileId}/summary`, { method: "POST" }),

  addFavorite: (profileId: string, analyteId: string) =>
    req<void>(`/api/profiles/${profileId}/favorites`, json({ analyteId })),
  removeFavorite: (profileId: string, analyteId: string) =>
    req<void>(`/api/profiles/${profileId}/favorites/${analyteId}`, { method: "DELETE" }),

  pdfUrl: (reportId: string) => `/api/reports/${reportId}/pdf`,

  // Opens the report PDF in a new tab, attaching the auth token (a plain
  // <a href> can't send the Bearer header). Opens the tab synchronously to
  // dodge popup blockers, then points it at the fetched blob.
  openPdf: async (reportId: string) => {
    const win = window.open("about:blank", "_blank");
    try {
      const token = getAccessToken();
      const res = await fetch(`/api/reports/${reportId}/pdf`, {
        headers: token ? { Authorization: `Bearer ${token}` } : {},
      });
      if (!res.ok) {
        if (res.status === 401) handleUnauthorized();
        throw new Error("failed to open PDF");
      }
      const url = URL.createObjectURL(await res.blob());
      if (win) win.location.href = url;
      else window.open(url, "_blank");
      setTimeout(() => URL.revokeObjectURL(url), 60_000);
    } catch (e) {
      win?.close();
      throw e;
    }
  },
};
