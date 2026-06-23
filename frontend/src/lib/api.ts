export interface Profile {
  id: string;
  name: string;
  dateOfBirth: string | null;
}

export interface Analyte {
  id: string;
  name: string;
  defaultUnit: string | null;
  category: string | null;
  loinc: string | null;
  specimen: string | null;
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
  flag: string | null;
  observedDate: string | null;
}

export interface DraftResult {
  testName: string;
  value: string;
  valueNumeric: number | null;
  unit: string | null;
  referenceRange: string | null;
  referenceLow: number | null;
  referenceHigh: number | null;
  flag: string | null;
  specimen: string | null;
  suggestedAnalyteId: string | null;
  suggestedAnalyteName: string | null;
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
  flag: string | null;
  observedDate: string | null;
  learnAlias: boolean;
}

export interface ConfirmInput {
  sourceLab: string | null;
  collectedDate: string | null;
  reportedDate: string | null;
  results: ConfirmResultInput[];
}

async function req<T>(url: string, init?: RequestInit): Promise<T> {
  const res = await fetch(url, init);
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

export const api = {
  listProfiles: () => req<Profile[]>("/api/profiles"),
  createProfile: (name: string, dateOfBirth: string | null) =>
    req<Profile>("/api/profiles", json({ name, dateOfBirth })),
  deleteProfile: (id: string) =>
    req<void>(`/api/profiles/${id}`, { method: "DELETE" }),

  listAnalytes: () => req<Analyte[]>("/api/analytes"),
  listProfileAnalytes: (profileId: string) =>
    req<Analyte[]>(`/api/profiles/${profileId}/analytes`),

  latestResults: (profileId: string) =>
    req<Result[]>(`/api/profiles/${profileId}/results`),
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

  pdfUrl: (reportId: string) => `/api/reports/${reportId}/pdf`,
};
