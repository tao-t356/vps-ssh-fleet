#!/usr/bin/env bash

set -euo pipefail

REPO_RAW_URL="${REPO_RAW_URL:-https://raw.githubusercontent.com/tao-t356/vps-ssh-fleet/refs/heads/main}"
TARGET_PATH="${TARGET_PATH:-${HOME}/ssh-key-menu.sh}"
RUN_AFTER_INSTALL=1
JSHOOK_VALUE="${JSHOOK:-}"
INSTALL_SHORTCUT=1
SHORTCUT_NAME="${SHORTCUT_NAME:-f}"
MARKER="# Managed by vps-ssh-fleet bootstrap"

usage() {
  cat <<'EOF'
用法:
  bash bootstrap-vps.sh [--jshook 123] [--no-run] [--target /root/ssh-key-menu.sh]
                        [--shortcut f] [--no-shortcut]

功能:
  1. 从 GitHub 拉取最新的 ssh-key-menu.sh
  2. 保存到本机
  3. 赋予执行权限
  4. 默认安装快捷命令（默认是 f）
  5. 默认立即运行
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
    --shortcut)
      SHORTCUT_NAME="${2:-}"
      shift 2
      ;;
    --no-shortcut)
      INSTALL_SHORTCUT=0
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

ensure_local_bin_in_path() {
  local local_bin="${HOME}/.local/bin"
  local bashrc="${HOME}/.bashrc"
  mkdir -p "${local_bin}"

  case ":${PATH}:" in
    *":${local_bin}:"*) return 0 ;;
  esac

  if [ -f "${bashrc}" ] && grep -Fqs "${local_bin}" "${bashrc}"; then
    return 0
  fi

  {
    printf '\n'
    printf '# Added by vps-ssh-fleet bootstrap\n'
    printf 'export PATH="%s:$PATH"\n' "${local_bin}"
  } >> "${bashrc}"
}

install_shortcut() {
  local shortcut_name="$1"
  local shortcut_path=""
  local shortcut_dir=""
  local existing=""

  [ -n "${shortcut_name}" ] || return 0

  if [ "$(id -u)" -eq 0 ] && [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
    shortcut_dir="/usr/local/bin"
  else
    shortcut_dir="${HOME}/.local/bin"
    ensure_local_bin_in_path
  fi

  mkdir -p "${shortcut_dir}"
  shortcut_path="${shortcut_dir}/${shortcut_name}"

  if [ -e "${shortcut_path}" ]; then
    existing="$(head -n 1 "${shortcut_path}" 2>/dev/null || true)"
    if ! grep -Fqs "${MARKER}" "${shortcut_path}" 2>/dev/null; then
      echo "检测到已有文件 ${shortcut_path}，为了避免覆盖，已跳过快捷命令安装。" >&2
      echo "你仍然可以手动运行: bash ${TARGET_PATH}" >&2
      return 0
    fi
  fi

  cat > "${shortcut_path}" <<EOF
#!/usr/bin/env bash
${MARKER}
exec bash "${TARGET_PATH}" "\$@"
EOF
  chmod +x "${shortcut_path}"
  echo "已安装快捷命令: ${shortcut_name}"
  echo "快捷命令路径: ${shortcut_path}"
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

  if [ "${INSTALL_SHORTCUT}" = "1" ]; then
    install_shortcut "${SHORTCUT_NAME}"
  fi

  if [ "${RUN_AFTER_INSTALL}" = "1" ]; then
    echo "正在启动菜单..."
    exec "${TARGET_PATH}"
  fi
}

main
