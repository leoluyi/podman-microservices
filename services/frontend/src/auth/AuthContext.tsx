import React, { createContext, useState, useEffect, useCallback } from 'react';
import axios from 'axios';
import client from '../api/client';

interface User {
  username: string;
  roles: string[];
  permissions: string[];
}

interface AuthContextType {
  user: User | null;
  loading: boolean;
  login: (username: string, password: string) => Promise<void>;
  register: (username: string, password: string, email: string) => Promise<void>;
  logout: () => Promise<void>;
  hasRole: (role: string) => boolean;
  hasPermission: (permission: string) => boolean;
}

export const AuthContext = createContext<AuthContextType | null>(null);

function parseJwt(token: string): { sub: string; roles: string[]; permissions: string[] } | null {
  try {
    const base64Url = token.split('.')[1];
    const base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/');
    const payload = JSON.parse(atob(base64));
    return { sub: payload.sub, roles: payload.roles || [], permissions: payload.permissions || [] };
  } catch {
    return null;
  }
}

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);

  const setUserFromToken = useCallback((token: string) => {
    const parsed = parseJwt(token);
    if (parsed) {
      localStorage.setItem('access_token', token);
      setUser({ username: parsed.sub, roles: parsed.roles, permissions: parsed.permissions });
    }
  }, []);

  useEffect(() => {
    const token = localStorage.getItem('access_token');
    if (token) {
      const parsed = parseJwt(token);
      if (parsed) {
        setUser({ username: parsed.sub, roles: parsed.roles, permissions: parsed.permissions });
      }
    }
    // Try silent refresh
    axios.post('/api/auth/refresh', null, { withCredentials: true })
      .then(({ data }) => setUserFromToken(data.accessToken))
      .catch(() => {})
      .finally(() => setLoading(false));
  }, [setUserFromToken]);

  const login = async (username: string, password: string) => {
    const { data } = await client.post('/auth/login', { username, password }, { withCredentials: true });
    setUserFromToken(data.accessToken);
  };

  const register = async (username: string, password: string, email: string) => {
    const { data } = await client.post('/auth/register', { username, password, email }, { withCredentials: true });
    setUserFromToken(data.accessToken);
  };

  const logout = async () => {
    await client.post('/auth/logout', null, { withCredentials: true }).catch(() => {});
    localStorage.removeItem('access_token');
    setUser(null);
  };

  const hasRole = (role: string) => user?.roles.includes(role) ?? false;
  const hasPermission = (permission: string) => user?.permissions.includes(permission) ?? false;

  return (
    <AuthContext.Provider value={{ user, loading, login, register, logout, hasRole, hasPermission }}>
      {children}
    </AuthContext.Provider>
  );
}
