import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import { api, type User } from "./api";

type AuthState = {
  token: string | null;
  user: User | null;
  loading: boolean;
  applyToken: (token: string, user: User) => void;
  login: (email: string, password: string) => Promise<void>;
  sendEmailCode: (email: string) => Promise<{
    expiresIn: number;
    mock: boolean;
    debugCode?: string | null;
  }>;
  register: (
    email: string,
    password: string,
    code: string,
    displayName?: string,
  ) => Promise<void>;
  logout: () => void;
};

const AuthContext = createContext<AuthState | null>(null);
const TOKEN_KEY = "ae_token";

export function AuthProvider({ children }: { children: ReactNode }) {
  const [token, setToken] = useState<string | null>(() => localStorage.getItem(TOKEN_KEY));
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    async function boot() {
      if (!token) {
        setLoading(false);
        return;
      }
      try {
        const me = await api.me(token);
        if (!cancelled) setUser(me);
      } catch {
        localStorage.removeItem(TOKEN_KEY);
        if (!cancelled) {
          setToken(null);
          setUser(null);
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    }
    void boot();
    return () => {
      cancelled = true;
    };
  }, [token]);

  const value = useMemo<AuthState>(
    () => ({
      token,
      user,
      loading,
      applyToken(nextToken, nextUser) {
        localStorage.setItem(TOKEN_KEY, nextToken);
        setToken(nextToken);
        setUser(nextUser);
      },
      async login(email, password) {
        const res = await api.login(email, password);
        localStorage.setItem(TOKEN_KEY, res.access_token);
        setToken(res.access_token);
        setUser(res.user);
      },
      async sendEmailCode(email) {
        const res = await api.sendEmailCode(email);
        return {
          expiresIn: res.expires_in,
          mock: res.mock,
          debugCode: res.debug_code,
        };
      },
      async register(email, password, code, displayName) {
        const res = await api.register(email, password, code, displayName);
        localStorage.setItem(TOKEN_KEY, res.access_token);
        setToken(res.access_token);
        setUser(res.user);
      },
      logout() {
        localStorage.removeItem(TOKEN_KEY);
        setToken(null);
        setUser(null);
      },
    }),
    [token, user, loading],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used within AuthProvider");
  return ctx;
}
