import { Navigate } from 'react-router-dom';
import { useAuth } from './useAuth';

interface Props {
  children: React.ReactNode;
  requiredRole?: string;
  requiredPermission?: string;
}

export function ProtectedRoute({ children, requiredRole, requiredPermission }: Props) {
  const { user, loading } = useAuth();

  if (loading) return <div>Loading...</div>;
  if (!user) return <Navigate to="/login" replace />;
  if (requiredRole && !user.roles.includes(requiredRole)) return <div>Access denied</div>;
  if (requiredPermission && !user.permissions.includes(requiredPermission)) return <div>Access denied</div>;

  return <>{children}</>;
}
