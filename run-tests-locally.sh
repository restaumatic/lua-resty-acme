#!/bin/bash

set -eo pipefail

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BASE_PATH="${BASE_PATH:-$HOME/.cache/lua-resty-acme}"

# Check if setup was completed
if [ ! -f "$BASE_PATH/test-env.conf" ]; then
    echo "ERROR: Test environment not set up."
    echo "Please run ./setup-test-environment.sh first"
    exit 1
fi

# Load environment configuration
echo "Loading test environment configuration..."
source "$BASE_PATH/test-env.conf"

# Export HOST_IP for docker-compose (required by etcd)
export HOST_IP="$(hostname -I | awk '{print $1}')"

echo "======================================"
echo "Lua-Resty-ACME Test Runner"
echo "======================================"
echo "HOST_IP: $HOST_IP"
echo "BASE_PATH: $BASE_PATH"
echo "======================================"

# Check for Docker and Docker Compose
if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker is not installed. Please install Docker first."
    exit 1
fi

if ! docker compose version &> /dev/null; then
    echo "ERROR: Docker Compose is not available. Please install Docker Compose."
    exit 1
fi

echo ""
echo "Step 2: Cleaning up old nginx processes..."
pkill -9 nginx || echo "no nginx processes found"


echo "Step 2.5: Cleaning redis..."
echo -ne "FLUSHALL\r\n" | nc -q1 localhost 6379
echo -ne "AUTH passdefault\r\nFLUSHALL\r\n" | nc -q1 localhost 6380

# Run tests
echo ""
echo "======================================"
echo "Step 3: Running Tests"
echo "======================================"
cd "$SCRIPT_DIR"

# Set up PATH and LD_LIBRARY_PATH for tests
# Update OPENSSL_LIB if it's in lib64
if [ -d "$OPENSSL_PREFIX/lib64" ] && [ ! -d "$OPENSSL_PREFIX/lib" ]; then
    export OPENSSL_LIB="$OPENSSL_PREFIX/lib64"
fi

export PATH="$BASE_PATH/work/nginx/sbin:$BASE_PATH/../nginx-devel-utils:$PATH"
#export LD_LIBRARY_PATH="$LUAJIT_LIB:$OPENSSL_LIB:$LD_LIBRARY_PATH"
export LD_LIBRARY_PATH="$LUAJIT_LIB:$LD_LIBRARY_PATH"

echo "PATH: $PATH"
echo "LD_LIBRARY_PATH: $LD_LIBRARY_PATH"

# Check required commands are available
echo ""
echo "Checking required commands..."

if ! command -v nginx &> /dev/null; then
    echo "ERROR: nginx command not found in PATH"
    echo "Expected: $BASE_PATH/work/nginx/sbin/nginx"
    echo "Run ./setup-test-environment.sh to build nginx"
    exit 1
fi
echo "✓ Nginx: $(which nginx)"
nginx -v 2>&1 | head -1

if ! command -v openssl &> /dev/null; then
    echo "ERROR: openssl command not found in PATH"
    echo "Expected: $OPENSSL_PREFIX/bin/openssl"
    echo "Run ./setup-test-environment.sh to build openssl"
    exit 1
fi
echo "✓ OpenSSL: $(which openssl)"
openssl version

if ! command -v prove &> /dev/null; then
    echo "ERROR: prove command not found (Test::Nginx)"
    echo "Run ./setup-test-environment.sh to install Test::Nginx"
    exit 1
fi
echo "✓ prove: $(which prove)"

# Allow specifying test file as argument
if [ -n "$1" ]; then
    echo "Running specific test: $1"
    TEST_NGINX_TIMEOUT=60 prove -v "$1"
else
    echo "Running all tests..."
    TEST_NGINX_TIMEOUT=60 prove -j"${JOBS:-3}" -r t/
fi

TEST_EXIT_CODE=$?

echo ""
if [ $TEST_EXIT_CODE -eq 0 ]; then
    echo "======================================"
    echo "Tests completed successfully!"
    echo "======================================"
else
    echo "======================================"
    echo "Tests failed with exit code: $TEST_EXIT_CODE"
    echo "======================================"
    echo ""
    echo "To view Docker logs:"
    echo "  cd t/fixtures && docker compose logs"
    echo ""
    echo "To run a specific test:"
    echo "  ./run-tests-locally.sh t/specific_test.t"
fi

exit $TEST_EXIT_CODE
