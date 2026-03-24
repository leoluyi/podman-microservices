# Config Directory Restructure Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure `configs/` into `shared/`, `dev/`, `prod/` subdirectories so the dev/prod boundary is immediately obvious from the directory layout.

**Architecture:** Move shared configs (ha.conf, ssl-proxy/, postgres/, frontend/, logrotate.d/) under `configs/shared/`. Move `images.env` to `configs/dev/images.env`, create `configs/prod/images.env`. Extract hardcoded dev secrets from `local-start.sh` into `configs/dev/secrets.env`. Update `setup.sh` to read `configs/prod/images.env` and sed-replace `Image=` lines in `.container` files during deployment. Add `configs/dev/secrets.env` to `.gitignore` and provide an example file.

**Tech Stack:** Bash, Podman Quadlet, systemd

---

## File Structure

### New directory layout

```
configs/
├── shared/
│   ├── ha.conf                    # (moved) replica counts — dev + prod
│   ├── ssl-proxy/                 # (moved) nginx configs — dev + prod
│   │   ├── nginx.conf
│   │   └── conf.d/
│   ├── postgres/                  # (moved) init-db.sh — dev + prod
│   │   └── init-db.sh
│   ├── frontend/                  # (moved) nginx.conf — dev + prod
│   │   └── nginx.conf
│   └── logrotate.d/               # (moved) — prod only but shared infra
│       └── ssl-proxy
├── dev/
│   ├── images.env                 # (moved from configs/images.env)
│   └── secrets.env.example        # (new) template for dev secrets
└── prod/
    └── images.env                 # (new) prod image tags
```

### Files to modify

| File | Change |
|---|---|
| `scripts/lib.sh` | `HA_CONF` path → `configs/shared/ha.conf` |
| `scripts/local-start.sh` | source `configs/dev/images.env` + `configs/dev/secrets.env`; update volume mount paths to `configs/shared/` |
| `scripts/deploy/setup.sh` | update `configs/` paths → `configs/shared/`; source `configs/prod/images.env` and sed-replace `.container` Image= lines |
| `scripts/deploy/scale-service.sh` | no change (uses `$HA_CONF` from lib.sh) |
| `scripts/deploy/status.sh` | no change (uses functions from lib.sh) |
| `quadlet/*.container` | change `Image=` values to `__IMAGE_PLACEHOLDER__` pattern |
| `.gitignore` | add `configs/dev/secrets.env` |

---

## Chunk 1: Move shared configs and update references

### Task 1: Create new directory structure and move shared configs

**Files:**
- Create: `configs/shared/` (directory)
- Create: `configs/dev/` (directory)
- Create: `configs/prod/` (directory)
- Move: `configs/ha.conf` → `configs/shared/ha.conf`
- Move: `configs/ssl-proxy/` → `configs/shared/ssl-proxy/`
- Move: `configs/postgres/` → `configs/shared/postgres/`
- Move: `configs/frontend/` → `configs/shared/frontend/`
- Move: `configs/logrotate.d/` → `configs/shared/logrotate.d/`

- [ ] **Step 1: Create directories and move files**

```bash
cd configs
mkdir -p shared dev prod
git mv ha.conf shared/
git mv ssl-proxy shared/
git mv postgres shared/
git mv frontend shared/
git mv logrotate.d shared/
```

- [ ] **Step 2: Commit the move**

```bash
git add -A configs/
git commit -m "refactor(configs): move shared configs under configs/shared/"
```

### Task 2: Update lib.sh HA_CONF path

**Files:**
- Modify: `scripts/lib.sh:25`

- [ ] **Step 1: Update HA_CONF path**

Change line 25 from:
```bash
HA_CONF="$PROJECT_ROOT/configs/ha.conf"
```
to:
```bash
HA_CONF="$PROJECT_ROOT/configs/shared/ha.conf"
```

- [ ] **Step 2: Commit**

```bash
git add scripts/lib.sh
git commit -m "refactor(scripts): update HA_CONF to configs/shared/ha.conf"
```

### Task 3: Update local-start.sh shared config paths

**Files:**
- Modify: `scripts/local-start.sh:174,180,239,301-302`

- [ ] **Step 1: Update all volume mount paths from `configs/` to `configs/shared/`**

Update these lines:
- Line 174: `configs/postgres/init-db.sh` → `configs/shared/postgres/init-db.sh`
- Line 180: `configs/ssl-proxy` → `configs/shared/ssl-proxy`
- Line 239: `configs/postgres/init-db.sh` → `configs/shared/postgres/init-db.sh`
- Line 301: `configs/ssl-proxy/nginx.conf` → `configs/shared/ssl-proxy/nginx.conf`
- Line 302: `configs/ssl-proxy/conf.d` → `configs/shared/ssl-proxy/conf.d`

- [ ] **Step 2: Commit**

```bash
git add scripts/local-start.sh
git commit -m "refactor(local-start): update config paths to configs/shared/"
```

### Task 4: Update deploy/setup.sh shared config paths

**Files:**
- Modify: `scripts/deploy/setup.sh:62,92,95,103`

- [ ] **Step 1: Update all config copy paths**

- Line 62: `mkdir -p /opt/app/configs/ssl-proxy/conf.d` → no change (target path on server)
- Line 92: `configs/ssl-proxy/` → `configs/shared/ssl-proxy/`
- Line 95: `configs/frontend/nginx.conf` → `configs/shared/frontend/nginx.conf`
- Line 103: `configs/logrotate.d/ssl-proxy` → `configs/shared/logrotate.d/ssl-proxy`

- [ ] **Step 2: Commit**

```bash
git add scripts/deploy/setup.sh
git commit -m "refactor(setup): update config paths to configs/shared/"
```

### Task 5: Verify references — grep for stale paths

- [ ] **Step 1: Search for any remaining `configs/ssl-proxy`, `configs/postgres`, `configs/ha.conf` etc.**

```bash
grep -rn 'configs/ssl-proxy\|configs/postgres\|configs/ha\.conf\|configs/frontend\|configs/logrotate' scripts/ quadlet/ --include='*.sh' --include='*.container'
```

Expected: No matches (all should reference `configs/shared/` now), except for deploy target paths like `/opt/app/configs/` which are server-side and correct.

- [ ] **Step 2: Fix any remaining stale references found, then commit**

---

## Chunk 2: Separate dev and prod image configs

### Task 6: Move images.env to dev and create prod version

**Files:**
- Move: `configs/images.env` → `configs/dev/images.env`
- Create: `configs/prod/images.env`

- [ ] **Step 1: Move dev images.env**

```bash
git mv configs/images.env configs/dev/images.env
```

- [ ] **Step 2: Create prod/images.env**

```bash
cat > configs/prod/images.env << 'ENVEOF'
# ============================================================================
# Production container image tags
# ============================================================================
# Used by: scripts/deploy/setup.sh (replaces Image= in Quadlet .container files)
# Update these when deploying a new version to production.

# SSL Termination Proxy
SSL_PROXY_IMAGE=localhost/ssl-proxy:latest

# Frontend
FRONTEND_IMAGE=localhost/frontend:latest

# BFF Gateway
BFF_IMAGE=localhost/bff:latest

# Database
POSTGRES_IMAGE=docker.io/library/postgres:16-alpine

# Auth Service
API_AUTH_IMAGE=localhost/api-auth:latest

# Backend APIs
API_USER_IMAGE=localhost/api-user:latest
API_ORDER_IMAGE=localhost/api-order:latest
API_PRODUCT_IMAGE=localhost/api-product:latest
ENVEOF
```

- [ ] **Step 3: Update local-start.sh source path**

Change line 15-16 from:
```bash
# shellcheck source=../configs/images.env
source "$PROJECT_ROOT/configs/images.env"
```
to:
```bash
# shellcheck source=../configs/dev/images.env
source "$PROJECT_ROOT/configs/dev/images.env"
```

- [ ] **Step 4: Commit**

```bash
git add configs/dev/images.env configs/prod/images.env scripts/local-start.sh
git commit -m "refactor(configs): split images.env into dev/ and prod/"
```

### Task 7: Update Quadlet .container files to use placeholders

**Files:**
- Modify: all 8 `quadlet/*.container` files

- [ ] **Step 1: Replace hardcoded Image= with placeholder pattern**

For each `.container` file, change the `Image=` line to a `__PLACEHOLDER__` that `setup.sh` will replace:

| File | Before | After |
|---|---|---|
| `api-user@.container:7` | `Image=localhost/api-user:latest` | `Image=__API_USER_IMAGE__` |
| `api-order@.container:7` | `Image=localhost/api-order:latest` | `Image=__API_ORDER_IMAGE__` |
| `api-product@.container:7` | `Image=localhost/api-product:latest` | `Image=__API_PRODUCT_IMAGE__` |
| `api-auth@.container:7` | `Image=localhost/api-auth:latest` | `Image=__API_AUTH_IMAGE__` |
| `bff@.container:7` | `Image=localhost/bff:latest` | `Image=__BFF_IMAGE__` |
| `frontend@.container:10` | `Image=localhost/frontend:latest` | `Image=__FRONTEND_IMAGE__` |
| `ssl-proxy.container:12` | `Image=localhost/ssl-proxy:latest` | `Image=__SSL_PROXY_IMAGE__` |
| `postgres.container:7` | `Image=docker.io/library/postgres:16-alpine` | `Image=__POSTGRES_IMAGE__` |

- [ ] **Step 2: Commit**

```bash
git add quadlet/*.container
git commit -m "refactor(quadlet): replace hardcoded Image= with placeholders"
```

### Task 8: Update setup.sh to source prod images and replace placeholders

**Files:**
- Modify: `scripts/deploy/setup.sh` (section 7, around line 182-189)

- [ ] **Step 1: Add image substitution logic to setup.sh**

Insert before the existing Quadlet copy block (line 184):

```bash
# ============================================================================
# 7. 部署 Quadlet 配置
# ============================================================================
info "部署 Quadlet 配置..."

# Source production image tags
# shellcheck source=../../configs/prod/images.env
source "$PROJECT_ROOT/configs/prod/images.env"

# Copy .container and .network files, replacing image placeholders
for f in quadlet/*.container quadlet/*.network; do
    [ -f "$f" ] || continue
    dest="$HOME/.config/containers/systemd/$(basename "$f")"
    sed \
        -e "s|__SSL_PROXY_IMAGE__|${SSL_PROXY_IMAGE}|g" \
        -e "s|__FRONTEND_IMAGE__|${FRONTEND_IMAGE}|g" \
        -e "s|__BFF_IMAGE__|${BFF_IMAGE}|g" \
        -e "s|__POSTGRES_IMAGE__|${POSTGRES_IMAGE}|g" \
        -e "s|__API_AUTH_IMAGE__|${API_AUTH_IMAGE}|g" \
        -e "s|__API_USER_IMAGE__|${API_USER_IMAGE}|g" \
        -e "s|__API_ORDER_IMAGE__|${API_ORDER_IMAGE}|g" \
        -e "s|__API_PRODUCT_IMAGE__|${API_PRODUCT_IMAGE}|g" \
        "$f" > "$dest"
done

success "Quadlet 配置已部署（Image 已替換為 prod 版本）"
```

This replaces the old block:
```bash
# 複製所有 .container 和 .network 檔案
cp quadlet/*.{container,network} ~/.config/containers/systemd/ 2>/dev/null || true
```

- [ ] **Step 2: Commit**

```bash
git add scripts/deploy/setup.sh
git commit -m "feat(setup): source prod/images.env and replace Quadlet image placeholders"
```

---

## Chunk 3: Extract dev secrets from local-start.sh

### Task 9: Create dev secrets.env.example and .gitignore entry

**Files:**
- Create: `configs/dev/secrets.env.example`
- Create: `configs/dev/secrets.env` (local, gitignored)
- Modify: `.gitignore`

- [ ] **Step 1: Create secrets.env.example**

```bash
cat > configs/dev/secrets.env.example << 'ENVEOF'
# ============================================================================
# Dev-only secrets — DO NOT USE IN PRODUCTION
# ============================================================================
# Copy to secrets.env:  cp secrets.env.example secrets.env
# Used by: scripts/local-start.sh

# JWT Partner secrets (ssl-proxy)
JWT_SECRET_PARTNER_A=dev-secret-partner-a-for-testing-only-32chars
JWT_SECRET_PARTNER_B=dev-secret-partner-b-for-testing-only-32chars
JWT_SECRET_PARTNER_C=dev-secret-partner-c-for-testing-only-32chars
DEBUG_PARTNERS=true
ENVEOF
```

- [ ] **Step 2: Copy example as default dev file**

```bash
cp configs/dev/secrets.env.example configs/dev/secrets.env
```

- [ ] **Step 3: Add to .gitignore**

Append:
```
configs/dev/secrets.env
```

- [ ] **Step 4: Commit**

```bash
git add configs/dev/secrets.env.example .gitignore
git commit -m "feat(configs): add dev/secrets.env.example with gitignored secrets.env"
```

### Task 10: Update local-start.sh to source dev secrets

**Files:**
- Modify: `scripts/local-start.sh:16,304-307`

- [ ] **Step 1: Add secrets.env source near the top (after images.env source)**

After line 16, add:
```bash
# shellcheck source=../configs/dev/secrets.env
if [ -f "$PROJECT_ROOT/configs/dev/secrets.env" ]; then
    source "$PROJECT_ROOT/configs/dev/secrets.env"
else
    error "Missing configs/dev/secrets.env — copy from secrets.env.example"
    exit 1
fi
```

- [ ] **Step 2: Replace hardcoded secrets in start_ssl_proxy()**

Change lines 304-307 from:
```bash
            -e JWT_SECRET_PARTNER_A="dev-secret-partner-a-for-testing-only-32chars" \
            -e JWT_SECRET_PARTNER_B="dev-secret-partner-b-for-testing-only-32chars" \
            -e JWT_SECRET_PARTNER_C="dev-secret-partner-c-for-testing-only-32chars" \
            -e DEBUG_PARTNERS=true \
```
to:
```bash
            -e JWT_SECRET_PARTNER_A="${JWT_SECRET_PARTNER_A}" \
            -e JWT_SECRET_PARTNER_B="${JWT_SECRET_PARTNER_B}" \
            -e JWT_SECRET_PARTNER_C="${JWT_SECRET_PARTNER_C}" \
            -e DEBUG_PARTNERS="${DEBUG_PARTNERS:-true}" \
```

- [ ] **Step 3: Commit**

```bash
git add scripts/local-start.sh
git commit -m "refactor(local-start): source dev secrets from configs/dev/secrets.env"
```

---

## Chunk 4: Update dev/images.env header and final verification

### Task 11: Update dev/images.env header comment

**Files:**
- Modify: `configs/dev/images.env:1-5`

- [ ] **Step 1: Update header to reflect new location and purpose**

Replace lines 1-5:
```bash
# ============================================================================
# Dev container image tags
# ============================================================================
# Used by: scripts/local-start.sh (podman run, no systemd)
# Prod equivalent: configs/prod/images.env
```

- [ ] **Step 2: Commit**

```bash
git add configs/dev/images.env
git commit -m "docs(configs): update dev/images.env header comment"
```

### Task 12: End-to-end verification

- [ ] **Step 1: Verify no stale `configs/` references remain**

```bash
# Should return zero matches (excluding configs/shared/, configs/dev/, configs/prod/, /opt/app/configs/)
grep -rn '"$PROJECT_ROOT/configs/[^sdp]' scripts/ --include='*.sh'
grep -rn 'configs/ssl-proxy\|configs/postgres\|configs/ha\.conf\|configs/frontend\|configs/logrotate' scripts/ quadlet/ --include='*.sh' --include='*.container'
```

Expected: No matches.

- [ ] **Step 2: Verify Quadlet placeholders are consistent with prod/images.env**

```bash
# Extract placeholder names from .container files
grep -h '__.*__' quadlet/*.container | sed 's/.*__\(.*\)__.*/\1/' | sort

# Extract variable names from prod/images.env
grep -v '^#' configs/prod/images.env | grep '=' | cut -d= -f1 | sort

# Both lists should match exactly
```

- [ ] **Step 3: Verify local-start.sh sources correct files**

```bash
grep 'source.*configs/' scripts/local-start.sh
```

Expected:
```
source "$PROJECT_ROOT/configs/dev/images.env"
source "$PROJECT_ROOT/configs/dev/secrets.env"
```

- [ ] **Step 4: Verify setup.sh sources prod images**

```bash
grep 'source.*configs/' scripts/deploy/setup.sh
```

Expected:
```
source "$PROJECT_ROOT/configs/prod/images.env"
```

- [ ] **Step 5: Shellcheck scripts (if available)**

```bash
shellcheck scripts/local-start.sh scripts/deploy/setup.sh scripts/lib.sh 2>/dev/null || true
```

- [ ] **Step 6: Final commit (if any fixups needed)**

```bash
git add -A
git commit -m "refactor(configs): complete config directory restructure"
```
