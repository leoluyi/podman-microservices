INSERT INTO roles (name, description) VALUES
    ('ROLE_ADMIN',   'Full system access'),
    ('ROLE_MANAGER', 'Read/write access to business resources'),
    ('ROLE_USER',    'Read-only access to own resources');

INSERT INTO permissions (name, resource, action, description) VALUES
    ('users:read',    'users',    'read',   'View user profiles'),
    ('users:write',   'users',    'write',  'Create/update users'),
    ('users:delete',  'users',    'delete', 'Delete users'),
    ('orders:read',   'orders',   'read',   'View orders'),
    ('orders:write',  'orders',   'write',  'Create/update orders'),
    ('products:read', 'products', 'read',   'View products'),
    ('products:write','products', 'write',  'Create/update products');

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p WHERE r.name = 'ROLE_ADMIN';

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.name = 'ROLE_MANAGER' AND p.action IN ('read', 'write');

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.name = 'ROLE_USER' AND p.action = 'read';

-- Seed admin user (BCrypt hash of 'admin123')
INSERT INTO users (username, password, email) VALUES
    ('admin', '$2a$10$zW/T2/p3Ooa2RbLmLC/ZDuwsMPebx/bxh3fuWupr6z9NVnomNaiQG', 'admin@example.com');

INSERT INTO user_roles (user_id, role_id)
SELECT u.id, r.id FROM users u, roles r WHERE u.username = 'admin' AND r.name = 'ROLE_ADMIN';
