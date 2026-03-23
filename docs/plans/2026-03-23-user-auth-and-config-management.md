# User Auth (RBAC) + Config Management Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite Go stub services to Java Spring Boot, add React frontend with user login, implement RBAC via api-auth, make api-order a complete CRUD service accessible by both internal users and external partners, and establish best-practice config management with profiles and mounted secrets.

**Architecture:** Hybrid JWT auth (short-lived access token + httpOnly refresh cookie) with RBAC. Spring Cloud Gateway powers the BFF. PostgreSQL for persistence. api-order has dual access: internal users via BFF (user JWT) and partners via ssl-proxy (partner JWT/Lua). Each service independently manages its own dependencies (no shared common module). SSL termination and partner JWT auth remain in OpenResty ssl-proxy (unchanged).

**Tech Stack:**
- Java 21, Spring Boot 3.3, Spring Cloud Gateway, Spring Security, Spring Data JPA, Flyway
- PostgreSQL 16 (containerized)
- React 18 + Vite + React Router + Axios
- Maven (multi-module parent POM, no shared library)
- Existing: OpenResty ssl-proxy (unchanged), Podman + Quadlet

---

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| BFF | Spring Cloud Gateway | Purpose-built gateway with native JWT filter support |
| Auth pattern | Hybrid JWT + httpOnly cookie | RBAC claims in JWT, refresh via secure cookie |
| api-order | Full CRUD, dual access (internal + partner) | Partners need real endpoints |
| api-user, api-product | Stubs with DB connection verified | Internal only, flesh out later |
| Shared library | None | Each service owns its dependencies independently |
| Config management | application.yml (baked) + application-{profile}.yml (mounted) + secret files | Best practice env separation |
| RBAC model | users → user_roles → roles → role_permissions → permissions | Standard 5-table RBAC |

---

## Dual Access Pattern: api-order

```
Internal user:  Browser → ssl-proxy → BFF (validates user JWT, adds X-User-* headers) → api-order
Partner:        Partner → ssl-proxy (validates partner JWT via Lua, adds X-Partner-* headers) → api-order
```

api-order distinguishes the caller by checking headers:
- `X-User-Id` + `X-User-Roles` → internal request (from BFF)
- `X-Partner-ID` + `X-Partner-Name` → partner request (from ssl-proxy Lua)

---

## Project Structure

```
project-root/
├── services/
│   ├── pom.xml                        # Maven parent POM (shared dep versions only)
│   ├── api-auth/                      # Auth service - login, register, RBAC
│   │   ├── pom.xml
│   │   ├── Dockerfile
│   │   ├── config/
│   │   │   ├── application-dev.yml
│   │   │   └── application-prod.yml
│   │   └── src/main/
│   │       ├── java/com/example/auth/
│   │       │   ├── AuthApplication.java
│   │       │   ├── config/SecurityConfig.java
│   │       │   ├── controller/AuthController.java
│   │       │   ├── dto/{LoginRequest,RegisterRequest,TokenResponse}.java
│   │       │   ├── entity/{User,Role,Permission}.java
│   │       │   ├── repository/{UserRepository,RoleRepository}.java
│   │       │   ├── service/{AuthService,JwtService}.java
│   │       │   └── exception/GlobalExceptionHandler.java
│   │       └── resources/
│   │           ├── application.yml
│   │           └── db/migration/
│   │               ├── V1__create_rbac_schema.sql
│   │               └── V2__seed_default_roles.sql
│   ├── api-order/                     # Order service - full CRUD (partner + internal)
│   │   ├── pom.xml
│   │   ├── Dockerfile
│   │   ├── config/
│   │   │   ├── application-dev.yml
│   │   │   └── application-prod.yml
│   │   └── src/main/
│   │       ├── java/com/example/order/
│   │       │   ├── OrderApplication.java
│   │       │   ├── controller/OrderController.java
│   │       │   ├── dto/{CreateOrderRequest,OrderResponse}.java
│   │       │   ├── entity/Order.java
│   │       │   ├── repository/OrderRepository.java
│   │       │   └── service/OrderService.java
│   │       └── resources/
│   │           ├── application.yml
│   │           └── db/migration/
│   │               └── V1__create_orders_table.sql
│   ├── api-user/                      # Stub (internal only)
│   │   ├── pom.xml
│   │   ├── Dockerfile
│   │   ├── config/
│   │   │   ├── application-dev.yml
│   │   │   └── application-prod.yml
│   │   └── src/main/
│   │       ├── java/com/example/user/
│   │       │   ├── UserApplication.java
│   │       │   └── controller/UserController.java
│   │       └── resources/application.yml
│   ├── api-product/                   # Stub (internal only)
│   │   ├── pom.xml
│   │   ├── Dockerfile
│   │   ├── config/
│   │   │   ├── application-dev.yml
│   │   │   └── application-prod.yml
│   │   └── src/main/
│   │       ├── java/com/example/product/
│   │       │   ├── ProductApplication.java
│   │       │   └── controller/ProductController.java
│   │       └── resources/application.yml
│   ├── bff/                           # BFF - Spring Cloud Gateway + JWT filter
│   │   ├── pom.xml
│   │   ├── Dockerfile
│   │   ├── config/
│   │   │   ├── application-dev.yml
│   │   │   └── application-prod.yml
│   │   └── src/main/
│   │       ├── java/com/example/bff/
│   │       │   ├── BffApplication.java
│   │       │   ├── config/SecurityConfig.java
│   │       │   └── filter/JwtAuthFilter.java
│   │       └── resources/application.yml
│   ├── frontend/                      # React SPA (Vite)
│   │   ├── Dockerfile
│   │   ├── nginx.conf
│   │   ├── package.json
│   │   ├── vite.config.ts
│   │   └── src/
│   │       ├── main.tsx
│   │       ├── App.tsx
│   │       ├── api/client.ts
│   │       ├── auth/{AuthContext.tsx,ProtectedRoute.tsx,useAuth.ts}
│   │       └── pages/{LoginPage.tsx,DashboardPage.tsx}
│   └── ssl-proxy/                     # Moved from dockerfiles/ (logic unchanged)
│       ├── Dockerfile
│       ├── nginx.conf
│       ├── conf.d/{routes.conf,upstream.conf,partners.json}
│       └── lua/{partner-auth.lua,partners-loader.lua}
├── configs/                           # Infrastructure config only
│   ├── postgres/
│   │   └── init-db.sh
│   ├── ha.conf
│   └── images.env
├── secrets/                           # Local dev secrets (gitignored)
│   ├── db-password.properties         # spring.datasource.password=...
│   ├── jwt-signing-key.properties     # jwt.signing-key=...
│   └── postgres-password
├── quadlet/
├── scripts/
├── docs/plans/
├── certs/
└── .gitignore
```

**Deleted:** `dockerfiles/`, `examples/`, `configs/ssl-proxy/`, `configs/frontend/` (moved into `services/`)

---

## Configuration Management (3 Layers)

```
┌────────────────────────────────────────────────────────┐
│ Layer 1: application.yml (baked into JAR)               │
│ - Server port, actuator, logging defaults               │
│ - Safe defaults that work without external config       │
├────────────────────────────────────────────────────────┤
│ Layer 2: application-{profile}.yml (mounted volume)     │
│ - spring.datasource.url per environment                 │
│ - Logging levels                                        │
│ - Mounted at: /app/config/                              │
├────────────────────────────────────────────────────────┤
│ Layer 3: Secret files (mounted at /run/secrets/)        │
│ - spring.datasource.password                            │
│ - jwt.signing-key                                       │
│ - Podman Secrets in prod, local files in dev            │
└────────────────────────────────────────────────────────┘
```

### Baked defaults (example: api-order)

```yaml
server:
  port: 8080

spring:
  application:
    name: api-order
  profiles:
    active: ${SPRING_PROFILES_ACTIVE:dev}
  datasource:
    url: jdbc:postgresql://postgres:5432/microservices
    username: app_user
    hikari:
      maximum-pool-size: 10
      minimum-idle: 2
  jpa:
    hibernate:
      ddl-auto: validate
    open-in-view: false
  flyway:
    enabled: true
  config:
    import:
      - optional:file:/run/secrets/db-password.properties

management:
  endpoints:
    web:
      exposure:
        include: health,info

logging:
  level:
    root: INFO
    com.example: INFO
```

### Dev override (example: api-order)

```yaml
# services/api-order/config/application-dev.yml
spring:
  datasource:
    url: jdbc:postgresql://postgres:5432/microservices_dev
  jpa:
    show-sql: true
logging:
  level:
    com.example: DEBUG
```

### Prod override (example: api-order)

```yaml
# services/api-order/config/application-prod.yml
spring:
  datasource:
    url: jdbc:postgresql://postgres:5432/microservices
    hikari:
      maximum-pool-size: 20
logging:
  level:
    root: WARN
    com.example: INFO
```

### Secret files

```properties
# secrets/db-password.properties
spring.datasource.password=dev-password-change-me

# secrets/jwt-signing-key.properties
jwt.signing-key=dev-jwt-secret-key-minimum-32-characters-long!!
```

---

## RBAC Schema

```sql
-- V1__create_rbac_schema.sql

CREATE TABLE users (
    id          BIGSERIAL PRIMARY KEY,
    username    VARCHAR(50)  NOT NULL UNIQUE,
    password    VARCHAR(255) NOT NULL,
    email       VARCHAR(100) NOT NULL UNIQUE,
    enabled     BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMP    NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE TABLE roles (
    id          BIGSERIAL PRIMARY KEY,
    name        VARCHAR(50) NOT NULL UNIQUE,
    description VARCHAR(255)
);

CREATE TABLE permissions (
    id          BIGSERIAL PRIMARY KEY,
    name        VARCHAR(100) NOT NULL UNIQUE,
    resource    VARCHAR(50)  NOT NULL,
    action      VARCHAR(20)  NOT NULL,
    description VARCHAR(255)
);

CREATE TABLE user_roles (
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id BIGINT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, role_id)
);

CREATE TABLE role_permissions (
    role_id       BIGINT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id BIGINT NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_email ON users(email);
```

```sql
-- V2__seed_default_roles.sql

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

-- Seed admin user
-- IMPORTANT: Generate real BCrypt hash at implementation time:
--   echo -n 'admin123' | htpasswd -nbBC 10 "" - | cut -d: -f2
INSERT INTO users (username, password, email) VALUES
    ('admin', '$2a$10$GENERATE_REAL_BCRYPT_HASH_AT_IMPL_TIME', 'admin@example.com');

INSERT INTO user_roles (user_id, role_id)
SELECT u.id, r.id FROM users u, roles r WHERE u.username = 'admin' AND r.name = 'ROLE_ADMIN';
```

## Orders Schema

```sql
-- V1__create_orders_table.sql (in api-order service)

CREATE TABLE orders (
    id             BIGSERIAL PRIMARY KEY,
    order_number   VARCHAR(50)    NOT NULL UNIQUE,
    customer_name  VARCHAR(100)   NOT NULL,
    status         VARCHAR(20)    NOT NULL DEFAULT 'PENDING',
    total_amount   DECIMAL(12,2),
    created_by     VARCHAR(50)    NOT NULL,
    source         VARCHAR(20)    NOT NULL DEFAULT 'INTERNAL',
    created_at     TIMESTAMP      NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMP      NOT NULL DEFAULT NOW()
);

-- source: 'INTERNAL' (user via BFF) or 'PARTNER' (via ssl-proxy)
-- created_by: username (internal) or partner_id (partner)

CREATE INDEX idx_orders_order_number ON orders(order_number);
CREATE INDEX idx_orders_source ON orders(source);
CREATE INDEX idx_orders_created_by ON orders(created_by);
```

---

## Auth Flow

```
┌──────────┐     ┌─────────────┐     ┌──────────┐     ┌──────────┐
│ React    │     │ SSL Proxy   │     │ BFF      │     │ api-auth │
│ Frontend │     │ (OpenResty) │     │ (SCG)    │     │          │
└────┬─────┘     └──────┬──────┘     └────┬─────┘     └────┬─────┘
     │                  │                 │                 │
     │ POST /api/auth/login               │                 │
     ├─────────────────►├────────────────►├────────────────►│
     │                  │                 │                 │
     │  {access_token}  │                 │  + Set-Cookie:  │
     │  + Set-Cookie    │◄────────────────┤◄────────────────┤
     │◄─────────────────┤                 │                 │
     │                  │                 │                 │
     │ GET /api/orders  │                 │                 │
     │ Authorization:   │                 │ validate JWT    │
     │ Bearer <token>   │                 │ add X-User-*    │
     ├─────────────────►├────────────────►├────────────────►│ api-order
     │  {order data}    │                 │                 │
     │◄─────────────────┤◄────────────────┤◄────────────────┤
```

---

## Chunk 1: Infrastructure Foundation

### Task 1.1: Clean Up Go Artifacts and Scaffold

**Files:**
- Delete: `dockerfiles/` (entire directory)
- Delete: `examples/` (entire directory)
- Modify: `.gitignore`

- [ ] **Step 1: Remove old directories**

```bash
rm -rf dockerfiles/ examples/
```

- [ ] **Step 2: Create new directory structure**

```bash
mkdir -p services/{api-auth,api-order,api-user,api-product,bff}/{src,config}
mkdir -p services/{frontend,ssl-proxy}
mkdir -p configs/postgres
mkdir -p secrets
```

- [ ] **Step 3: Move ssl-proxy files to services/ssl-proxy/**

Copy existing `configs/ssl-proxy/` contents (nginx.conf, conf.d/, lua/) into `services/ssl-proxy/`, then recreate the ssl-proxy Dockerfile at `services/ssl-proxy/Dockerfile`.

- [ ] **Step 4: Move frontend nginx.conf to services/frontend/**

Copy `configs/frontend/nginx.conf` to `services/frontend/nginx.conf`.

- [ ] **Step 5: Update .gitignore**

```gitignore
# Secrets
secrets/

# Java
services/*/target/

# Node
services/frontend/node_modules/
services/frontend/dist/
```

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: remove Go stubs, scaffold Java+React project structure"
```

---

### Task 1.2: PostgreSQL Container

**Files:**
- Create: `configs/postgres/init-db.sh`
- Create: `secrets/db-password.properties`
- Create: `secrets/jwt-signing-key.properties`
- Create: `secrets/postgres-password`
- Modify: `configs/images.env`
- Modify: `scripts/local-start.sh`
- Modify: `scripts/local-stop.sh`

- [ ] **Step 1: Create init-db.sh**

```bash
#!/bin/bash
set -e
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    CREATE DATABASE microservices_dev;
    CREATE DATABASE microservices;
    CREATE USER app_user WITH PASSWORD '${APP_USER_PASSWORD:-dev-password-change-me}';
    GRANT ALL PRIVILEGES ON DATABASE microservices_dev TO app_user;
    GRANT ALL PRIVILEGES ON DATABASE microservices TO app_user;
EOSQL
for db in microservices_dev microservices; do
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" -d "$db" <<-EOSQL
        GRANT ALL ON SCHEMA public TO app_user;
EOSQL
done
```

- [ ] **Step 2: Create secret files**

```properties
# secrets/db-password.properties
spring.datasource.password=dev-password-change-me

# secrets/jwt-signing-key.properties
jwt.signing-key=dev-jwt-secret-key-minimum-32-characters-long!!

# secrets/postgres-password  (plain text, no key=value)
dev-password-change-me
```

- [ ] **Step 3: Add POSTGRES_IMAGE to images.env**

```bash
POSTGRES_IMAGE=docker.io/library/postgres:16-alpine
```

- [ ] **Step 4: Add start_postgres() to local-start.sh**

```bash
start_postgres() {
    section "PostgreSQL"
    local name="postgres"
    if podman container exists "$name" 2>/dev/null; then
        warning "$name already running, skipping"
        return
    fi
    info "Starting $name ..."
    podman run -d --name "$name" \
        --network "$NETWORK" \
        --network-alias postgres \
        --label "$LABEL" \
        -e POSTGRES_PASSWORD="$(cat "$PROJECT_ROOT/secrets/postgres-password")" \
        -e APP_USER_PASSWORD="$(grep -oP '(?<=spring.datasource.password=).*' "$PROJECT_ROOT/secrets/db-password.properties")" \
        -v "$PROJECT_ROOT/configs/postgres/init-db.sh:/docker-entrypoint-initdb.d/init-db.sh:ro" \
        -v "pgdata:/var/lib/postgresql/data" \
        "$POSTGRES_IMAGE"
    success "$name started"
}
```

Call `start_postgres` in `main()` before `start_api_services`.

- [ ] **Step 5: Add postgres stop to local-stop.sh**

- [ ] **Step 6: Verify**

```bash
./scripts/local-stop.sh && ./scripts/local-start.sh
podman exec postgres psql -U app_user -d microservices_dev -c 'SELECT 1'
```

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add PostgreSQL container with init script and dev secrets"
```

---

### Task 1.3: Maven Parent POM

**Files:**
- Create: `services/pom.xml`

- [ ] **Step 1: Create parent POM**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
         https://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>3.3.6</version>
        <relativePath/>
    </parent>

    <groupId>com.example</groupId>
    <artifactId>microservices-parent</artifactId>
    <version>1.0.0-SNAPSHOT</version>
    <packaging>pom</packaging>
    <name>Microservices Parent</name>

    <modules>
        <module>api-auth</module>
        <module>api-order</module>
        <module>api-user</module>
        <module>api-product</module>
        <module>bff</module>
    </modules>

    <properties>
        <java.version>21</java.version>
        <spring-cloud.version>2023.0.4</spring-cloud.version>
        <jjwt.version>0.12.6</jjwt.version>
    </properties>

    <dependencyManagement>
        <dependencies>
            <dependency>
                <groupId>org.springframework.cloud</groupId>
                <artifactId>spring-cloud-dependencies</artifactId>
                <version>${spring-cloud.version}</version>
                <type>pom</type>
                <scope>import</scope>
            </dependency>
            <dependency>
                <groupId>io.jsonwebtoken</groupId>
                <artifactId>jjwt-api</artifactId>
                <version>${jjwt.version}</version>
            </dependency>
            <dependency>
                <groupId>io.jsonwebtoken</groupId>
                <artifactId>jjwt-impl</artifactId>
                <version>${jjwt.version}</version>
                <scope>runtime</scope>
            </dependency>
            <dependency>
                <groupId>io.jsonwebtoken</groupId>
                <artifactId>jjwt-jackson</artifactId>
                <version>${jjwt.version}</version>
                <scope>runtime</scope>
            </dependency>
        </dependencies>
    </dependencyManagement>
</project>
```

- [ ] **Step 2: Commit**

```bash
git add services/pom.xml
git commit -m "chore: add Maven parent POM with shared dependency versions"
```

---

## Chunk 2: api-auth Service

### Task 2.1: api-auth Project + Entities + Migrations

**Files:**
- Create: `services/api-auth/pom.xml`
- Create: `services/api-auth/src/main/java/com/example/auth/AuthApplication.java`
- Create: `services/api-auth/src/main/resources/application.yml`
- Create: `services/api-auth/src/main/resources/db/migration/V1__create_rbac_schema.sql`
- Create: `services/api-auth/src/main/resources/db/migration/V2__seed_default_roles.sql`
- Create: `services/api-auth/src/main/java/com/example/auth/entity/{User,Role,Permission}.java`
- Create: `services/api-auth/src/main/java/com/example/auth/repository/{UserRepository,RoleRepository}.java`

- [ ] **Step 1: Create pom.xml** with dependencies: spring-boot-starter-web, spring-boot-starter-security, spring-boot-starter-data-jpa, spring-boot-starter-validation, spring-boot-starter-actuator, postgresql, flyway-core, flyway-database-postgresql, jjwt-api, jjwt-impl, jjwt-jackson, spring-boot-starter-test, spring-security-test.

- [ ] **Step 2: Create AuthApplication.java** (standard `@SpringBootApplication` main class)

- [ ] **Step 3: Create application.yml** (see Config Management section; includes `spring.config.import` for secrets, Flyway enabled, jwt.expiration-ms=900000, jwt.refresh-expiration-ms=604800000)

- [ ] **Step 4: Create V1 and V2 Flyway migrations** (see RBAC Schema section above)

- [ ] **Step 5: Create User entity**

```java
package com.example.auth.entity;

@Entity
@Table(name = "users")
public class User {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @Column(nullable = false, unique = true, length = 50)
    private String username;
    @Column(nullable = false)
    private String password;
    @Column(nullable = false, unique = true, length = 100)
    private String email;
    private boolean enabled = true;
    private LocalDateTime createdAt = LocalDateTime.now();
    private LocalDateTime updatedAt = LocalDateTime.now();

    @ManyToMany(fetch = FetchType.EAGER)
    @JoinTable(name = "user_roles",
        joinColumns = @JoinColumn(name = "user_id"),
        inverseJoinColumns = @JoinColumn(name = "role_id"))
    private Set<Role> roles = new HashSet<>();

    // getters + setters
}
```

- [ ] **Step 6: Create Role entity** (with `@ManyToMany` to Permission via `role_permissions` join table)

- [ ] **Step 7: Create Permission entity** (id, name, resource, action, description)

- [ ] **Step 8: Create UserRepository** (`findByUsername`, `existsByUsername`, `existsByEmail`)

- [ ] **Step 9: Create RoleRepository** (`findByName`)

- [ ] **Step 10: Verify compile**

```bash
cd services && mvn -pl api-auth compile -q
```

- [ ] **Step 11: Commit**

```bash
git add services/api-auth/
git commit -m "feat(api-auth): scaffold project with RBAC entities and Flyway migrations"
```

---

### Task 2.2: JWT Service + Auth Service + Controller

**Files:**
- Create: `services/api-auth/src/main/java/com/example/auth/service/JwtService.java`
- Create: `services/api-auth/src/main/java/com/example/auth/service/AuthService.java`
- Create: `services/api-auth/src/main/java/com/example/auth/dto/{LoginRequest,RegisterRequest,TokenResponse}.java`
- Create: `services/api-auth/src/main/java/com/example/auth/controller/AuthController.java`
- Create: `services/api-auth/src/main/java/com/example/auth/config/SecurityConfig.java`
- Create: `services/api-auth/src/main/java/com/example/auth/exception/GlobalExceptionHandler.java`

- [ ] **Step 1: Create JwtService**

```java
package com.example.auth.service;

@Service
public class JwtService {
    private final SecretKey signingKey;
    private final long accessExpirationMs;
    private final long refreshExpirationMs;

    public JwtService(@Value("${jwt.signing-key}") String secret,
                      @Value("${jwt.expiration-ms}") long accessMs,
                      @Value("${jwt.refresh-expiration-ms}") long refreshMs) {
        this.signingKey = Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
        this.accessExpirationMs = accessMs;
        this.refreshExpirationMs = refreshMs;
    }

    public String generateAccessToken(String username, List<String> roles, List<String> permissions) {
        return Jwts.builder()
            .subject(username)
            .claims(Map.of("roles", roles, "permissions", permissions, "type", "access"))
            .issuedAt(new Date())
            .expiration(new Date(System.currentTimeMillis() + accessExpirationMs))
            .signWith(signingKey).compact();
    }

    public String generateRefreshToken(String username) {
        return Jwts.builder()
            .subject(username).claims(Map.of("type", "refresh"))
            .issuedAt(new Date())
            .expiration(new Date(System.currentTimeMillis() + refreshExpirationMs))
            .signWith(signingKey).compact();
    }

    public Claims parseToken(String token) {
        return Jwts.parser().verifyWith(signingKey).build()
            .parseSignedClaims(token).getPayload();
    }

    public boolean isValid(String token) {
        try { parseToken(token); return true; }
        catch (Exception e) { return false; }
    }

    public String getUsername(String token) { return parseToken(token).getSubject(); }
}
```

- [ ] **Step 2: Create DTOs** (records: `LoginRequest(username, password)`, `RegisterRequest(username, password, email)`, `TokenResponse(accessToken, tokenType, expiresIn)`)

- [ ] **Step 3: Create AuthService** with methods: `login(LoginRequest)`, `register(RegisterRequest)`, `refresh(String refreshToken)`. Each returns `AuthResult(TokenResponse, refreshToken)`. Register assigns `ROLE_USER` by default.

- [ ] **Step 4: Create SecurityConfig** (stateless, CSRF disabled, permit `/auth/**` and `/health` and `/actuator/health`, BCryptPasswordEncoder bean)

- [ ] **Step 5: Create AuthController**

```java
@RestController
@RequestMapping("/auth")
public class AuthController {
    @PostMapping("/login")    → returns TokenResponse + sets refresh_token httpOnly cookie
    @PostMapping("/register") → returns TokenResponse + sets refresh_token httpOnly cookie
    @PostMapping("/refresh")  → reads refresh_token from @CookieValue, returns new TokenResponse
    @PostMapping("/logout")   → clears refresh_token cookie (maxAge=0)
}
```

Cookie config: `httpOnly=true, secure=true, path=/api/auth/refresh`

- [ ] **Step 6: Create GlobalExceptionHandler** (handles `IllegalArgumentException` → 400, `MethodArgumentNotValidException` → 400)

- [ ] **Step 7: Commit**

```bash
git add services/api-auth/
git commit -m "feat(api-auth): add JWT, auth service, controller, security config"
```

---

### Task 2.3: api-auth Dockerfile and Config Profiles

**Files:**
- Create: `services/api-auth/Dockerfile`
- Create: `services/api-auth/config/application-dev.yml`
- Create: `services/api-auth/config/application-prod.yml`

- [ ] **Step 1: Create Dockerfile**

```dockerfile
FROM maven:3.9-eclipse-temurin-21-alpine AS builder
WORKDIR /build
COPY pom.xml ./pom.xml
RUN mvn -N install -q -B
COPY api-auth/pom.xml ./api-auth/pom.xml
RUN mvn -pl api-auth dependency:go-offline -q -B
COPY api-auth/src ./api-auth/src
RUN mvn -pl api-auth package -DskipTests -q -B

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
RUN addgroup -S app && adduser -S app -G app
COPY --from=builder /build/api-auth/target/*.jar app.jar
RUN mkdir -p /app/config && chown -R app:app /app
USER app
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD wget -qO- http://localhost:8080/actuator/health || exit 1
ENTRYPOINT ["java", "-XX:+UseContainerSupport", "-XX:MaxRAMPercentage=75.0", \
    "-jar", "app.jar", \
    "--spring.config.additional-location=optional:file:/app/config/"]
```

Note: `mvn -N install` installs the parent POM without resolving child modules. All Java Dockerfiles follow this pattern.

- [ ] **Step 2: Create config profiles**

```yaml
# services/api-auth/config/application-dev.yml
spring:
  datasource:
    url: jdbc:postgresql://postgres:5432/microservices_dev
  jpa:
    show-sql: true
logging:
  level:
    com.example: DEBUG
    org.springframework.security: DEBUG
```

```yaml
# services/api-auth/config/application-prod.yml
spring:
  datasource:
    url: jdbc:postgresql://postgres:5432/microservices
    hikari:
      maximum-pool-size: 20
logging:
  level:
    root: WARN
    com.example: INFO
```

- [ ] **Step 3: Commit**

```bash
git add services/api-auth/
git commit -m "feat(api-auth): add Dockerfile and config profiles"
```

---

## Chunk 3: api-order Service (Full CRUD)

### Task 3.1: api-order Project + Entity + Migration

**Files:**
- Create: `services/api-order/pom.xml`
- Create: `services/api-order/src/main/java/com/example/order/OrderApplication.java`
- Create: `services/api-order/src/main/resources/application.yml`
- Create: `services/api-order/src/main/resources/db/migration/V1__create_orders_table.sql`
- Create: `services/api-order/src/main/java/com/example/order/entity/Order.java`
- Create: `services/api-order/src/main/java/com/example/order/repository/OrderRepository.java`

- [ ] **Step 1: Create pom.xml** with: spring-boot-starter-web, starter-data-jpa, starter-actuator, starter-validation, postgresql, flyway-core, flyway-database-postgresql, starter-test.

- [ ] **Step 2: Create OrderApplication.java**

- [ ] **Step 3: Create application.yml** (same 3-layer pattern as api-auth, but no JWT or security deps; includes `spring.config.import` for db-password secret)

- [ ] **Step 4: Create V1 migration** (see Orders Schema section above)

- [ ] **Step 5: Create Order entity**

```java
package com.example.order.entity;

@Entity
@Table(name = "orders")
public class Order {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "order_number", nullable = false, unique = true, length = 50)
    private String orderNumber;

    @Column(name = "customer_name", nullable = false, length = 100)
    private String customerName;

    @Column(nullable = false, length = 20)
    private String status = "PENDING";

    @Column(name = "total_amount", precision = 12, scale = 2)
    private BigDecimal totalAmount;

    @Column(name = "created_by", nullable = false, length = 50)
    private String createdBy;

    @Column(nullable = false, length = 20)
    private String source = "INTERNAL";

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt = LocalDateTime.now();

    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt = LocalDateTime.now();

    // getters + setters
}
```

- [ ] **Step 6: Create OrderRepository** (`findByOrderNumber`, `findBySource`, `findByCreatedBy`)

- [ ] **Step 7: Commit**

```bash
git add services/api-order/
git commit -m "feat(api-order): scaffold project with Order entity and migration"
```

---

### Task 3.2: api-order Service + Controller (Dual Access)

**Files:**
- Create: `services/api-order/src/main/java/com/example/order/dto/{CreateOrderRequest,OrderResponse}.java`
- Create: `services/api-order/src/main/java/com/example/order/service/OrderService.java`
- Create: `services/api-order/src/main/java/com/example/order/controller/OrderController.java`

- [ ] **Step 1: Create DTOs**

```java
public record CreateOrderRequest(
    @NotBlank String customerName,
    @NotNull BigDecimal totalAmount
) {}

public record OrderResponse(
    Long id, String orderNumber, String customerName,
    String status, BigDecimal totalAmount,
    String createdBy, String source,
    LocalDateTime createdAt
) {}
```

- [ ] **Step 2: Create OrderService**

```java
@Service
public class OrderService {
    private final OrderRepository orderRepository;

    public OrderResponse create(CreateOrderRequest req, String createdBy, String source) {
        Order order = new Order();
        order.setOrderNumber(generateOrderNumber());
        order.setCustomerName(req.customerName());
        order.setTotalAmount(req.totalAmount());
        order.setCreatedBy(createdBy);
        order.setSource(source);
        return toResponse(orderRepository.save(order));
    }

    public List<OrderResponse> list(String createdBy, String source) {
        // If source is provided, filter by it; otherwise return all for the user
        return orderRepository.findByCreatedBy(createdBy).stream()
            .map(this::toResponse).toList();
    }

    public OrderResponse getById(Long id) { ... }
    public OrderResponse updateStatus(Long id, String status) { ... }

    private String generateOrderNumber() {
        return "ORD-" + System.currentTimeMillis();
    }

    private OrderResponse toResponse(Order o) { ... }
}
```

- [ ] **Step 3: Create OrderController** (dual access via headers)

```java
@RestController
public class OrderController {

    @GetMapping("/health")
    public Map<String, String> health() {
        return Map.of("status", "healthy", "service", "api-order");
    }

    @PostMapping("/orders")
    public ResponseEntity<OrderResponse> create(
            @Valid @RequestBody CreateOrderRequest req,
            @RequestHeader(value = "X-User-Id", required = false) String userId,
            @RequestHeader(value = "X-Partner-ID", required = false) String partnerId) {
        CallerInfo caller = resolveCaller(userId, partnerId);
        return ResponseEntity.status(201).body(orderService.create(req, caller.id(), caller.source()));
    }

    @GetMapping("/orders")
    public List<OrderResponse> list(
            @RequestHeader(value = "X-User-Id", required = false) String userId,
            @RequestHeader(value = "X-Partner-ID", required = false) String partnerId) {
        CallerInfo caller = resolveCaller(userId, partnerId);
        return orderService.list(caller.id(), caller.source());
    }

    @GetMapping("/orders/{id}")
    public OrderResponse getById(@PathVariable Long id) { ... }

    @PatchMapping("/orders/{id}/status")
    public OrderResponse updateStatus(@PathVariable Long id, @RequestBody Map<String, String> body) { ... }

    private record CallerInfo(String id, String source) {}

    private CallerInfo resolveCaller(String userId, String partnerId) {
        if (partnerId != null) return new CallerInfo(partnerId, "PARTNER");
        if (userId != null) return new CallerInfo(userId, "INTERNAL");
        throw new IllegalArgumentException("No caller identity in request headers");
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add services/api-order/
git commit -m "feat(api-order): add CRUD controller with dual access (internal + partner)"
```

---

### Task 3.3: api-order Dockerfile and Config

**Files:**
- Create: `services/api-order/Dockerfile`
- Create: `services/api-order/config/application-dev.yml`
- Create: `services/api-order/config/application-prod.yml`

- [ ] **Step 1: Create Dockerfile** (same pattern as api-auth, replacing `api-auth` with `api-order`)
- [ ] **Step 2: Create config profiles** (same pattern as api-auth, without security debug logging)
- [ ] **Step 3: Commit**

```bash
git add services/api-order/
git commit -m "feat(api-order): add Dockerfile and config profiles"
```

---

## Chunk 4: Stub Services (api-user, api-product)

### Task 4.1: api-user Stub

**Files:**
- Create: `services/api-user/pom.xml`
- Create: `services/api-user/Dockerfile`
- Create: `services/api-user/config/{application-dev.yml,application-prod.yml}`
- Create: `services/api-user/src/main/java/com/example/user/{UserApplication,controller/UserController}.java`
- Create: `services/api-user/src/main/resources/application.yml`

- [ ] **Step 1: Create pom.xml** with: starter-web, starter-actuator, starter-data-jpa, postgresql, starter-test.

- [ ] **Step 2: Create UserApplication.java**

- [ ] **Step 3: Create UserController.java** (`GET /health` → healthy, `GET /` → ok)

- [ ] **Step 4: Create application.yml** (same config pattern, DB connection for verification)

- [ ] **Step 5: Create Dockerfile** (same pattern, `api-user`)

- [ ] **Step 6: Create config profiles**

- [ ] **Step 7: Commit**

```bash
git add services/api-user/
git commit -m "feat(api-user): add Spring Boot stub with DB connection"
```

---

### Task 4.2: api-product Stub

Same as Task 4.1 but for api-product. Package: `com.example.product`, class: `ProductApplication`, `ProductController`.

- [ ] **Step 1-6: Repeat pattern for api-product**

- [ ] **Step 7: Commit**

```bash
git add services/api-product/
git commit -m "feat(api-product): add Spring Boot stub with DB connection"
```

---

## Chunk 5: BFF (Spring Cloud Gateway)

### Task 5.1: BFF Project + JWT Filter

**Files:**
- Create: `services/bff/pom.xml`
- Create: `services/bff/Dockerfile`
- Create: `services/bff/config/{application-dev.yml,application-prod.yml}`
- Create: `services/bff/src/main/java/com/example/bff/BffApplication.java`
- Create: `services/bff/src/main/java/com/example/bff/config/SecurityConfig.java`
- Create: `services/bff/src/main/java/com/example/bff/filter/JwtAuthFilter.java`
- Create: `services/bff/src/main/resources/application.yml`

- [ ] **Step 1: Create pom.xml** with: spring-cloud-starter-gateway, starter-security, starter-actuator, jjwt-api, jjwt-impl, jjwt-jackson, starter-test.

- [ ] **Step 2: Create BffApplication.java**

- [ ] **Step 3: Create application.yml with routes**

```yaml
server:
  port: 8080

spring:
  application:
    name: bff
  profiles:
    active: ${SPRING_PROFILES_ACTIVE:dev}
  cloud:
    gateway:
      routes:
        - id: auth-service
          uri: http://api-auth:8080
          predicates:
            - Path=/api/auth/**
          filters:
            - StripPrefix=1

        - id: user-service
          uri: http://api-user:8080
          predicates:
            - Path=/api/users,/api/users/**
          filters:
            - StripPrefix=1
            - JwtAuth

        - id: order-service
          uri: http://api-order:8080
          predicates:
            - Path=/api/orders,/api/orders/**
          filters:
            - StripPrefix=1
            - JwtAuth

        - id: product-service
          uri: http://api-product:8080
          predicates:
            - Path=/api/products,/api/products/**
          filters:
            - StripPrefix=1
            - JwtAuth
  config:
    import:
      - optional:file:/run/secrets/jwt-signing-key.properties

jwt:
  signing-key: ${jwt.signing-key:dev-jwt-secret-key-minimum-32-characters-long!!}

management:
  endpoints:
    web:
      exposure:
        include: health,info
```

- [ ] **Step 4: Create SecurityConfig** (WebFlux: `@EnableWebFluxSecurity`, permit `/api/auth/**` and health, disable csrf/httpBasic/formLogin)

- [ ] **Step 5: Create JwtAuthFilter** (pre-build `JwtParser` in constructor)

```java
@Component
public class JwtAuthFilter extends AbstractGatewayFilterFactory<JwtAuthFilter.Config> {
    private final JwtParser jwtParser;

    public JwtAuthFilter(@Value("${jwt.signing-key}") String secret) {
        super(Config.class);
        SecretKey key = Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
        this.jwtParser = Jwts.parser().verifyWith(key).build();
    }

    @Override
    public GatewayFilter apply(Config config) {
        return (exchange, chain) -> {
            String authHeader = exchange.getRequest().getHeaders()
                .getFirst(HttpHeaders.AUTHORIZATION);
            if (authHeader == null || !authHeader.startsWith("Bearer "))
                return unauthorized(exchange);

            try {
                Claims claims = jwtParser.parseSignedClaims(authHeader.substring(7)).getPayload();
                ServerWebExchange mutated = exchange.mutate()
                    .request(r -> r
                        .header("X-User-Id", claims.getSubject())
                        .header("X-User-Roles", String.join(",", claims.get("roles", List.class)))
                        .header("X-User-Permissions", String.join(",", claims.get("permissions", List.class)))
                    ).build();
                return chain.filter(mutated);
            } catch (Exception e) {
                return unauthorized(exchange);
            }
        };
    }

    private Mono<Void> unauthorized(ServerWebExchange exchange) {
        exchange.getResponse().setStatusCode(HttpStatus.UNAUTHORIZED);
        return exchange.getResponse().setComplete();
    }

    public static class Config {}
}
```

- [ ] **Step 6: Create Dockerfile** (same pattern, `bff`)

- [ ] **Step 7: Create config profiles** (dev: debug logging only; prod: warn logging only — routes are in baked application.yml)

- [ ] **Step 8: Commit**

```bash
git add services/bff/
git commit -m "feat(bff): add Spring Cloud Gateway with JWT auth filter"
```

---

## Chunk 6: React Frontend

### Task 6.1: Vite + React Scaffold

**Files:**
- Create: `services/frontend/package.json`
- Create: `services/frontend/vite.config.ts`
- Create: `services/frontend/src/main.tsx`
- Create: `services/frontend/src/App.tsx`

- [ ] **Step 1: Scaffold**

```bash
cd services/frontend
npm create vite@latest . -- --template react-ts
npm install axios react-router-dom
```

- [ ] **Step 2: Create vite.config.ts** (proxy `/api` to `https://localhost:8443`)

- [ ] **Step 3: Commit**

```bash
git add services/frontend/
git commit -m "feat(frontend): scaffold Vite + React + TypeScript"
```

---

### Task 6.2: Auth Context + API Client

**Files:**
- Create: `services/frontend/src/api/client.ts`
- Create: `services/frontend/src/auth/AuthContext.tsx`
- Create: `services/frontend/src/auth/useAuth.ts`
- Create: `services/frontend/src/auth/ProtectedRoute.tsx`

- [ ] **Step 1: Create API client** with Axios interceptors: attach access token, auto-refresh on 401 (queue concurrent retries), redirect to `/login` on refresh failure.

- [ ] **Step 2: Create AuthContext** with: login, register, logout, hasPermission, hasRole. On mount, attempt silent refresh via `POST /api/auth/refresh`. Parse JWT payload client-side for user info.

- [ ] **Step 3: Create useAuth hook** and **ProtectedRoute** component (redirects to `/login` if no user, checks requiredRole/requiredPermission)

- [ ] **Step 4: Commit**

```bash
git add services/frontend/src/
git commit -m "feat(frontend): add auth context, API client with token refresh"
```

---

### Task 6.3: Login Page + Dashboard + Routing

**Files:**
- Create: `services/frontend/src/pages/LoginPage.tsx`
- Create: `services/frontend/src/pages/DashboardPage.tsx`
- Modify: `services/frontend/src/App.tsx`

- [ ] **Step 1: Create LoginPage** (username/password form, calls `login()`, navigates to `/` on success)

- [ ] **Step 2: Create DashboardPage** (shows user info, roles, permissions; buttons to test API endpoints including order CRUD; renders API responses)

- [ ] **Step 3: Wire App.tsx** with BrowserRouter, AuthProvider, Routes (`/login` → LoginPage, `/` → ProtectedRoute → DashboardPage)

- [ ] **Step 4: Commit**

```bash
git add services/frontend/
git commit -m "feat(frontend): add login page, dashboard, routing"
```

---

### Task 6.4: Frontend Dockerfile

**Files:**
- Create: `services/frontend/Dockerfile`

- [ ] **Step 1: Create multi-stage Dockerfile**

```dockerfile
FROM node:22-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM registry.suse.com/suse/nginx:1.21
COPY --from=builder /app/dist /usr/share/nginx/html
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD curl -f http://localhost/health || exit 1
CMD ["nginx", "-g", "daemon off;"]
```

- [ ] **Step 2: Commit**

```bash
git add services/frontend/Dockerfile
git commit -m "feat(frontend): add multi-stage Dockerfile"
```

---

## Chunk 7: Integration (Scripts, Nginx, Quadlet)

### Task 7.1: Update local-start.sh and local-stop.sh

**Files:**
- Modify: `scripts/local-start.sh`
- Modify: `scripts/local-stop.sh`
- Modify: `scripts/lib.sh`
- Modify: `configs/images.env`
- Modify: `configs/ha.conf`

- [ ] **Step 1: Update images.env**

```bash
SSL_PROXY_IMAGE=localhost/ssl-proxy:latest
FRONTEND_IMAGE=localhost/frontend:latest
BFF_IMAGE=localhost/bff:latest
API_AUTH_IMAGE=localhost/api-auth:latest
API_USER_IMAGE=localhost/api-user:latest
API_ORDER_IMAGE=localhost/api-order:latest
API_PRODUCT_IMAGE=localhost/api-product:latest
POSTGRES_IMAGE=docker.io/library/postgres:16-alpine
```

- [ ] **Step 2: Update ha.conf**

```bash
API_USER_REPLICAS=2
API_ORDER_REPLICAS=2
API_PRODUCT_REPLICAS=2
API_AUTH_REPLICAS=1
BFF_REPLICAS=2
FRONTEND_REPLICAS=2
```

- [ ] **Step 3: Update build_images()** — all Java services build with `-f services/<name>/Dockerfile` and context `$PROJECT_ROOT/services`

- [ ] **Step 4: Add start_spring_service() helper**

```bash
start_spring_service() {
    local service=$1 image=$2
    shift 2
    start_replicas "$service" "$image" 8080 \
        -e SPRING_PROFILES_ACTIVE=dev \
        -v "$PROJECT_ROOT/services/${service}/config/application-dev.yml:/app/config/application-dev.yml:ro" \
        -v "$PROJECT_ROOT/secrets/db-password.properties:/run/secrets/db-password.properties:ro" \
        -v "$PROJECT_ROOT/secrets/jwt-signing-key.properties:/run/secrets/jwt-signing-key.properties:ro" \
        "$@"
}
```

- [ ] **Step 5: Update main() start order**

```
start_postgres → start_auth → start_api_services → start_bff → start_frontend → start_ssl_proxy
```

- [ ] **Step 6: Update lib.sh** — `SCALABLE_SERVICES="api-user api-order api-product api-auth bff frontend"`

- [ ] **Step 7: Update local-stop.sh** (add postgres, replace bff references, add api-auth)

- [ ] **Step 8: Commit**

```bash
git add scripts/ configs/
git commit -m "feat(scripts): update local-start/stop for Java services with config mounts"
```

---

### Task 7.2: Update SSL Proxy Routes

**Files:**
- Modify: `services/ssl-proxy/conf.d/upstream.conf`
- Modify: `services/ssl-proxy/conf.d/routes.conf`

- [ ] **Step 1: Update upstream.conf** — replace `bff` upstream with `bff` pointing to `bff-1:8080`, `bff-2:8080` (name stays `bff`)

- [ ] **Step 2: Update routes.conf** — change `/api/` proxy_pass from `http://bff` (already correct if upstream name stays `bff`)

- [ ] **Step 3: Commit**

```bash
git add services/ssl-proxy/conf.d/
git commit -m "feat(ssl-proxy): update upstream config for Java BFF"
```

---

### Task 7.3: Update Quadlet Files

**Files:**
- Delete: `quadlet/bff@.container` (old Go BFF)
- Create: `quadlet/bff@.container` (new Java BFF)
- Create: `quadlet/api-auth@.container`
- Create: `quadlet/postgres.container`
- Modify: `quadlet/api-user@.container`
- Modify: `quadlet/api-order@.container`
- Modify: `quadlet/api-product@.container`
- Modify: `quadlet/frontend@.container`

All Java service Quadlet files need:
- `Volume=/opt/app/services/<service>/config/application-prod.yml:/app/config/application-prod.yml:ro`
- `Secret=db-password,type=mount,target=/run/secrets/db-password.properties`
- `Secret=jwt-signing-key,type=mount,target=/run/secrets/jwt-signing-key.properties`
- `Environment=SPRING_PROFILES_ACTIVE=prod`
- Health check: `wget -qO- http://localhost:8080/actuator/health || exit 1`

- [ ] **Step 1: Create postgres.container**
- [ ] **Step 2: Create api-auth@.container**
- [ ] **Step 3: Create bff@.container** (replaces old Go version)
- [ ] **Step 4: Update api-user@, api-order@, api-product@, frontend@**
- [ ] **Step 5: Commit**

```bash
git add quadlet/
git commit -m "feat(quadlet): update all container units for Java services"
```

---

### Task 7.4: End-to-End Verification

- [ ] **Step 1: Full stack start**

```bash
./scripts/local-stop.sh && ./scripts/local-start.sh
```

- [ ] **Step 2: Verify PostgreSQL**

```bash
podman exec postgres psql -U app_user -d microservices_dev -c 'SELECT 1'
```

- [ ] **Step 3: Verify Flyway**

```bash
podman logs api-auth-1 2>&1 | grep -i flyway
podman logs api-order-1 2>&1 | grep -i flyway
```

- [ ] **Step 4: Verify DB connection from stubs**

```bash
podman logs api-user-1 2>&1 | grep -i "HikariPool"
podman logs api-product-1 2>&1 | grep -i "HikariPool"
```

- [ ] **Step 5: Test auth flow**

```bash
# Register
curl -sk https://localhost:8443/api/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"username":"testuser","password":"testpass123","email":"test@example.com"}'

# Login
TOKEN=$(curl -sk https://localhost:8443/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"admin123"}' | jq -r .accessToken)

# Create order (internal, via BFF)
curl -sk https://localhost:8443/api/orders \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"customerName":"Test Customer","totalAmount":99.99}'

# List orders
curl -sk https://localhost:8443/api/orders \
  -H "Authorization: Bearer $TOKEN"

# Without token (expect 401)
curl -sk -o /dev/null -w "%{http_code}" https://localhost:8443/api/orders
```

- [ ] **Step 6: Test partner access to api-order**

```bash
# Generate partner JWT
PARTNER_TOKEN=$(./scripts/generate-jwt.sh partner-company-a 3600)

# Create order via partner path
curl -sk https://localhost:8443/partner/api/order/orders \
  -H "Authorization: Bearer $PARTNER_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"customerName":"Partner Customer","totalAmount":150.00}'
```

- [ ] **Step 7: Test React frontend**

Open `https://localhost:8443/` → login page → login with admin/admin123 → dashboard → test order CRUD buttons.

- [ ] **Step 8: Commit any fixes**

```bash
git add -A
git commit -m "fix: resolve integration issues from e2e verification"
```

---

## Summary

| Service | Type | Access | DB |
|---------|------|--------|-----|
| api-auth | Full (RBAC, JWT) | Internal via BFF | Yes (users, roles, permissions) |
| api-order | Full CRUD | Internal via BFF + Partner via ssl-proxy | Yes (orders) |
| api-user | Stub | Internal via BFF | Connection verified, no tables |
| api-product | Stub | Internal via BFF | Connection verified, no tables |
| bff | Gateway | All internal traffic | No |
| frontend | React SPA | Browser | No |
| ssl-proxy | Reverse proxy | Entry point | No |
| postgres | Database | Internal network | N/A |

**Container start order:** postgres → api-auth → api-order, api-user, api-product → bff → frontend → ssl-proxy

**Config files per service:**

| File | Location | Purpose |
|------|----------|---------|
| `application.yml` | Baked in JAR | Defaults |
| `application-dev.yml` | `services/<svc>/config/` | Dev overrides |
| `application-prod.yml` | `services/<svc>/config/` | Prod overrides |
| `db-password.properties` | `secrets/` or Podman Secret | DB password |
| `jwt-signing-key.properties` | `secrets/` or Podman Secret | JWT key (api-auth + bff only) |
