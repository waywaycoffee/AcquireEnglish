const API_BASE = import.meta.env.VITE_API_BASE ?? "";

export type User = {
  id: number;
  email: string;
  display_name: string | null;
};

export type Lesson = {
  id: string;
  title: string;
  index: number;
  durationSec?: number;
  videoUrl: string;
  subtitles: { en: string; zh?: string | null };
};

export type Course = {
  id: string;
  title: string;
  titleZh?: string | null;
  description?: string | null;
  coverUrl?: string | null;
  level: string;
  tags: string[];
  lessons: Lesson[];
};

export type TokenResponse = {
  access_token: string;
  token_type: string;
  user: User;
};

export type Preferences = {
  level: string;
  tags: string[];
  daily_quota: number;
  notify_daily_feed: boolean;
};

export type VocabItem = {
  id: number;
  word: string;
  context?: string | null;
  mastery: string;
  ease: number;
  interval_days: number;
  repetitions: number;
  due_at?: string | null;
};

async function request<T>(path: string, init: RequestInit = {}, token?: string | null): Promise<T> {
  const headers = new Headers(init.headers);
  headers.set("Content-Type", "application/json");
  if (token) headers.set("Authorization", `Bearer ${token}`);

  const res = await fetch(`${API_BASE}${path}`, { ...init, headers });
  if (!res.ok) {
    let detail = "Request failed";
    try {
      const body = await res.json();
      detail = body.detail ?? detail;
    } catch {
      /* ignore */
    }
    throw new Error(typeof detail === "string" ? detail : JSON.stringify(detail));
  }
  if (res.status === 204) return undefined as T;
  return res.json() as Promise<T>;
}

export const api = {
  register: (email: string, password: string, display_name?: string) =>
    request<TokenResponse>("/api/auth/register", {
      method: "POST",
      body: JSON.stringify({ email, password, display_name }),
    }),
  login: (email: string, password: string) =>
    request<TokenResponse>("/api/auth/login", {
      method: "POST",
      body: JSON.stringify({ email, password }),
    }),
  me: (token: string) => request<User>("/api/auth/me", {}, token),
  courses: (token?: string | null) => request<Course[]>("/api/courses", {}, token),
  course: (id: string, token?: string | null) =>
    request<Course>(`/api/courses/${id}`, {}, token),
  importLink: (token: string, url: string) =>
    request<Course>("/api/imports/link", { method: "POST", body: JSON.stringify({ url }) }, token),
  fetchText: async (path: string, token?: string | null) => {
    const headers = new Headers();
    if (token) headers.set("Authorization", `Bearer ${token}`);
    const res = await fetch(`${API_BASE}${path}`, { headers });
    if (!res.ok) throw new Error("Failed to load subtitle");
    return res.text();
  },
  upsertProgress: (
    payload: { course_id: string; lesson_id: string; position_sec: number; completed: boolean },
    token: string,
  ) => request("/api/progress", { method: "PUT", body: JSON.stringify(payload) }, token),
  listProgress: (token: string) =>
    request<
      Array<{ course_id: string; lesson_id: string; position_sec: number; completed: boolean; updated_at: string }>
    >("/api/progress", {}, token),
  getPreferences: (token: string) => request<Preferences>("/api/preferences", {}, token),
  putPreferences: (token: string, prefs: Preferences) =>
    request<Preferences>("/api/preferences", { method: "PUT", body: JSON.stringify(prefs) }, token),
  dailyFeed: (token: string) => request<Course[]>("/api/feed/daily", {}, token),
  listVocab: (token: string) => request<VocabItem[]>("/api/vocab", {}, token),
  upsertVocab: (
    token: string,
    payload: {
      word: string;
      context?: string;
      mastery?: string;
      ease?: number;
      interval_days?: number;
      repetitions?: number;
      due_at?: string | null;
    },
  ) => request<VocabItem>("/api/vocab", { method: "POST", body: JSON.stringify(payload) }, token),
};
