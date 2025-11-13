# Running Tests Locally

This repository has been set up with scripts to run the test suite locally, matching the GitHub Actions CI environment as closely as possible.

## Quick Start

### 1. Initial Setup (run once)

```bash
./setup-test-environment.sh
```

This will:
- Install dependencies (cpanminus, build tools, PCRE, zlib)
- Clone and build OpenSSL 3.2.1
- Clone and build LuaJIT 2.1
- Clone and build Nginx 1.25.3 with Lua modules
- Clone all required Lua libraries
- Set up Test::Nginx
- Build lua-cjson

The setup takes 10-30 minutes on first run, but subsequent runs are much faster as most artifacts are cached in `~/.cache/lua-resty-acme/`.

### 2. Run Tests

```bash
./run-tests-locally.sh
```

Or run a specific test file:

```bash
./run-tests-locally.sh t/e2e.t
```

## Configuration

You can override default versions by setting environment variables:

```bash
# Different Nginx/OpenSSL versions
NGINX_VERSION=1.21.4 OPENSSL_VERSION=3.0.12 ./setup-test-environment.sh

# More build parallelism
JOBS=8 ./setup-test-environment.sh

# Custom cache location
BASE_PATH=/tmp/acme-build ./setup-test-environment.sh
```

Available configurations from CI matrix:
- NGINX 1.25.3 + OpenSSL 3.2.1 (default)
- NGINX 1.21.4 + OpenSSL 3.0.12
- NGINX 1.25.3 + OpenSSL 3.1.4
- NGINX 1.21.4 + OpenSSL 1.1.1w (with older Lua modules)

## Docker Services

The test runner automatically starts these Docker services:
- Pebble (ACME server) on ports 14000, 15000
- Challenge test server on port 8055
- Consul on port 8500
- Vault on ports 8200, 8210
- etcd on ports 2379, 2380, 4001
- Redis (2 instances) on ports 6379, 6380

To view service logs:
```bash
cd t/fixtures && docker compose logs
```

To restart services:
```bash
cd t/fixtures && docker compose down && docker compose up -d
```

## Troubleshooting

### Services not starting

Check Docker services status:
```bash
cd t/fixtures && docker compose ps
```

View logs for a specific service:
```bash
cd t/fixtures && docker compose logs pebble
```

### Tests failing

Tests should pass locally just as they do in CI. If you see test failures, check:
- Docker services are running: `cd t/fixtures && docker compose ps`
- All services are healthy (especially vault, consul, etcd)
- No port conflicts with existing services

### Clean rebuild

To force a complete rebuild:
```bash
rm -rf ~/.cache/lua-resty-acme
./setup-test-environment.sh
```

## File Locations

- Built artifacts: `~/.cache/lua-resty-acme/`
- OpenSSL: `~/.cache/lua-resty-acme/ssl/`
- LuaJIT: `~/.cache/lua-resty-acme/luajit21/`
- Nginx: `~/.cache/lua-resty-acme/work/nginx/`
- Test environment config: `~/.cache/lua-resty-acme/test-env.conf`
