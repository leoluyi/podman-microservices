import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../auth/useAuth';

type Mode = 'login' | 'register';

export function LoginPage() {
  const { login, register, user } = useAuth();
  const navigate = useNavigate();

  const [mode, setMode] = useState<Mode>('login');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [email, setEmail] = useState('');
  const [error, setError] = useState('');
  const [submitting, setSubmitting] = useState(false);

  // Redirect if already logged in
  if (user) {
    navigate('/', { replace: true });
    return null;
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setSubmitting(true);

    try {
      if (mode === 'login') {
        await login(username, password);
      } else {
        await register(username, password, email);
      }
      navigate('/', { replace: true });
    } catch (err: unknown) {
      if (err && typeof err === 'object' && 'response' in err) {
        const axiosErr = err as { response?: { data?: { message?: string } } };
        setError(axiosErr.response?.data?.message || 'Authentication failed');
      } else {
        setError('Network error. Please try again.');
      }
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div style={{ maxWidth: 400, margin: '80px auto', padding: 24 }}>
      <h1>{mode === 'login' ? 'Sign In' : 'Create Account'}</h1>

      {error && (
        <div style={{ color: '#d32f2f', background: '#fdecea', padding: '8px 12px', borderRadius: 4, marginBottom: 16 }}>
          {error}
        </div>
      )}

      <form onSubmit={handleSubmit}>
        <div style={{ marginBottom: 12 }}>
          <label htmlFor="username" style={{ display: 'block', marginBottom: 4, fontWeight: 500 }}>
            Username
          </label>
          <input
            id="username"
            type="text"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            required
            autoComplete="username"
            style={{ width: '100%', padding: 8, boxSizing: 'border-box' }}
          />
        </div>

        {mode === 'register' && (
          <div style={{ marginBottom: 12 }}>
            <label htmlFor="email" style={{ display: 'block', marginBottom: 4, fontWeight: 500 }}>
              Email
            </label>
            <input
              id="email"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              autoComplete="email"
              style={{ width: '100%', padding: 8, boxSizing: 'border-box' }}
            />
          </div>
        )}

        <div style={{ marginBottom: 16 }}>
          <label htmlFor="password" style={{ display: 'block', marginBottom: 4, fontWeight: 500 }}>
            Password
          </label>
          <input
            id="password"
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
            autoComplete={mode === 'login' ? 'current-password' : 'new-password'}
            style={{ width: '100%', padding: 8, boxSizing: 'border-box' }}
          />
        </div>

        <button
          type="submit"
          disabled={submitting}
          style={{
            width: '100%',
            padding: '10px 0',
            background: '#1976d2',
            color: '#fff',
            border: 'none',
            borderRadius: 4,
            cursor: submitting ? 'not-allowed' : 'pointer',
            fontSize: 16,
          }}
        >
          {submitting ? 'Please wait...' : mode === 'login' ? 'Sign In' : 'Register'}
        </button>
      </form>

      <div style={{ marginTop: 16, textAlign: 'center' }}>
        {mode === 'login' ? (
          <span>
            No account?{' '}
            <button
              type="button"
              onClick={() => { setMode('register'); setError(''); }}
              style={{ background: 'none', border: 'none', color: '#1976d2', cursor: 'pointer', textDecoration: 'underline' }}
            >
              Create one
            </button>
          </span>
        ) : (
          <span>
            Already have an account?{' '}
            <button
              type="button"
              onClick={() => { setMode('login'); setError(''); }}
              style={{ background: 'none', border: 'none', color: '#1976d2', cursor: 'pointer', textDecoration: 'underline' }}
            >
              Sign in
            </button>
          </span>
        )}
      </div>
    </div>
  );
}
