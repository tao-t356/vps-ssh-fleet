#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_PATH="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)/$(basename "$0")"
TOOLBOX_VERSION="0.9.0"
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

print_logo() {
  say "${C_BOLD}${C_CYAN} __     ______   _____   _______             _ _                ${C_RESET}"
  say "${C_BOLD}${C_CYAN} \\ \\   / /  _ \\ / ____| |__   __|           | | |               ${C_RESET}"
  say "${C_BOLD}${C_CYAN}  \\ \\_/ /| |_) | (___      | | ___   ___ ___| | |__   _____  __  ${C_RESET}"
  say "${C_BOLD}${C_CYAN}   \\   / |  _ < \\___ \\     | |/ _ \\ / _ / __| | '_ \\ / _ \\ \\/ /  ${C_RESET}"
  say "${C_BOLD}${C_CYAN}    | |  | |_) |____) |    | | (_) | (_) (__| | |_) | (_) >  <   ${C_RESET}"
  say "${C_BOLD}${C_CYAN}    |_|  |____/|_____/     |_|\\___/ \\___\\___|_|_.__/ \\___/_/\\_\\  ${C_RESET}"
  say "${C_BOLD}${C_CYAN}                         v${TOOLBOX_VERSION}${C_RESET}"
}

run_docker() {
  if ! have_cmd docker; then
    err "当前系统未安装 Docker。"
    return 1
  fi

  if docker info >/dev/null 2>&1; then
    docker "$@"
  elif have_cmd sudo && sudo docker info >/dev/null 2>&1; then
    sudo docker "$@"
  else
    err "当前用户无法访问 Docker，请切换到 root 或加入 docker 组。"
    return 1
  fi
}

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
  print_logo
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

run_remote_installer() {
  local project_name="$1"
  local project_url="$2"
  local note="${3:-}"
  local jshook=""
  local tmp_file=""

  if [ "$(id -u)" -ne 0 ]; then
    err "${project_name} 建议使用 root 运行。"
    return 1
  fi

  say "即将运行: ${project_name}"
  say "仓库地址: ${project_url}"
  [ -n "${note}" ] && say "注意：${note}"
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

option_run_vless_project() {
  if [ -r /etc/os-release ]; then
    . /etc/os-release
    case "${ID:-}" in
      debian|ubuntu) ;;
      *)
        warn "当前系统不是 Debian / Ubuntu，脚本可能不兼容。"
        ;;
    esac
  fi

  run_remote_installer \
    "vless-xhttp-reality-self" \
    "https://raw.githubusercontent.com/tao-t356/vless-xhttp-reality-self/main/scripts/install.sh" \
    "它会修改 Xray / Nginx / 证书等配置。"
}

option_npm_docker_info() {
  say "${C_BOLD}${C_CYAN}Docker + Nginx Proxy Manager${C_RESET}"
  say "--------------------------------------------------"
  say "仓库: https://github.com/tao-t356/Docker-Nginx-Proxy-Manager"
  say "用途: 一键安装 Docker 与 Nginx Proxy Manager"
  say "原始命令: wget -qO n https://raw.githubusercontent.com/tao-t356/Docker-Nginx-Proxy-Manager/main/install.sh && bash n"
  say "当前工具箱会改成 jshook 兼容方式下载后执行。"
  say "--------------------------------------------------"
}

option_run_npm_docker() {
  run_remote_installer \
    "Docker-Nginx-Proxy-Manager" \
    "https://raw.githubusercontent.com/tao-t356/Docker-Nginx-Proxy-Manager/main/install.sh" \
    "它会安装 Docker 与 Nginx Proxy Manager。"
}

option_nexttrace_info() {
  say "${C_BOLD}${C_CYAN}NextTrace${C_RESET}"
  say "--------------------------------------------------"
  say "官网: https://nxtrace.org"
  say "用途: 路由追踪 / 网络诊断"
  say "原始命令: curl -sL https://nxtrace.org/nt | bash"
  say "当前工具箱会改成 jshook 兼容方式下载后执行。"
  say "--------------------------------------------------"
}

option_run_nexttrace() {
  run_remote_installer \
    "NextTrace" \
    "https://nxtrace.org/nt" \
    "它会在线安装 NextTrace。"
}

option_bbr_info() {
  local cc="unknown"
  local qdisc="unknown"
  local available="unknown"

  if have_cmd sysctl; then
    cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || printf 'unknown')"
    qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null || printf 'unknown')"
    available="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || printf 'unknown')"
  fi

  say "${C_BOLD}${C_CYAN}BBR 状态${C_RESET}"
  say "--------------------------------------------------"
  say "当前拥塞控制算法: ${cc}"
  say "当前默认队列算法: ${qdisc}"
  say "内核支持的拥塞控制: ${available}"
  if printf '%s' "${available}" | grep -qw bbr; then
    say "BBR 支持状态: 支持"
  else
    say "BBR 支持状态: 可能不支持"
  fi
  if [ "${cc}" = "bbr" ]; then
    say "BBR 启用状态: 已启用"
  else
    say "BBR 启用状态: 未启用"
  fi
  say "--------------------------------------------------"
}

option_enable_bbr() {
  local root_cmd=""
  local tmp_script=""

  if ! root_cmd="$(sudo_prefix)"; then
    err "需要 root 或 sudo 权限才能启用 BBR。"
    return 1
  fi

  say "即将启用 BBR。"
  say "会写入:"
  say "- /etc/modules-load.d/bbr.conf"
  say "- /etc/sysctl.d/99-vps-toolbox-bbr.conf"
  prompt_read -p "确认继续？[y/N]: " confirm
  case "${confirm}" in
    y|Y) ;;
    *)
      warn "已取消。"
      return 0
      ;;
  esac

  tmp_script="$(mktemp)"
  cat > "${tmp_script}" <<'EOF'
set -e

mkdir -p /etc/modules-load.d /etc/sysctl.d

cat > /etc/modules-load.d/bbr.conf <<'CONF'
tcp_bbr
sch_fq
CONF

cat > /etc/sysctl.d/99-vps-toolbox-bbr.conf <<'CONF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
CONF

modprobe sch_fq 2>/dev/null || true
modprobe tcp_bbr 2>/dev/null || true

if command -v sysctl >/dev/null 2>&1; then
  sysctl --system >/dev/null
fi
EOF

  if [ -n "${root_cmd}" ]; then
    ${root_cmd} bash "${tmp_script}"
  else
    bash "${tmp_script}"
  fi
  rm -f "${tmp_script}"

  option_bbr_info
}

option_system_cleanup() {
  local root_cmd=""
  local tmp_script=""

  if ! root_cmd="$(sudo_prefix)"; then
    err "需要 root 或 sudo 权限才能执行系统清理。"
    return 1
  fi

  say "即将执行系统清理："
  say "- apt / dnf / yum 缓存清理"
  say "- 无用依赖清理"
  say "- journal 日志保留最近 7 天"
  prompt_read -p "确认继续？[y/N]: " confirm
  case "${confirm}" in
    y|Y) ;;
    *)
      warn "已取消。"
      return 0
      ;;
  esac

  say "清理前磁盘使用："
  df -h /

  tmp_script="$(mktemp)"
  cat > "${tmp_script}" <<'EOF'
set -e

if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y >/dev/null 2>&1 || true
  apt-get autoremove -y
  apt-get autoclean -y
  apt-get clean -y
elif command -v dnf >/dev/null 2>&1; then
  dnf autoremove -y || true
  dnf clean all || true
elif command -v yum >/dev/null 2>&1; then
  yum autoremove -y || true
  yum clean all || true
fi

if command -v journalctl >/dev/null 2>&1; then
  journalctl --vacuum-time=7d || true
fi
EOF

  if [ -n "${root_cmd}" ]; then
    ${root_cmd} bash "${tmp_script}"
  else
    bash "${tmp_script}"
  fi
  rm -f "${tmp_script}"

  say "清理后磁盘使用："
  df -h /
}

option_docker_status() {
  if ! have_cmd docker; then
    warn "当前系统未安装 Docker。"
    return 0
  fi

  say "${C_BOLD}${C_CYAN}Docker 状态${C_RESET}"
  say "--------------------------------------------------"
  docker --version 2>/dev/null || true
  run_docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' 2>/dev/null || true
}

option_docker_list_all() {
  if ! have_cmd docker; then
    warn "当前系统未安装 Docker。"
    return 0
  fi

  run_docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.Image}}'
}

option_docker_start_all() {
  local ids=""
  ids="$(run_docker ps -aq 2>/dev/null || true)"
  if [ -z "${ids}" ]; then
    warn "当前没有容器。"
    return 0
  fi
  run_docker start ${ids}
}

option_docker_stop_all() {
  local ids=""
  ids="$(run_docker ps -aq 2>/dev/null || true)"
  if [ -z "${ids}" ]; then
    warn "当前没有容器。"
    return 0
  fi
  run_docker stop ${ids}
}

option_docker_restart_all() {
  local ids=""
  ids="$(run_docker ps -aq 2>/dev/null || true)"
  if [ -z "${ids}" ]; then
    warn "当前没有容器。"
    return 0
  fi
  run_docker restart ${ids}
}

option_docker_logs() {
  local container_name=""
  prompt_read -p "请输入容器名: " container_name
  if [ -z "${container_name}" ]; then
    warn "容器名不能为空。"
    return 0
  fi
  run_docker logs --tail 100 "${container_name}"
}

option_docker_prune() {
  prompt_read -p "确认执行 docker system prune -f ? [y/N]: " confirm
  case "${confirm}" in
    y|Y) run_docker system prune -f ;;
    *) warn "已取消。" ;;
  esac
}

detect_firewall_backend() {
  if have_cmd ufw; then
    printf 'ufw'
    return 0
  fi
  if have_cmd firewall-cmd && firewall-cmd --state >/dev/null 2>&1; then
    printf 'firewalld'
    return 0
  fi
  printf 'none'
}

option_firewall_status() {
  local backend=""
  backend="$(detect_firewall_backend)"
  say "${C_BOLD}${C_CYAN}防火墙状态${C_RESET}"
  say "--------------------------------------------------"
  case "${backend}" in
    ufw)
      ufw status verbose || true
      ;;
    firewalld)
      firewall-cmd --state
      firewall-cmd --list-all || true
      ;;
    *)
      warn "未检测到受支持的防火墙（ufw / firewalld）。"
      ;;
  esac
}

allow_firewall_port() {
  local port="$1"
  local proto="$2"
  local backend=""
  local root_cmd=""

  backend="$(detect_firewall_backend)"
  if [ "${backend}" = "none" ]; then
    warn "未检测到受支持的防火墙（ufw / firewalld）。"
    return 1
  fi

  if ! root_cmd="$(sudo_prefix)"; then
    err "需要 root 或 sudo 权限才能修改防火墙。"
    return 1
  fi

  case "${backend}" in
    ufw)
      if [ -n "${root_cmd}" ]; then
        ${root_cmd} ufw allow "${port}/${proto}"
      else
        ufw allow "${port}/${proto}"
      fi

      if ufw status 2>/dev/null | head -n 1 | grep -qi inactive; then
        prompt_read -p "UFW 当前未启用，是否立即启用？[y/N]: " enable_ufw
        case "${enable_ufw}" in
          y|Y)
            if [ -n "${root_cmd}" ]; then
              ${root_cmd} ufw --force enable
            else
              ufw --force enable
            fi
            ;;
        esac
      fi
      ;;
    firewalld)
      if [ -n "${root_cmd}" ]; then
        ${root_cmd} firewall-cmd --permanent --add-port="${port}/${proto}"
        ${root_cmd} firewall-cmd --reload
      else
        firewall-cmd --permanent --add-port="${port}/${proto}"
        firewall-cmd --reload
      fi
      ;;
  esac

  ok "已放行端口 ${port}/${proto}"
}

option_allow_common_ports() {
  allow_firewall_port 22 tcp
  allow_firewall_port 80 tcp
  allow_firewall_port 443 tcp
}

option_allow_custom_port() {
  local port=""
  local proto=""
  prompt_read -p "端口号: " port
  if [ -z "${port}" ]; then
    warn "端口号不能为空。"
    return 0
  fi
  prompt_read -p "协议 [tcp]: " proto
  proto="${proto:-tcp}"
  allow_firewall_port "${port}" "${proto}"
}

option_update_toolbox() {
  local jshook=""
  local tmp_script=""

  prompt_read -p "jshook（当前环境需要）: " jshook
  if [ -z "${jshook}" ]; then
    warn "jshook 不能为空。"
    return 0
  fi

  tmp_script="$(mktemp)"
  if have_cmd curl; then
    curl -fsSL -H "jshook: ${jshook}" "https://raw.githubusercontent.com/tao-t356/vps-ssh-fleet/main/bootstrap-vps.sh" -o "${tmp_script}"
  elif have_cmd wget; then
    wget -qO "${tmp_script}" --header="jshook: ${jshook}" "https://raw.githubusercontent.com/tao-t356/vps-ssh-fleet/main/bootstrap-vps.sh"
  else
    err "需要 curl 或 wget 其中一个命令。"
    rm -f "${tmp_script}"
    return 1
  fi

  chmod +x "${tmp_script}"
  bash "${tmp_script}" --no-run --target "${SCRIPT_PATH}"
  rm -f "${tmp_script}"
  ok "工具箱已更新到最新版本。"

  prompt_read -p "是否立即重新打开工具箱？[Y/n]: " reopen
  case "${reopen}" in
    n|N) ;;
    *)
      exec bash "${SCRIPT_PATH}"
      ;;
  esac
}

option_ping_test() {
  local target=""
  prompt_read -p "请输入目标域名或 IP: " target
  if [ -z "${target}" ]; then
    warn "目标不能为空。"
    return 0
  fi
  if have_cmd ping; then
    run_with_tty ping -c 4 "${target}"
  else
    err "当前系统没有 ping 命令。"
  fi
}

option_trace_test() {
  local target=""
  prompt_read -p "请输入目标域名或 IP: " target
  if [ -z "${target}" ]; then
    warn "目标不能为空。"
    return 0
  fi

  if have_cmd traceroute; then
    run_with_tty traceroute "${target}"
  elif have_cmd tracepath; then
    run_with_tty tracepath "${target}"
  else
    err "当前系统没有 traceroute / tracepath。"
  fi
}

option_show_ip_route() {
  if have_cmd ip; then
    ip route show
  elif have_cmd route; then
    route -n
  else
    err "当前系统没有 ip / route 命令。"
  fi
}

option_show_listening_ports() {
  if have_cmd ss; then
    ss -tulpn
  elif have_cmd netstat; then
    netstat -tulpn
  else
    err "当前系统没有 ss / netstat。"
  fi
}

option_show_top_processes() {
  say "[CPU TOP 10]"
  ps -eo pid,ppid,user,%cpu,%mem,comm --sort=-%cpu | sed -n '1,11p'
  say "--------------------------------------------------"
  say "[MEM TOP 10]"
  ps -eo pid,ppid,user,%cpu,%mem,comm --sort=-%mem | sed -n '1,11p'
}

option_show_common_service_status() {
  local services="ssh sshd nginx docker xray hysteria-server hysteria"
  local svc=""

  if have_cmd systemctl; then
    for svc in ${services}; do
      if systemctl list-unit-files 2>/dev/null | awk '{print $1}' | grep -qx "${svc}.service"; then
        printf '%-18s %s\n' "${svc}" "$(systemctl is-active "${svc}" 2>/dev/null || printf 'unknown')"
      fi
    done
  else
    warn "当前系统没有 systemctl，无法统一查询服务状态。"
  fi
}

option_restart_ssh_service() {
  local root_cmd=""
  if ! root_cmd="$(sudo_prefix)"; then
    err "需要 root 或 sudo 权限才能重启 SSH 服务。"
    return 1
  fi

  prompt_read -p "确认重启 SSH 服务？[y/N]: " confirm
  case "${confirm}" in
    y|Y) ;;
    *)
      warn "已取消。"
      return 0
      ;;
  esac

  if [ -n "${root_cmd}" ]; then
    ${root_cmd} systemctl restart sshd 2>/dev/null || \
    ${root_cmd} systemctl restart ssh 2>/dev/null || \
    ${root_cmd} service sshd restart 2>/dev/null || \
    ${root_cmd} service ssh restart 2>/dev/null
  else
    systemctl restart sshd 2>/dev/null || \
    systemctl restart ssh 2>/dev/null || \
    service sshd restart 2>/dev/null || \
    service ssh restart 2>/dev/null
  fi
  ok "SSH 服务已重启。"
}

option_recent_logins() {
  if have_cmd last; then
    last -a | sed -n '1,20p'
  else
    err "当前系统没有 last 命令。"
  fi
}

option_reboot_server() {
  local root_cmd=""
  if ! root_cmd="$(sudo_prefix)"; then
    err "需要 root 或 sudo 权限才能重启服务器。"
    return 1
  fi

  warn "重启服务器会导致当前 SSH 会话断开。"
  prompt_read -p "确认重启服务器？[y/N]: " confirm
  case "${confirm}" in
    y|Y) ;;
    *)
      warn "已取消。"
      return 0
      ;;
  esac

  if [ -n "${root_cmd}" ]; then
    ${root_cmd} reboot
  else
    reboot
  fi
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
  print_logo
  say "${C_BOLD}${C_CYAN}VPS 工具箱 v${TOOLBOX_VERSION}${C_RESET}"
  say "当前用户: ${CURRENT_USER}    主机: $(hostname)"
  say "密码登录模式: $(password_status_text)    公钥条数: $(count_authorized_keys)"
  say "--------------------------------------------------"
  say "1. SSH 登录管理"
  say "2. 系统信息查询"
  say "3. 应用市场"
  say "4. 系统清理"
  say "5. Docker 管理"
  say "6. 常用端口放行"
  say "7. 网络工具"
  say "8. 系统工具"
  say "9. 更新工具箱"
  say "0. 退出"
  say "--------------------------------------------------"
}

apps_menu_loop() {
  local choice=""
  while true; do
    clear 2>/dev/null || true
    print_logo
    say "${C_BOLD}${C_CYAN}应用市场${C_RESET}"
    say "--------------------------------------------------"
    say "1. 运行 vless-xhttp-reality-self"
    say "2. 查看 vless-xhttp-reality-self 说明"
    say "3. 安装 Docker + Nginx Proxy Manager"
    say "4. 查看 Docker + Nginx Proxy Manager 说明"
    say "5. 安装 NextTrace"
    say "6. 查看 NextTrace 说明"
    say "7. 启用 BBR"
    say "8. 查看 BBR 状态"
    say "0. 返回上一级"
    say "--------------------------------------------------"
    prompt_read -p "请输入你的选择: " choice
    printf '\n'
    case "${choice}" in
      1) option_run_vless_project ;;
      2) option_vless_project_info ;;
      3) option_run_npm_docker ;;
      4) option_npm_docker_info ;;
      5) option_run_nexttrace ;;
      6) option_nexttrace_info ;;
      7) option_enable_bbr ;;
      8) option_bbr_info ;;
      0) return 0 ;;
      *) warn "无效选项，请重新输入。" ;;
    esac
    pause
  done
}

docker_menu_loop() {
  local choice=""
  while true; do
    clear 2>/dev/null || true
    print_logo
    say "${C_BOLD}${C_CYAN}Docker 管理${C_RESET}"
    say "--------------------------------------------------"
    say "1. 查看 Docker 状态"
    say "2. 查看全部容器"
    say "3. 启动全部容器"
    say "4. 停止全部容器"
    say "5. 重启全部容器"
    say "6. 查看容器日志"
    say "7. Docker system prune"
    say "0. 返回上一级"
    say "--------------------------------------------------"
    prompt_read -p "请输入你的选择: " choice
    printf '\n'
    case "${choice}" in
      1) option_docker_status ;;
      2) option_docker_list_all ;;
      3) option_docker_start_all ;;
      4) option_docker_stop_all ;;
      5) option_docker_restart_all ;;
      6) option_docker_logs ;;
      7) option_docker_prune ;;
      0) return 0 ;;
      *) warn "无效选项，请重新输入。" ;;
    esac
    pause
  done
}

firewall_menu_loop() {
  local choice=""
  while true; do
    clear 2>/dev/null || true
    print_logo
    say "${C_BOLD}${C_CYAN}常用端口放行${C_RESET}"
    say "--------------------------------------------------"
    say "1. 放行 SSH (22/tcp)"
    say "2. 放行 HTTP (80/tcp)"
    say "3. 放行 HTTPS (443/tcp)"
    say "4. 一次放行 22/80/443"
    say "5. 放行自定义端口"
    say "6. 查看防火墙状态"
    say "0. 返回上一级"
    say "--------------------------------------------------"
    prompt_read -p "请输入你的选择: " choice
    printf '\n'
    case "${choice}" in
      1) allow_firewall_port 22 tcp ;;
      2) allow_firewall_port 80 tcp ;;
      3) allow_firewall_port 443 tcp ;;
      4) option_allow_common_ports ;;
      5) option_allow_custom_port ;;
      6) option_firewall_status ;;
      0) return 0 ;;
      *) warn "无效选项，请重新输入。" ;;
    esac
    pause
  done
}

network_menu_loop() {
  local choice=""
  while true; do
    clear 2>/dev/null || true
    print_logo
    say "${C_BOLD}${C_CYAN}网络工具${C_RESET}"
    say "--------------------------------------------------"
    say "1. 安装 NextTrace"
    say "2. 查看 NextTrace 说明"
    say "3. 启用 BBR"
    say "4. 查看 BBR 状态"
    say "5. Ping 测试"
    say "6. Traceroute / Tracepath"
    say "7. 查看本机路由"
    say "0. 返回上一级"
    say "--------------------------------------------------"
    prompt_read -p "请输入你的选择: " choice
    printf '\n'
    case "${choice}" in
      1) option_run_nexttrace ;;
      2) option_nexttrace_info ;;
      3) option_enable_bbr ;;
      4) option_bbr_info ;;
      5) option_ping_test ;;
      6) option_trace_test ;;
      7) option_show_ip_route ;;
      0) return 0 ;;
      *) warn "无效选项，请重新输入。" ;;
    esac
    pause
  done
}

system_tools_menu_loop() {
  local choice=""
  while true; do
    clear 2>/dev/null || true
    print_logo
    say "${C_BOLD}${C_CYAN}系统工具${C_RESET}"
    say "--------------------------------------------------"
    say "1. 查看监听端口"
    say "2. 查看高占用进程"
    say "3. 查看常见服务状态"
    say "4. 重启 SSH 服务"
    say "5. 查看最近登录"
    say "6. 重启服务器"
    say "0. 返回上一级"
    say "--------------------------------------------------"
    prompt_read -p "请输入你的选择: " choice
    printf '\n'
    case "${choice}" in
      1) option_show_listening_ports ;;
      2) option_show_top_processes ;;
      3) option_show_common_service_status ;;
      4) option_restart_ssh_service ;;
      5) option_recent_logins ;;
      6) option_reboot_server ;;
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
      4) option_system_cleanup; pause ;;
      5) docker_menu_loop ;;
      6) firewall_menu_loop ;;
      7) network_menu_loop ;;
      8) system_tools_menu_loop ;;
      9) option_update_toolbox ;;
      0) exit 0 ;;
      *) warn "无效选项，请重新输入。"; pause ;;
    esac
  done
}

main_loop
