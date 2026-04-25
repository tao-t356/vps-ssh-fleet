#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
CURRENT_USER="$(id -un)"
CURRENT_HOME="${HOME:-/root}"
SSH_DIR="${CURRENT_HOME}/.ssh"
AUTHORIZED_KEYS="${SSH_DIR}/authorized_keys"
MARK_BEGIN="# BEGIN VPS-SSH-KEY-MENU"
MARK_END="# END VPS-SSH-KEY-MENU"

if command -v tput >/dev/null 2>&1 && [ -n "${TERM:-}" ] && [ "${TERM}" != "dumb" ]; then
  C_CYAN="$(tput setaf 6)"
  C_GREEN="$(tput setaf 2)"
  C_YELLOW="$(tput setaf 3)"
  C_RED="$(tput setaf 1)"
  C_BOLD="$(tput bold)"
  C_RESET="$(tput sgr0)"
else
  C_CYAN=""
  C_GREEN=""
  C_YELLOW=""
  C_RED=""
  C_BOLD=""
  C_RESET=""
fi

say() { printf '%s\n' "$*"; }
ok() { printf '%s%s%s\n' "${C_GREEN}" "$*" "${C_RESET}"; }
warn() { printf '%s%s%s\n' "${C_YELLOW}" "$*" "${C_RESET}"; }
err() { printf '%s%s%s\n' "${C_RED}" "$*" "${C_RESET}" >&2; }
have_cmd() { command -v "$1" >/dev/null 2>&1; }

prompt_read() {
  if [ -r /dev/tty ]; then
    read -r "$@" < /dev/tty
  else
    read -r "$@"
  fi
}

pause() { printf '\n'; prompt_read -p "按回车继续..." _; }

require_cmd() {
  if ! have_cmd "$1"; then
    err "缺少命令: $1"
    return 1
  fi
}

ensure_ssh_dir() {
  mkdir -p "${SSH_DIR}"
  chmod 700 "${SSH_DIR}"
  touch "${AUTHORIZED_KEYS}"
  chmod 600 "${AUTHORIZED_KEYS}"
}

count_authorized_keys() {
  if [ -f "${AUTHORIZED_KEYS}" ]; then
    awk 'NF{n++} END{print n+0}' "${AUTHORIZED_KEYS}"
  else
    echo 0
  fi
}

default_editor() {
  if [ -n "${EDITOR:-}" ]; then
    printf '%s' "${EDITOR}"
  elif have_cmd nano; then
    printf 'nano'
  else
    printf 'vi'
  fi
}

sudo_prefix() {
  if [ "$(id -u)" -eq 0 ]; then
    printf ''
  elif have_cmd sudo; then
    printf 'sudo'
  else
    return 1
  fi
}

effective_sshd_status() {
  local field="$1"
  local sshd_bin=""
  if have_cmd sshd; then
    sshd_bin="$(command -v sshd)"
  elif [ -x /usr/sbin/sshd ]; then
    sshd_bin="/usr/sbin/sshd"
  fi

  if [ -n "${sshd_bin}" ]; then
    "${sshd_bin}" -T 2>/dev/null | awk -v key="${field}" '$1 == key {print $2; exit}'
    return 0
  fi

  printf 'unknown'
}

password_status_text() {
  local status
  status="$(effective_sshd_status passwordauthentication)"
  case "${status}" in
    yes) printf '已启用' ;;
    no) printf '未启用' ;;
    *) printf '未知' ;;
  esac
}

pubkey_status_text() {
  local status
  status="$(effective_sshd_status pubkeyauthentication)"
  case "${status}" in
    yes) printf '已启用' ;;
    no) printf '未启用' ;;
    *) printf '未知' ;;
  esac
}

print_menu() {
  clear 2>/dev/null || true
  say "${C_BOLD}${C_CYAN}SSH 登录管理菜单${C_RESET}"
  say "当前用户: ${CURRENT_USER}"
  say "密码登录模式: $(password_status_text)"
  say "公钥登录模式: $(pubkey_status_text)"
  say "authorized_keys 条数: $(count_authorized_keys)"
  say "--------------------------------------------------"
  say "1. 生成本机密钥对            2. 手动输入一行公钥"
  say "3. GitHub 导入已有公钥       4. URL 导入已有公钥"
  say "5. 编辑公钥文件              6. 查看本机密钥"
  say "7. 查看 authorized_keys      8. 关闭密码登录"
  say "9. 开启密码登录              0. 退出"
  say "--------------------------------------------------"
}

append_keys_text() {
  local payload="$1"
  local tmp_file

  ensure_ssh_dir

  tmp_file="$(mktemp)"
  {
    [ -f "${AUTHORIZED_KEYS}" ] && cat "${AUTHORIZED_KEYS}"
    printf '%s\n' "${payload}"
  } | awk 'NF && !seen[$0]++' > "${tmp_file}"

  mv "${tmp_file}" "${AUTHORIZED_KEYS}"
  chmod 600 "${AUTHORIZED_KEYS}"
}

validate_public_key_line() {
  case "$1" in
    ssh-*|ecdsa-*|sk-ssh-*|sk-ecdsa-*) return 0 ;;
    *) return 1 ;;
  esac
}

fetch_url_text() {
  local url="$1"
  local jshook="${2:-}"

  if have_cmd curl; then
    if [ -n "${jshook}" ]; then
      curl -fsSL -H "jshook: ${jshook}" "${url}"
    else
      curl -fsSL "${url}"
    fi
  elif have_cmd wget; then
    if [ -n "${jshook}" ]; then
      wget -qO- --header="jshook: ${jshook}" "${url}"
    else
      wget -qO- "${url}"
    fi
  else
    err "需要 curl 或 wget 其中一个命令。"
    return 1
  fi
}

option_generate_keypair() {
  require_cmd ssh-keygen || return 1
  ensure_ssh_dir

  local default_path="${SSH_DIR}/id_ed25519"
  local key_path=""
  local comment=""

  prompt_read -p "密钥保存路径 [${default_path}]: " key_path
  key_path="${key_path:-${default_path}}"

  if [ -e "${key_path}" ] || [ -e "${key_path}.pub" ]; then
    prompt_read -p "文件已存在，是否覆盖？[y/N]: " confirm
    case "${confirm}" in
      y|Y) ;;
      *) warn "已取消。"; return 0 ;;
    esac
  fi

  prompt_read -p "注释 [${CURRENT_USER}@$(hostname)]: " comment
  comment="${comment:-${CURRENT_USER}@$(hostname)}"

  ssh-keygen -t ed25519 -f "${key_path}" -C "${comment}"
  ok "已生成密钥：${key_path}"
  [ -f "${key_path}.pub" ] && say "公钥内容：" && cat "${key_path}.pub"
}

option_manual_key() {
  local key_line=""
  prompt_read -p "请粘贴一整行 SSH 公钥: " key_line

  if [ -z "${key_line}" ]; then
    warn "没有输入内容。"
    return 0
  fi

  if ! validate_public_key_line "${key_line}"; then
    err "这看起来不像标准 SSH 公钥。"
    return 1
  fi

  append_keys_text "${key_line}"
  ok "公钥已写入 ${AUTHORIZED_KEYS}"
}

option_import_github() {
  local gh_user=""
  local jshook=""
  local url=""
  local body=""

  prompt_read -p "GitHub 用户名: " gh_user
  if [ -z "${gh_user}" ]; then
    warn "GitHub 用户名不能为空。"
    return 0
  fi

  prompt_read -p "jshook（当前环境建议填写）: " jshook
  url="https://github.com/${gh_user}.keys"
  body="$(fetch_url_text "${url}" "${jshook}")" || return 1

  if [ -z "${body}" ]; then
    err "没有拉取到任何公钥，请确认 ${gh_user} 账号下已经上传了公钥。"
    return 1
  fi

  append_keys_text "${body}"
  ok "已从 GitHub 导入公钥。"
}

option_import_url() {
  local url=""
  local jshook=""
  local body=""

  prompt_read -p "公钥 URL: " url
  if [ -z "${url}" ]; then
    warn "URL 不能为空。"
    return 0
  fi

  prompt_read -p "jshook（如果需要）: " jshook
  body="$(fetch_url_text "${url}" "${jshook}")" || return 1

  if [ -z "${body}" ]; then
    err "URL 返回为空。"
    return 1
  fi

  append_keys_text "${body}"
  ok "已从 URL 导入公钥。"
}

option_edit_authorized_keys() {
  ensure_ssh_dir
  local editor
  editor="$(default_editor)"
  "${editor}" "${AUTHORIZED_KEYS}"
}

option_view_local_keys() {
  ensure_ssh_dir
  say "SSH 目录: ${SSH_DIR}"
  say "--------------------------------------------------"
  ls -la "${SSH_DIR}" 2>/dev/null || true
  say "--------------------------------------------------"
  if ls "${SSH_DIR}"/*.pub >/dev/null 2>&1; then
    for pub_file in "${SSH_DIR}"/*.pub; do
      say ">>> ${pub_file}"
      cat "${pub_file}"
      say ""
    done
  else
    warn "当前目录下还没有 .pub 公钥文件。"
  fi
}

option_view_authorized_keys() {
  ensure_ssh_dir
  if [ ! -s "${AUTHORIZED_KEYS}" ]; then
    warn "${AUTHORIZED_KEYS} 还是空的。"
    return 0
  fi

  say "文件: ${AUTHORIZED_KEYS}"
  say "--------------------------------------------------"
  nl -ba "${AUTHORIZED_KEYS}"
}

apply_password_mode() {
  local password_auth="$1"
  local kbd_auth="$2"
  local challenge_auth="$3"
  local permit_root="$4"
  local root_cmd=""
  local tmp_script=""

  if ! root_cmd="$(sudo_prefix)"; then
    err "需要 root 或 sudo 权限才能修改 SSH 服务配置。"
    return 1
  fi

  tmp_script="$(mktemp)"
  cat > "${tmp_script}" <<EOF
set -e
CONFIG="/etc/ssh/sshd_config"
MANAGED_FILE="/etc/ssh/sshd_config.d/99-vps-ssh-key-menu.conf"
USE_INCLUDE=0

if grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\\.d/\\*\\.conf' "\${CONFIG}" 2>/dev/null; then
  USE_INCLUDE=1
fi

backup_file() {
  if [ -f "\$1" ]; then
    cp "\$1" "\$1.bak.\$(date +%F-%H%M%S)"
  fi
}

if [ "\${USE_INCLUDE}" = "1" ]; then
  mkdir -p /etc/ssh/sshd_config.d
  backup_file "\${MANAGED_FILE}"
  cat > "\${MANAGED_FILE}" <<'CONF'
# Managed by ${SCRIPT_NAME}
PubkeyAuthentication yes
PasswordAuthentication ${password_auth}
KbdInteractiveAuthentication ${kbd_auth}
ChallengeResponseAuthentication ${challenge_auth}
PermitRootLogin ${permit_root}
CONF
else
  backup_file "\${CONFIG}"
  TMP="\$(mktemp)"
  awk '
    BEGIN {skip=0}
    \$0 == "${MARK_BEGIN}" {skip=1; next}
    \$0 == "${MARK_END}" {skip=0; next}
    !skip {print}
  ' "\${CONFIG}" > "\${TMP}"
  cat >> "\${TMP}" <<'CONF'
${MARK_BEGIN}
PubkeyAuthentication yes
PasswordAuthentication ${password_auth}
KbdInteractiveAuthentication ${kbd_auth}
ChallengeResponseAuthentication ${challenge_auth}
PermitRootLogin ${permit_root}
${MARK_END}
CONF
  mv "\${TMP}" "\${CONFIG}"
fi

if command -v sshd >/dev/null 2>&1; then
  sshd -t
elif [ -x /usr/sbin/sshd ]; then
  /usr/sbin/sshd -t
fi

systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || service sshd restart 2>/dev/null || service ssh restart 2>/dev/null
EOF

  if [ -n "${root_cmd}" ]; then
    ${root_cmd} bash "${tmp_script}"
  else
    bash "${tmp_script}"
  fi

  rm -f "${tmp_script}"
}

option_disable_password_login() {
  say "请先确保你已经在新终端里测试过公钥登录。"
  prompt_read -p "确认关闭密码登录？[y/N]: " confirm
  case "${confirm}" in
    y|Y)
      apply_password_mode "no" "no" "no" "prohibit-password"
      ok "密码登录已关闭。"
      ;;
    *)
      warn "已取消。"
      ;;
  esac
}

option_enable_password_login() {
  prompt_read -p "确认开启密码登录？[y/N]: " confirm
  case "${confirm}" in
    y|Y)
      apply_password_mode "yes" "yes" "yes" "yes"
      ok "密码登录已开启。"
      ;;
    *)
      warn "已取消。"
      ;;
  esac
}

main_loop() {
  local choice=""
  while true; do
    print_menu
    prompt_read -p "请输入你的选择: " choice
    printf '\n'
    case "${choice}" in
      1) option_generate_keypair ;;
      2) option_manual_key ;;
      3) option_import_github ;;
      4) option_import_url ;;
      5) option_edit_authorized_keys ;;
      6) option_view_local_keys ;;
      7) option_view_authorized_keys ;;
      8) option_disable_password_login ;;
      9) option_enable_password_login ;;
      0) exit 0 ;;
      *) warn "无效选项，请重新输入。" ;;
    esac
    pause
  done
}

main_loop
