#!/bin/bash

set -e

# Configuration - you can override these by passing them as environment variables
# Example: NGINX_VERSION=1.25.3 OPENSSL_VERSION=3.2.1 ./setup-test-environment.sh

NGINX_VERSION="${NGINX_VERSION:-1.25.3}"
OPENSSL_VERSION="${OPENSSL_VERSION:-3.2.1}"
LUA_NGINX_MODULE="${LUA_NGINX_MODULE:-v0.10.26}"
STREAM_LUA_NGINX_MODULE="${STREAM_LUA_NGINX_MODULE:-v0.0.14}"
LUA_RESTY_CORE="${LUA_RESTY_CORE:-v0.1.28}"

# Other matrix configurations available:
# NGINX_VERSION=1.21.4 OPENSSL_VERSION=3.0.12
# NGINX_VERSION=1.25.3 OPENSSL_VERSION=3.1.4
# NGINX_VERSION=1.21.4 OPENSSL_VERSION=1.1.1w LUA_NGINX_MODULE=v0.10.21 STREAM_LUA_NGINX_MODULE=v0.0.11 LUA_RESTY_CORE=v0.1.23

# Environment variables
export JOBS="${JOBS:-3}"
export SH=bash
export NGX_BUILD_JOBS="${NGX_BUILD_JOBS:-3}"
export BASE_PATH="${BASE_PATH:-$HOME/.cache/lua-resty-acme}"
export LUAJIT_PREFIX="$BASE_PATH/luajit21"
export LUAJIT_LIB="$LUAJIT_PREFIX/lib"
export LUAJIT_INC="$LUAJIT_PREFIX/include/luajit-2.1"
export LUA_INCLUDE_DIR="$LUAJIT_INC"
export OPENSSL_PREFIX="$BASE_PATH/ssl"
export OPENSSL_LIB="$OPENSSL_PREFIX/lib"
export OPENSSL_INC="$OPENSSL_PREFIX/include"
export TEST_NGINX_SLEEP=0.005
export TEST_NGINX_RANDOMIZE=1
export LUACHECK_VER=0.21.1
export CC=gcc
export NGX_BUILD_CC=gcc
export NGINX_CC_OPTS=""
export LUAJIT_CC_OPTS=""

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BUILD_DIR="$BASE_PATH/build"

echo "======================================"
echo "Lua-Resty-ACME Test Environment Setup"
echo "======================================"
echo "Configuration:"
echo "  NGINX_VERSION: $NGINX_VERSION"
echo "  OPENSSL_VERSION: $OPENSSL_VERSION"
echo "  LUA_NGINX_MODULE: $LUA_NGINX_MODULE"
echo "  STREAM_LUA_NGINX_MODULE: $STREAM_LUA_NGINX_MODULE"
echo "  LUA_RESTY_CORE: $LUA_RESTY_CORE"
echo "  BASE_PATH: $BASE_PATH"
echo "======================================"

# Create directories
mkdir -p "$OPENSSL_PREFIX" "$LUAJIT_PREFIX" "$BUILD_DIR"

# Check dependencies
echo ""
echo "Step 1: Checking dependencies..."
if ! command -v cpanm &> /dev/null; then
    echo "Installing cpanminus and build dependencies..."
    sudo apt-get update -qq
    sudo apt-get install -qq -y cpanminus axel ca-certificates build-essential libpcre3-dev zlib1g-dev
else
    echo "Checking for build dependencies..."
    sudo apt-get install -qq -y build-essential libpcre3-dev zlib1g-dev 2>/dev/null || true
fi

# Check for Docker and Docker Compose
if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker is not installed. Please install Docker first."
    exit 1
fi

if ! docker compose version &> /dev/null; then
    echo "ERROR: Docker Compose is not available. Please install Docker Compose."
    exit 1
fi

# Install Test::Nginx if not cached
echo ""
echo "Step 2: Setting up Perl Test::Nginx..."
pushd "$BASE_PATH" > /dev/null
if [ ! -e perl ]; then
    echo "Installing Test::Nginx..."
    sudo cpanm --notest Test::Nginx > build.log 2>&1 || (cat build.log && exit 1)
    cp -r /usr/local/share/perl/ .
else
    echo "Test::Nginx already cached, copying to system..."
    sudo cp -r perl /usr/local/share
fi
popd > /dev/null

# Clone build tools
echo ""
echo "Step 3: Cloning build tools and dependencies..."
cd "$BASE_PATH/.."

if [ ! -d "openresty" ]; then
    echo "Cloning openresty..."
    git clone https://github.com/openresty/openresty.git ./openresty
fi

if [ ! -d "nginx-devel-utils" ]; then
    echo "Cloning nginx-devel-utils..."
    git clone https://github.com/openresty/nginx-devel-utils.git
fi

if [ ! -d "ndk-nginx-module" ]; then
    echo "Cloning ndk-nginx-module..."
    git clone https://github.com/simpl/ngx_devel_kit.git ./ndk-nginx-module
fi

if [ ! -d "lua-nginx-module" ]; then
    echo "Cloning lua-nginx-module..."
    git clone https://github.com/openresty/lua-nginx-module.git ./lua-nginx-module -b "$LUA_NGINX_MODULE"
else
    echo "Checking out lua-nginx-module $LUA_NGINX_MODULE..."
    cd lua-nginx-module && git fetch && git checkout "$LUA_NGINX_MODULE" && cd ..
fi

if [ ! -d "stream-lua-nginx-module" ]; then
    echo "Cloning stream-lua-nginx-module..."
    git clone https://github.com/openresty/stream-lua-nginx-module.git ./stream-lua-nginx-module -b "$STREAM_LUA_NGINX_MODULE"
else
    echo "Checking out stream-lua-nginx-module $STREAM_LUA_NGINX_MODULE..."
    cd stream-lua-nginx-module && git fetch && git checkout "$STREAM_LUA_NGINX_MODULE" && cd ..
fi

if [ ! -d "no-pool-nginx" ]; then
    echo "Cloning no-pool-nginx..."
    git clone https://github.com/openresty/no-pool-nginx.git ./no-pool-nginx
fi

# Clone Lua libraries
echo ""
echo "Step 4: Cloning Lua libraries..."
cd "$BASE_PATH/.."
mkdir -p lib

if [ ! -d "lua-resty-core" ]; then
    echo "Cloning lua-resty-core..."
    git clone https://github.com/openresty/lua-resty-core.git ./lua-resty-core -b "$LUA_RESTY_CORE"
else
    echo "Checking out lua-resty-core $LUA_RESTY_CORE..."
    cd lua-resty-core && git fetch && git checkout "$LUA_RESTY_CORE" && cd ..
fi

if [ ! -d "lua-resty-lrucache" ]; then
    git clone https://github.com/openresty/lua-resty-lrucache.git ./lua-resty-lrucache
fi

if [ ! -d "lua-resty-redis" ]; then
    git clone https://github.com/openresty/lua-resty-redis.git ./lua-resty-redis
fi

if [ ! -d "lua-resty-http" ]; then
    git clone -b v0.15 https://github.com/ledgetech/lua-resty-http ./lua-resty-http
fi

if [ ! -d "lua-resty-openssl" ]; then
    git clone https://github.com/fffonion/lua-resty-openssl ./lua-resty-openssl
fi

if [ ! -d "luafilesystem-ffi" ]; then
    git clone -b 0.3.0 https://github.com/spacewander/luafilesystem ./luafilesystem-ffi
fi

if [ ! -d "lua-resty-hmac" ]; then
    git clone https://github.com/jkeys089/lua-resty-hmac ./lua-resty-hmac
    pushd lua-resty-hmac > /dev/null && git checkout 79a4929 && popd > /dev/null
fi

if [ ! -d "lua-typeof" ]; then
    git clone https://github.com/iresty/lua-typeof ./lua-typeof
fi

if [ ! -d "lua-resty-etcd" ]; then
    git clone https://github.com/api7/lua-resty-etcd ./lua-resty-etcd -b v1.4.4
fi

echo "Copying Lua libraries..."
cp -r lua-resty-lrucache/lib/* lib/ 2>/dev/null || true
cp -r lua-resty-redis/lib/* lib/ 2>/dev/null || true
cp -r lua-resty-http/lib/* lib/ 2>/dev/null || true
cp -r lua-resty-openssl/lib/* lib/ 2>/dev/null || true
cp -r lua-typeof/lib/* lib/ 2>/dev/null || true
cp -r lua-resty-etcd/lib/* lib/ 2>/dev/null || true
cp luafilesystem-ffi/lfs_ffi.lua lib/ 2>/dev/null || true

echo "Library structure:"
find lib -type f | head -20

# Copy lib directory to repository parent (where tests expect it)
echo "Copying libraries to repository parent directory..."
sudo rm -rf "$SCRIPT_DIR/../lib"
sudo cp -r lib "$SCRIPT_DIR/../lib"
sudo chown -R $USER "$SCRIPT_DIR/../lib" 2>/dev/null || true

# Also copy lua-resty-core to repository parent (tests look for it there)
echo "Copying lua-resty-core to repository parent directory..."
sudo rm -rf "$SCRIPT_DIR/../lua-resty-core"
sudo cp -r lua-resty-core "$SCRIPT_DIR/../lua-resty-core"
sudo chown -R $USER "$SCRIPT_DIR/../lua-resty-core" 2>/dev/null || true

# Build OpenSSL
echo ""
echo "Step 5: Building OpenSSL $OPENSSL_VERSION..."
cd "$BUILD_DIR"
if [ ! -e "$OPENSSL_PREFIX/include" ]; then
    echo "Downloading OpenSSL..."
    if [ ! -d "openssl-$OPENSSL_VERSION" ]; then
        (wget "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz" -qO - || \
         wget "https://openssl.org/source/old/1.1.1/openssl-$OPENSSL_VERSION.tar.gz" -qO -) | tar zxf -
    fi

    pushd "openssl-$OPENSSL_VERSION" > /dev/null
    echo "Configuring OpenSSL..."
    ./config shared -d --prefix="$OPENSSL_PREFIX" -DPURIFY > build.log 2>&1 || (cat build.log && exit 1)
    echo "Building OpenSSL (this may take a while)..."
    make -j"$JOBS" > build.log 2>&1 || (cat build.log && exit 1)
    echo "Installing OpenSSL..."
    make install_sw > build.log 2>&1 || (cat build.log && exit 1)
    popd > /dev/null

    echo "Copying SSL certificates..."
    mkdir -p "$OPENSSL_PREFIX/certs/"
    sudo cp -r /etc/ssl/certs/* "$OPENSSL_PREFIX/certs/" 2>/dev/null || true
else
    echo "OpenSSL already built, skipping..."
fi

# Update OPENSSL_LIB if it was installed to lib64 instead of lib
if [ -d "$OPENSSL_PREFIX/lib64" ] && [ ! -d "$OPENSSL_PREFIX/lib" ]; then
    echo "Detected OpenSSL in lib64, updating OPENSSL_LIB..."
    export OPENSSL_LIB="$OPENSSL_PREFIX/lib64"
fi

# Build LuaJIT
echo ""
echo "Step 6: Building LuaJIT..."
cd "$LUAJIT_PREFIX"
if [ ! -e "$LUAJIT_PREFIX/bin/luajit" ]; then
    if [ ! -e luajit2 ]; then
        echo "Cloning LuaJIT..."
        git clone -b v2.1-agentzh https://github.com/openresty/luajit2.git
    fi

    cd luajit2
    echo "Building LuaJIT (this may take a while)..."
    make -j"$JOBS" CCDEBUG=-g Q= PREFIX="$LUAJIT_PREFIX" CC="$CC" \
        XCFLAGS="-DLUA_USE_APICHECK -DLUA_USE_ASSERT -DLUAJIT_ENABLE_LUA52COMPAT $LUAJIT_CC_OPTS" \
        > build.log 2>&1 || (cat build.log && exit 1)
    echo "Installing LuaJIT..."
    make install PREFIX="$LUAJIT_PREFIX" > build.log 2>&1 || (cat build.log && exit 1)
else
    echo "LuaJIT already built, skipping..."
fi

# Build lua-cjson
echo ""
echo "Step 7: Building lua-cjson..."
cd "$BUILD_DIR"
if [ ! -e lua-cjson ]; then
    echo "Cloning lua-cjson..."
    git clone https://github.com/openresty/lua-cjson.git ./lua-cjson
fi

pushd lua-cjson > /dev/null
if [ ! -e "/usr/local/lib/lua/5.1/cjson.so" ] && [ ! -e "$LUAJIT_PREFIX/lib/lua/5.1/cjson.so" ]; then
    echo "Building and installing lua-cjson..."
    make > /dev/null 2>&1 || true
    sudo make install > /dev/null 2>&1 || true
else
    echo "lua-cjson already installed, skipping..."
fi
popd > /dev/null

# Build Nginx
echo ""
echo "Step 8: Building Nginx $NGINX_VERSION..."
export PATH="$BASE_PATH/work/nginx/sbin:$BASE_PATH/../nginx-devel-utils:$PATH"
export LD_LIBRARY_PATH="$LUAJIT_LIB:$LD_LIBRARY_PATH"

cd "$BASE_PATH"
if [ ! -e work/nginx/sbin/nginx ]; then
    echo "Building Nginx with modules (this may take a while)..."
    ngx-build "$NGINX_VERSION" \
        --add-module=../ndk-nginx-module \
        --add-module=../lua-nginx-module \
        --add-module=../stream-lua-nginx-module \
        --with-http_ssl_module \
        --with-stream \
        --with-stream_ssl_module \
        --with-stream_ssl_preread_module \
	--with-threads \
        --with-cc-opt="-I$OPENSSL_INC $NGINX_CC_OPTS" \
        --with-ld-opt="-L$OPENSSL_LIB -Wl,-rpath,$OPENSSL_LIB" \
        --with-debug \
        > build.log 2>&1 || (cat build.log && exit 1)
else
    echo "Nginx already built, skipping..."
fi

echo ""
echo "Nginx version:"
nginx -V

echo ""
echo "Nginx library dependencies:"
ldd "$(which nginx)" | grep -E 'luajit|ssl|pcre' || true

# Start Redis services (if not already running)
echo ""
echo "Step 9: Setting up Redis services..."
if ! docker ps | grep -q redis-test; then
    echo "Starting Redis on port 6379..."
    docker run --rm -d --name redis-test -p 6379:6379 \
        --health-cmd "redis-cli ping" \
        --health-interval 10s \
        --health-timeout 5s \
        --health-retries 5 \
        redis:latest || echo "Redis on 6379 already exists (stopped or failed to start)"
else
    echo "Redis on 6379 already running"
fi

if ! docker ps | grep -q redis-auth-test; then
    echo "Starting Redis with auth on port 6380..."
    docker run --rm -d --name redis-auth-test -p 6380:6379 \
        --health-cmd "redis-cli ping" \
        --health-interval 10s \
        --health-timeout 5s \
        --health-retries 5 \
        -e REDIS_ARGS="--requirepass passdefault" \
        redis/redis-stack-server:latest || echo "Redis on 6380 already exists (stopped or failed to start)"
else
    echo "Redis on 6380 already running"
fi

# Save configuration for test runner
echo ""
echo "Saving environment configuration..."
cat > "$BASE_PATH/test-env.conf" <<EOF
export JOBS="$JOBS"
export SH="$SH"
export NGX_BUILD_JOBS="$NGX_BUILD_JOBS"
export BASE_PATH="$BASE_PATH"
export LUAJIT_PREFIX="$LUAJIT_PREFIX"
export LUAJIT_LIB="$LUAJIT_LIB"
export LUAJIT_INC="$LUAJIT_INC"
export LUA_INCLUDE_DIR="$LUA_INCLUDE_DIR"
export OPENSSL_PREFIX="$OPENSSL_PREFIX"
export OPENSSL_LIB="$OPENSSL_LIB"
export OPENSSL_INC="$OPENSSL_INC"
export TEST_NGINX_SLEEP="$TEST_NGINX_SLEEP"
export TEST_NGINX_RANDOMIZE="$TEST_NGINX_RANDOMIZE"
export CC="$CC"
export NGX_BUILD_CC="$NGX_BUILD_CC"
export PATH="$BASE_PATH/work/nginx/sbin:$BASE_PATH/../nginx-devel-utils:\$PATH"
export LD_LIBRARY_PATH="$LUAJIT_LIB:\$LD_LIBRARY_PATH"
EOF

# Prepare environment (start services)
echo ""
echo "Preparing environment (starting Docker services)..."
bash "$SCRIPT_DIR/t/fixtures/prepare_env.sh"

echo ""
echo "======================================"
echo "Setup completed successfully!"
echo "======================================"
echo ""
echo "You can now run tests with: ./run-tests-locally.sh"
echo ""
echo "Configuration saved to: $BASE_PATH/test-env.conf"
