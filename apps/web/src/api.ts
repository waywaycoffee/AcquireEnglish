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
  courses: () => request<Course[]>("/api/courses"),
  course: (id: string) => request<Course>(`/api/courses/${id}`),
  upsertProgress: (
    payload: { course_id: string; lesson_id: string; position_sec: number; completed: boolean },
    token: string,
  ) =>
    request("/api/progress", { method: "PUT", body: JSON.stringify(payload) }, token),
};
