#!/usr/bin/env bash

set -euo pipefail

REPO_RAW_URL="${REPO_RAW_URL:-https://raw.githubusercontent.com/tao-t356/vps-ssh-fleet/main}"
TARGET_PATH="${TARGET_PATH:-${HOME}/ssh-key-menu.sh}"
RUN_AFTER_INSTALL=1
JSHOOK_VALUE="${JSHOOK:-}"

usage() {
  cat <<'EOF'
用法:
  bash bootstrap-vps.sh [--jshook 123] [--no-run] [--target /root/ssh-key-menu.sh]

功能:
  1. 从 GitHub 拉取最新的 ssh-key-menu.sh
  2. 保存到本机
  3. 赋予执行权限
  4. 默认立即运行
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --jshook)
      JSHOOK_VALUE="${2:-}"
      shift 2
      ;;
    --no-run)
      RUN_AFTER_INSTALL=0
      shift
      ;;
    --target)
      TARGET_PATH="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

download() {
  local url="$1"
  local output="$2"

  if command -v curl >/dev/null 2>&1; then
    if [ -n "${JSHOOK_VALUE}" ]; then
      curl -fsSL -H "jshook: ${JSHOOK_VALUE}" "${url}" -o "${output}"
    else
      curl -fsSL "${url}" -o "${output}"
    fi
  elif command -v wget >/dev/null 2>&1; then
    if [ -n "${JSHOOK_VALUE}" ]; then
      wget -qO "${output}" --header="jshook: ${JSHOOK_VALUE}" "${url}"
    else
      wget -qO "${output}" "${url}"
    fi
  else
    echo "需要 curl 或 wget 其中之一。" >&2
    exit 1
  fi
}

main() {
  local url="${REPO_RAW_URL}/ssh-key-menu.sh"
  local target_dir

  target_dir="$(dirname "${TARGET_PATH}")"
  mkdir -p "${target_dir}"

  echo "正在下载: ${url}"
  download "${url}" "${TARGET_PATH}"
  chmod +x "${TARGET_PATH}"
  echo "已安装到: ${TARGET_PATH}"

  if [ "${RUN_AFTER_INSTALL}" = "1" ]; then
    echo "正在启动菜单..."
    exec "${TARGET_PATH}"
  fi
}

main
