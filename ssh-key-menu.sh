#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
TOOLBOX_VERSION="0.5.0"
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

run_with_tty() {
  if [ -r /dev/tty ] && [ -w /dev/tty ]; then
    "$@" < /dev/tty > /dev/tty 2>&1
  else
    "$@"
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

print_ssh_menu() {
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

  run_with_tty ssh-keygen -t ed25519 -f "${key_path}" -C "${comment}"
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
  run_with_tty "${editor}" "${AUTHORIZED_KEYS}"
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

option_show_system_info() {
  local os_name="unknown"
  local local_ip="unknown"

  if [ -r /etc/os-release ]; then
    os_name="$(. /etc/os-release && printf '%s' "${PRETTY_NAME:-unknown}")"
  fi

  if have_cmd hostname; then
    local_ip="$(hostname -I 2>/dev/null | awk '{print $1}' || printf 'unknown')"
  fi

  say "${C_BOLD}${C_CYAN}系统信息${C_RESET}"
  say "--------------------------------------------------"
  say "主机名: $(hostname)"
  say "当前用户: ${CURRENT_USER}"
  say "系统: ${os_name}"
  say "内核: $(uname -srmo 2>/dev/null || uname -a)"
  say "本机 IP: ${local_ip}"
  say "启动时间: $(uptime -p 2>/dev/null || uptime)"
  say "时间: $(date '+%Y-%m-%d %H:%M:%S %Z')"
  say "--------------------------------------------------"

  if have_cmd free; then
    say "[内存]"
    free -h
    say "--------------------------------------------------"
  fi

  if have_cmd df; then
    say "[磁盘]"
    df -h /
    say "--------------------------------------------------"
  fi

  if have_cmd ss; then
    say "[监听端口]"
    ss -tulpn 2>/dev/null | sed -n '1,12p'
  fi
}

option_vless_project_info() {
  say "${C_BOLD}${C_CYAN}vless-xhttp-reality-self${C_RESET}"
  say "--------------------------------------------------"
  say "仓库: https://github.com/tao-t356/vless-xhttp-reality-self"
  say "用途: Debian / Ubuntu 上菜单式部署 VLESS + XHTTP + REALITY + Hysteria2"
  say "要求: root、域名已解析、80/443 可用"
  say "运行方式: 会从 GitHub 拉取 scripts/install.sh 并执行"
  say "--------------------------------------------------"
}

option_run_vless_project() {
  local project_url="https://raw.githubusercontent.com/tao-t356/vless-xhttp-reality-self/main/scripts/install.sh"
  local jshook=""
  local tmp_file=""

  if [ "$(id -u)" -ne 0 ]; then
    err "这个项目建议使用 root 运行。"
    return 1
  fi

  if [ -r /etc/os-release ]; then
    . /etc/os-release
    case "${ID:-}" in
      debian|ubuntu) ;;
      *)
        warn "当前系统不是 Debian / Ubuntu，脚本可能不兼容。"
        ;;
    esac
  fi

  say "即将运行: vless-xhttp-reality-self"
  say "仓库地址: ${project_url}"
  say "注意：它会修改 Xray / Nginx / 证书等配置。"
  prompt_read -p "确认继续？[y/N]: " confirm
  case "${confirm}" in
    y|Y) ;;
    *)
      warn "已取消。"
      return 0
      ;;
  esac

  prompt_read -p "jshook（当前环境需要）: " jshook

  tmp_file="$(mktemp)"
  if have_cmd curl; then
    curl -fsSL -H "jshook: ${jshook}" "${project_url}" -o "${tmp_file}"
  elif have_cmd wget; then
    wget -qO "${tmp_file}" --header="jshook: ${jshook}" "${project_url}"
  else
    err "需要 curl 或 wget 其中一个命令。"
    rm -f "${tmp_file}"
    return 1
  fi

  chmod +x "${tmp_file}"
  run_with_tty bash "${tmp_file}"
  rm -f "${tmp_file}"
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

print_toolbox_menu() {
  clear 2>/dev/null || true
  say "${C_BOLD}${C_CYAN}VPS 工具箱 v${TOOLBOX_VERSION}${C_RESET}"
  say "当前用户: ${CURRENT_USER}    主机: $(hostname)"
  say "密码登录模式: $(password_status_text)    公钥条数: $(count_authorized_keys)"
  say "--------------------------------------------------"
  say "1. SSH 登录管理"
  say "2. 系统信息查询"
  say "3. 应用市场"
  say "0. 退出"
  say "--------------------------------------------------"
}

apps_menu_loop() {
  local choice=""
  while true; do
    clear 2>/dev/null || true
    say "${C_BOLD}${C_CYAN}应用市场${C_RESET}"
    say "--------------------------------------------------"
    say "1. 运行 vless-xhttp-reality-self"
    say "2. 查看 vless-xhttp-reality-self 说明"
    say "0. 返回上一级"
    say "--------------------------------------------------"
    prompt_read -p "请输入你的选择: " choice
    printf '\n'
    case "${choice}" in
      1) option_run_vless_project ;;
      2) option_vless_project_info ;;
      0) return 0 ;;
      *) warn "无效选项，请重新输入。" ;;
    esac
    pause
  done
}

ssh_menu_loop() {
  local choice=""
  while true; do
    print_ssh_menu
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
      0) return 0 ;;
      *) warn "无效选项，请重新输入。" ;;
    esac
    pause
  done
}

main_loop() {
  local choice=""
  while true; do
    print_toolbox_menu
    prompt_read -p "请输入你的选择: " choice
    printf '\n'
    case "${choice}" in
      1) ssh_menu_loop ;;
      2) option_show_system_info; pause ;;
      3) apps_menu_loop ;;
      0) exit 0 ;;
      *) warn "无效选项，请重新输入。"; pause ;;
    esac
  done
}

main_loop
