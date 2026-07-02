#!/usr/bin/env bash
# Deploy patched RKLLM runtime demo to RK3566 board and run a smoke test.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SSH_HOST="${SSH_HOST:-bpi2}"
SSH_TARGET="${1:-${SSH_HOST}}"
BOARD_DIR="${BOARD_DIR:-/opt/rkllm}"
MODEL_PATH="${MODEL_PATH:-}"

usage() {
    echo "Usage: MODEL_PATH=/path/to/model_w8a8_rk3566.rkllm $0 [ssh-target]"
    echo "  ssh-target defaults to '${SSH_HOST}' (or set SSH_HOST)"
    exit 1
}

remote() {
    ssh -o BatchMode=yes -o ConnectTimeout=15 "root@${SSH_TARGET}" "$@"
}

scp_to() {
    scp -o BatchMode=yes -o ConnectTimeout=15 "$1" "root@${SSH_TARGET}:$2"
}

echo "==> Applying RK3566 patches locally"
python3 "${REPO_ROOT}/scripts/patch_rk3566_support.py" --backup

echo "==> Checking board connectivity (${SSH_TARGET})"
remote "uname -a; cat /proc/device-tree/compatible 2>/dev/null | tr '\\0' ' '; echo"

echo "==> Checking NPU"
remote "ls -l /dev/dri/renderD* 2>/dev/null || true; ls /sys/class/devfreq/*npu* 2>/dev/null || true"

DEMO_BUILD="${REPO_ROOT}/examples/rkllm_api_demo/deploy"
DEMO_BIN="${DEMO_BUILD}/install/demo_Linux_aarch64/llm_demo"
if [ ! -x "${DEMO_BIN}" ]; then
    echo "==> Cross-compiling llm_demo for aarch64"
    if ! command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
        sudo apt-get update -qq
        sudo apt-get install -y -qq gcc-aarch64-linux-gnu g++-aarch64-linux-gnu cmake
    fi
    (
        cd "${DEMO_BUILD}"
        GCC_COMPILER_PATH="$(command -v aarch64-linux-gnu-gcc | sed 's/-gcc$//')"
        export GCC_COMPILER_PATH
        sed -i "s|~/opts/gcc-arm-.*|${GCC_COMPILER_PATH}|" build-linux.sh || true
        ./build-linux.sh
    )
fi

INSTALL="${REPO_ROOT}/build/rk3566_board"
rm -rf "${INSTALL}"
mkdir -p "${INSTALL}/lib"
cp "${REPO_ROOT}/rkllm-runtime/Linux/librkllm_api/aarch64/librkllmrt.so" "${INSTALL}/lib/"
cp "${DEMO_BIN}" "${INSTALL}/llm_demo"
cp "${REPO_ROOT}/scripts/fix_freq_rk3566.sh" "${INSTALL}/"

echo "==> Uploading runtime to board:${BOARD_DIR}"
remote "mkdir -p '${BOARD_DIR}'"
scp_to "${INSTALL}/llm_demo" "${BOARD_DIR}/"
scp_to "${INSTALL}/lib/librkllmrt.so" "${BOARD_DIR}/lib/"
scp_to "${INSTALL}/fix_freq_rk3566.sh" "${BOARD_DIR}/"

if [ -n "${MODEL_PATH}" ]; then
    echo "==> Uploading model ${MODEL_PATH}"
    scp_to "${MODEL_PATH}" "${BOARD_DIR}/model.rkllm"
    remote "cd '${BOARD_DIR}' && export LD_LIBRARY_PATH=./lib && bash fix_freq_rk3566.sh && ./llm_demo model.rkllm 128 512"
else
    echo "==> Smoke test (runtime upload – set MODEL_PATH for full inference)"
    remote "cd '${BOARD_DIR}' && export LD_LIBRARY_PATH=./lib && ldd ./llm_demo && strings ./lib/librkllmrt.so | grep -i 'RK3566\\|lite' | head -3"
fi

echo "Done."
