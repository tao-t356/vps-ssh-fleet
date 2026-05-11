#!/usr/bin/env bash
set -euo pipefail

# TaoBox Speed
# Native TaoBox Speed installer.
# - TCP optimize: uses the preserved TCP menu-66 entry.
# - Argo VMess+WS: native cloudflared + Xray + Nginx implementation, no ArgoX install chain.

REPO_SLUG="tao-t356/TaoBox"
REPO_RAW_BASE="https://raw.githubusercontent.com/${REPO_SLUG}/main"
SPEED_SLAYER_VERSION="v1.0.0-taobox.4"
PROJECT_URL="https://github.com/${REPO_SLUG}"
DEFAULT_JSHOOK="123"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || echo .)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd 2>/dev/null || echo .)"

TCP_SCRIPT_LOCAL="${SCRIPT_DIR}/tcp-one-click-optimize.sh"
TCP_CORE_LIB_LOCAL="${SCRIPT_DIR}/lib/tcp-core.sh"

WORK_DIR="/etc/vps-argo-vmess"
CONFIG_FILE="${WORK_DIR}/install.conf"
LOG_FILE="${WORK_DIR}/install.log"
STATE_FILE="${WORK_DIR}/state.env"
INSTALLED_BIN="/usr/local/bin/speed"

DEFAULT_START_PORT="30000"
DEFAULT_NGINX_PORT="8001"
DEFAULT_WS_PATH="argox"
DEFAULT_NODE_NAME="VPS-Argo-VMess"

if [ -t 1 ]; then
  C_RESET='\033[0m'; C_BOLD='\033[1m'; C_DIM='\033[2m'; C_UNDERLINE='\033[4m'
  C_RED='\033[31m'; C_GREEN='\033[32m'; C_YELLOW='\033[33m'; C_BLUE='\033[34m'; C_MAGENTA='\033[35m'; C_CYAN='\033[36m'; C_WHITE='\033[97m'
else
  C_RESET=''; C_BOLD=''; C_DIM=''; C_UNDERLINE=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_MAGENTA=''; C_CYAN=''; C_WHITE=''
fi

cecho() { printf "%b%s%b\n" "$1" "$2" "$C_RESET"; }
info() { printf "%b◆ INFO%b %s\n" "$C_CYAN" "$C_RESET" "$*"; }
success() { printf "%b◆ DONE%b %s\n" "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf "%b◆ WARN%b %s\n" "$C_YELLOW" "$C_RESET" "$*"; }
err() { printf "%b◆ ERR %b %s\n" "$C_RED" "$C_RESET" "$*" >&2; }

line() { printf "%b%s%b\n" "$C_MAGENTA" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "$C_RESET"; }
section() { echo ""; line; printf "%b%s%b\n" "$C_BOLD$C_CYAN" " $1" "$C_RESET"; line; }

intro() {
  echo ""
  printf " %bTaoBox Speed%b  %bVersion:%b %s  %bProject:%b TaoBox\n" "$C_BOLD$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET" "$SPEED_SLAYER_VERSION" "$C_CYAN" "$C_RESET"
  printf " %bGitHub:%b %s\n" "$C_CYAN" "$C_RESET" "$PROJECT_URL"
  printf " %b入口：%b输入 %bspeed%b 进入控制台；重启后输入 %bspeed%b 自动续跑。\n" "$C_YELLOW" "$C_RESET" "$C_BOLD$C_GREEN" "$C_RESET" "$C_BOLD$C_GREEN" "$C_RESET"
  echo ""
}

render_header_once() {
  if [ "${SPEED_HEADER_RENDERED:-0}" = "1" ]; then
    return 0
  fi
  SPEED_HEADER_RENDERED=1
  intro
}

require_root() {
  if [ "$(id -u)" != "0" ]; then
    err "请使用 root 执行：sudo -i 后重新运行"
    exit 1
  fi
}

confirm_action() {
  local prompt="$1"
  local ans
  if [ "${ASSUME_Y:-0}" = "1" ]; then
    return 0
  fi
  printf "%b?%b %s %b[Y/n]%b " "$C_YELLOW" "$C_RESET" "$prompt" "$C_GREEN" "$C_RESET"
  read -r ans || ans=""
  ans="${ans:-Y}"
  [[ "$ans" =~ ^[Yy]$ ]]
}

get_effective_jshook() {
  printf '%s' "${JSHOOK:-${DEFAULT_JSHOOK}}"
}

download_repo_file() {
  local repo_path="$1"
  local out="$2"
  local jshook=""
  local ts=""

  jshook="$(get_effective_jshook)"
  ts="$(date +%s)"

  if curl -fsSL \
    -H "Accept: application/vnd.github.raw" \
    -H "Cache-Control: no-cache" \
    -H "jshook: ${jshook}" \
    "https://api.github.com/repos/${REPO_SLUG}/contents/${repo_path}?ref=main&ts=${ts}" \
    -o "$out"; then
    return 0
  fi

  curl -fsSL \
    -H "Cache-Control: no-cache" \
    -H "jshook: ${jshook}" \
    "${REPO_RAW_BASE}/${repo_path}?${ts}" \
    -o "$out"
}

download_script() {
  local raw_path="$1"
  local out
  out="$(mktemp /tmp/speed-slayer.XXXXXX.sh)"
  download_repo_file "$raw_path" "$out"
  bash -n "$out"
  chmod +x "$out"
  echo "$out"
}

fetch_or_run_script() {
  local local_path="$1"
  local raw_path="$2"
  shift 2
  if [ -s "$local_path" ]; then
    bash "$local_path" "$@"
  else
    local tmp_script
    tmp_script="$(download_script "$raw_path")"
    bash "$tmp_script" "$@"
  fi
}

install_shortcut() {
  require_root
  mkdir -p "$WORK_DIR"
  if [ -s "${BASH_SOURCE[0]}" ]; then
    local src_path dst_path
    src_path="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
    dst_path="$(readlink -f "$INSTALLED_BIN" 2>/dev/null || echo "$INSTALLED_BIN")"
    if [ "$src_path" != "$dst_path" ]; then
      cp "${BASH_SOURCE[0]}" "$INSTALLED_BIN"
    else
      download_repo_file "scripts/taobox-speed.sh" "$INSTALLED_BIN.tmp"
      bash -n "$INSTALLED_BIN.tmp"
      mv "$INSTALLED_BIN.tmp" "$INSTALLED_BIN"
    fi
  else
    download_repo_file "scripts/taobox-speed.sh" "$INSTALLED_BIN"
  fi
  chmod +x "$INSTALLED_BIN"
  success "已安装快捷命令：speed"
  echo "以后可直接执行："
  echo "  speed"
  echo "  speed --force-all"
}

save_pending_state() {
  local next_action="${1:-continue}"
  require_root
  mkdir -p "$WORK_DIR"
  cat > "$STATE_FILE" <<EOF
PENDING_CONTINUE=1
CREATED_AT=$(date -Is 2>/dev/null || date)
NEXT_ACTION=${next_action}
EOF
  chmod 600 "$STATE_FILE"
}

cdn_recommendation() {
  echo ""
  line
  printf "%b%s%b
" "$C_BOLD$C_YELLOW" " 推荐下一步：本地优选 Cloudflare CDN" "$C_RESET"
  printf "  节点已经生成，建议继续在本地运行 %bCloudflareSpeedTest%b，选择延迟更低、速度更稳的 CDN IP。
" "$C_GREEN" "$C_RESET"
  printf "  项目地址：%bhttps://github.com/XIU2/CloudflareSpeedTest/releases%b
" "$C_UNDERLINE$C_CYAN" "$C_RESET"
  line
}

clear_state() {
  require_root
  rm -f "$STATE_FILE"
  success "已清理续跑状态：$STATE_FILE"
  cdn_recommendation
}

clear_state_silent() {
  rm -f "$STATE_FILE" 2>/dev/null || true
}

is_xanmod_kernel() {
  uname -r | grep -qi xanmod
}

show_continue_hint() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo " 下一步"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "已完成内核组件安装，需要重启服务器加载新内核。"
  echo "重启后只需要执行："
  echo ""
  echo "  speed"
  echo ""
  echo "TaoBox Speed 会自动识别续跑状态，继续完成：TCP 网络调优 + Argo VMess+WS 安装 + 健康检查。"
}

confirm_reboot_now() {
  show_continue_hint
  local choice="Y"
  if [ "${ASSUME_Y:-0}" = "1" ]; then
    choice="Y"
  elif [ -t 0 ]; then
    printf "%b?%b 是否现在重启服务器？默认回车 = Y %b[Y/n]%b " "$C_YELLOW" "$C_RESET" "$C_GREEN" "$C_RESET"
    read -r choice || choice=""
    choice="${choice:-Y}"
  else
    warn "非交互环境：已保存续跑状态，请手动重启后执行 speed。"
    return 0
  fi
  case "$choice" in
    [Yy]*)
      success "即将重启服务器。重启后执行：speed"
      sync || true
      if command -v systemctl >/dev/null 2>&1; then
        systemctl reboot
      else
        reboot
      fi
      ;;
    *)
      warn "已暂不重启。准备好后执行：reboot；重启后执行：speed"
      ;;
  esac
}

run_with_progress() {
  local title="$1"
  shift
  local log_file="$1"
  shift
  mkdir -p "$(dirname "$log_file")"
  section "$title"
  "$@" >"$log_file" 2>&1 &
  local pid=$!
  local frames=('▱▱▱▱▱▱▱▱▱▱ 0%' '▰▱▱▱▱▱▱▱▱▱ 10%' '▰▰▱▱▱▱▱▱▱▱ 20%' '▰▰▰▱▱▱▱▱▱▱ 30%' '▰▰▰▰▱▱▱▱▱▱ 40%' '▰▰▰▰▰▱▱▱▱▱ 50%' '▰▰▰▰▰▰▱▱▱▱ 60%' '▰▰▰▰▰▰▰▱▱▱ 70%' '▰▰▰▰▰▰▰▰▱▱ 80%' '▰▰▰▰▰▰▰▰▰▱ 90%')
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r%b◆ RUN %b%s" "$C_CYAN" "$C_RESET" "${frames[$((i % ${#frames[@]}))]}"
    i=$((i + 1))
    sleep 1
  done
  set +e
  wait "$pid"
  local code=$?
  set -e
  if [ "$code" -eq 0 ]; then
    printf "\r%b◆ DONE%b %s\n" "$C_GREEN" "$C_RESET" "▰▰▰▰▰▰▰▰▰▰ 100%"
  else
    printf "\r%b◆ FAIL%b 见日志：%s\n" "$C_RED" "$C_RESET" "$log_file"
    tail -n 40 "$log_file" || true
    return "$code"
  fi
}

tcp_value() { sysctl -n "$1" 2>/dev/null || echo "unknown"; }

tcp_status_panel() {
  section "TaoBox Speed · TCP 状态"
  printf "%b%-18s%b %s\n" "$C_CYAN" "Kernel" "$C_RESET" "$(uname -r)"
  printf "%b%-18s%b %s\n" "$C_CYAN" "XanMod" "$C_RESET" "$(is_xanmod_kernel && echo YES || echo NO)"
  printf "%b%-18s%b %s\n" "$C_CYAN" "Congestion" "$C_RESET" "$(tcp_value net.ipv4.tcp_congestion_control)"
  printf "%b%-18s%b %s\n" "$C_CYAN" "Qdisc" "$C_RESET" "$(tcp_value net.core.default_qdisc)"
  printf "%b%-18s%b %s\n" "$C_CYAN" "IPv6 disabled" "$C_RESET" "$(tcp_value net.ipv6.conf.all.disable_ipv6)"
}

tcp_plan_panel() {
  section "TaoBox Speed · TCP 施工计划"
  if is_xanmod_kernel; then
    progress_step 10 "已在 XanMod 内核：跳过内核安装阶段"
    progress_step 35 "执行 BBR v3 / FQ 网络参数优化"
    progress_step 55 "执行 DNS 净化 / 网络稳定性修复"
    progress_step 75 "执行 Realm 首连超时修复"
    progress_step 90 "可选 IPv6 禁用"
    progress_step 100 "输出 TCP 状态摘要"
  else
    progress_step 10 "当前不是 XanMod：准备安装 XanMod + BBR v3 内核"
    progress_step 60 "安装完成后需要重启"
    progress_step 100 "重启后执行 speed 自动继续后续 TCP 调优 + Argo 安装"
  fi
}

detect_x64_level() {
  local flags level="1"
  flags="$(grep -m1 '^flags' /proc/cpuinfo 2>/dev/null || true)"
  if echo "$flags" | grep -qw 'avx512f'; then level="4"
  elif echo "$flags" | grep -qw 'avx2'; then level="3"
  elif echo "$flags" | grep -qw 'sse4_2'; then level="2"
  fi
  echo "$level"
}

xanmod_available_packages() {
  apt-cache search '^linux-xanmod' 2>/dev/null | awk '{print $1}' | sort -u
}

xanmod_pkg_available() {
  local pkg="$1"
  xanmod_available_packages | grep -qx "${pkg}"
}

download_xanmod_gpg_key() {
  local key_tmp="$1"
  local jshook
  jshook="$(get_effective_jshook)"

  # 官方 dl.xanmod.org 近期可能触发 Cloudflare challenge，先按官方地址尝试，
  # 失败后自动切换到已知 GitHub raw 镜像，避免整个一键流程卡死在 GPG key。
  if wget -qO "$key_tmp" --header="jshook: ${jshook}" "https://dl.xanmod.org/archive.key"; then
    [ -s "$key_tmp" ] && return 0
  fi

  warn "XanMod 官方 GPG key 下载失败，尝试 GitHub 镜像源。"
  wget -qO "$key_tmp" \
    --header="jshook: ${jshook}" \
    "https://raw.githubusercontent.com/kejilion/sh/main/archive.key"
  [ -s "$key_tmp" ]
}

select_xanmod_pkg() {
  local level="$1" n pkg
  local candidates=()

  for n in "$level" 3 2 1; do
    [ "$n" -gt "$level" ] 2>/dev/null && continue
    [ "$n" -eq 1 ] && continue
    candidates+=("linux-xanmod-x64v${n}")
  done

  for n in "$level" 3 2 1; do
    [ "$n" -gt "$level" ] 2>/dev/null && continue
    candidates+=("linux-xanmod-lts-x64v${n}")
  done

  for n in "$level" 3 2 1; do
    [ "$n" -gt "$level" ] 2>/dev/null && continue
    [ "$n" -eq 1 ] && continue
    candidates+=("linux-xanmod-edge-x64v${n}")
  done

  candidates+=("linux-xanmod")

  for pkg in "${candidates[@]}"; do
    if xanmod_pkg_available "$pkg"; then
      echo "$pkg"
      return 0
    fi
  done
  return 1
}

show_xanmod_candidates() {
  xanmod_available_packages | awk '{print "  - "$1}' | head -30 || true
}

native_install_xanmod_kernel() {
  section "TaoBox Speed · 内核加速组件"
  if [ "$(uname -m)" != "x86_64" ]; then
    warn "当前架构暂未适配自动内核安装，将切换到兼容安装路径。"
    return 2
  fi
  if [ ! -r /etc/os-release ]; then
    err "无法识别系统：缺少 /etc/os-release"
    return 2
  fi
  # shellcheck disable=SC1091
  . /etc/os-release
  if [ "${ID:-}" != "debian" ] && [ "${ID:-}" != "ubuntu" ]; then
    warn "当前系统暂未适配自动内核安装，将切换到兼容安装路径。"
    return 2
  fi

  progress_step 10 "安装依赖：wget / gnupg / ca-certificates"
  apt-get update -y >>"$WORK_DIR/kernel-install.log" 2>&1 || true
  apt-get install -y wget gnupg ca-certificates >>"$WORK_DIR/kernel-install.log" 2>&1

  progress_step 25 "导入 XanMod GPG key"
  local keyring="/usr/share/keyrings/xanmod-archive-keyring.gpg"
  local key_tmp
  key_tmp="$(mktemp)"
  if ! download_xanmod_gpg_key "$key_tmp" >>"$WORK_DIR/kernel-install.log" 2>&1; then
    err "XanMod GPG key 下载失败"
    rm -f "$key_tmp"
    return 1
  fi
  gpg --dearmor -o "$keyring" --yes < "$key_tmp" >>"$WORK_DIR/kernel-install.log" 2>&1
  rm -f "$key_tmp"

  progress_step 40 "写入临时 XanMod APT 源"
  local repo_file="/etc/apt/sources.list.d/xanmod-release.list"
  echo "deb [signed-by=${keyring}] https://deb.xanmod.org releases main" > "$repo_file"

  progress_step 55 "检测 CPU x86-64-v 等级"
  local level pkg install_ok=0
  level="$(detect_x64_level)"
  apt-get update -y >>"$WORK_DIR/kernel-install.log" 2>&1 || true
  if ! pkg="$(select_xanmod_pkg "$level")"; then
    warn "未找到可安装的 XanMod 内核包，可能是 deb.xanmod.org 被 Cloudflare challenge 或网络策略拦截。"
    warn "将清理临时 XanMod APT 源，并允许后续自动降级到系统自带内核 BBR 调优。"
    echo "可用包候选："
    show_xanmod_candidates
    echo "日志：$WORK_DIR/kernel-install.log"
    rm -f "$repo_file"
    apt-get update -y >>"$WORK_DIR/kernel-install.log" 2>&1 || true
    return 3
  fi
  info "CPU 等级：x86-64-v${level}；选择内核包：${pkg}"

  progress_step 70 "安装 XanMod 内核包"
  if apt-get install -y "$pkg" >>"$WORK_DIR/kernel-install.log" 2>&1; then
    install_ok=1
  else
    warn "${pkg} 安装失败，尝试通用 XanMod 内核包。"
    if [ "$pkg" != "linux-xanmod" ] && xanmod_pkg_available "linux-xanmod" && apt-get install -y linux-xanmod >>"$WORK_DIR/kernel-install.log" 2>&1; then
      pkg="linux-xanmod"
      install_ok=1
    fi
  fi
  [ "$install_ok" -eq 1 ] || { err "XanMod 内核包安装失败，日志：$WORK_DIR/kernel-install.log"; return 1; }

  progress_step 88 "验证内核包安装"
  if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
    if ! dpkg -l 2>/dev/null | grep -qE '^ii\s+linux-(image|headers)-.*xanmod'; then
      err "内核包安装验证失败：${pkg}"
      echo "日志：$WORK_DIR/kernel-install.log"
      return 1
    fi
  fi

  progress_step 95 "清理临时 XanMod APT 源"
  rm -f "$repo_file"
  apt-get update -y >>"$WORK_DIR/kernel-install.log" 2>&1 || true

  progress_step 100 "XanMod 安装完成，重启后执行 speed 继续"
  return 0
}

run_tcp_backend_visible() {
  mkdir -p "$WORK_DIR"
  if [ "${SPEED_KERNEL_MODE:-native}" = "native" ]; then
    set +e
    native_install_xanmod_kernel
    local code=$?
    if [ "$code" -eq 0 ]; then
      set -e
      return 0
    elif [ "$code" -ne 2 ]; then
      # 保持 errexit 关闭返回给外层，让外层能识别 code=3 并进入
      # stock-kernel fallback；否则 `set -e` 会在非零 return 处直接退出。
      return "$code"
    fi
    set -e
  fi
  warn "正在切换到兼容安装路径。"
  fetch_or_run_script "$TCP_SCRIPT_LOCAL" "scripts/tcp-one-click-optimize.sh"
}

detect_swap_status() {
  local total used
  total="$(free -m 2>/dev/null | awk '/^Swap:/ {print $2+0}')"
  used="$(free -m 2>/dev/null | awk '/^Swap:/ {print $3+0}')"
  echo "${total:-0}:${used:-0}"
}

detect_memory_mb() {
  free -m 2>/dev/null | awk '/^Mem:/ {print $2+0}'
}

install_speedtest_cli() {
  command -v speedtest >/dev/null 2>&1 && return 0
  local arch url tmp
  case "$(uname -m)" in
    x86_64|amd64) arch="x86_64" ;;
    aarch64|arm64) arch="aarch64" ;;
    *) return 1 ;;
  esac
  url="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-${arch}.tgz"
  tmp="$(mktemp -d)"
  if curl -LfsS "$url" -o "$tmp/speedtest.tgz" 2>/dev/null || wget -q "$url" -O "$tmp/speedtest.tgz" 2>/dev/null; then
    tar -xzf "$tmp/speedtest.tgz" -C "$tmp" >/dev/null 2>&1 || { rm -rf "$tmp"; return 1; }
    [ -x "$tmp/speedtest" ] || { rm -rf "$tmp"; return 1; }
    mv "$tmp/speedtest" /usr/local/bin/speedtest
    chmod +x /usr/local/bin/speedtest
    rm -rf "$tmp"
    return 0
  fi
  rm -rf "$tmp"
  return 1
}

speedtest_bandwidth_mbps() {
  install_speedtest_cli || return 1
  local servers sid out mbps server_name attempt=0
  : > "$WORK_DIR/speedtest.log"
  echo "TaoBox Speed Speedtest - $(date -Is 2>/dev/null || date)" >> "$WORK_DIR/speedtest.log"
  servers="$(timeout 25 speedtest --accept-license --accept-gdpr --servers 2>/dev/null | sed -nE 's/^[[:space:]]*([0-9]+).*/\1/p' | head -n 8 || true)"
  if [ -z "$servers" ]; then
    servers="auto"
  fi
  for sid in $servers; do
    attempt=$((attempt + 1))
    if [ "$sid" = "auto" ]; then
      out="$(timeout 120 speedtest --accept-license --accept-gdpr 2>&1 || true)"
    else
      out="$(timeout 120 speedtest --accept-license --accept-gdpr --server-id="$sid" 2>&1 || true)"
    fi
    {
      echo ""
      echo "===== attempt ${attempt} server ${sid} ====="
      echo "$out"
    } >> "$WORK_DIR/speedtest.log"
    mbps="$(printf '%s\n' "$out" | awk '/Upload:/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+(\.[0-9]+)?$/){print int($i); exit}}')"
    server_name="$(printf '%s\n' "$out" | sed -n 's/.*Server:[[:space:]]*//p' | head -1 | sed 's/[[:space:]]*$//')"
    if [ -n "$mbps" ] && [ "$mbps" -gt 0 ] 2>/dev/null && ! printf '%s\n' "$out" | grep -qiE 'FAILED|error|timeout'; then
      SPEEDTEST_SERVER="$server_name"
      echo "$mbps"
      return 0
    fi
  done
  return 1
}

netcheck_one() {
  local label="$1" cmd="$2" hint="${3:-}"
  if eval "$cmd" >/dev/null 2>&1; then
    printf "%b[OK]%b   %s\n" "$C_GREEN" "$C_RESET" "$label"
  else
    printf "%b[FAIL]%b %s\n" "$C_RED" "$C_RESET" "$label"
    [ -n "$hint" ] && printf "       建议：%s\n" "$hint"
    return 1
  fi
}

repo_connectivity_check() {
  local tmp=""
  tmp="$(mktemp /tmp/taobox-repo-check.XXXXXX)"
  if download_repo_file "README.md" "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

run_netcheck() {
  require_root
  section "TaoBox Speed · Netcheck"
  local failed=0
  mkdir -p "$WORK_DIR"
  {
    echo "TaoBox Speed Netcheck - $(date -Is 2>/dev/null || date)"
    echo "Kernel: $(uname -r)"
    echo "Default route: $(ip route show default 2>/dev/null | head -1)"
    echo "IPv4: $(curl -4fsS --max-time 8 https://api.ipify.org 2>/dev/null || echo unknown)"
    echo "IPv6: $(curl -6fsS --max-time 8 https://api64.ipify.org 2>/dev/null || echo unavailable)"
  } > "$WORK_DIR/netcheck.log"

  netcheck_one "IPv4 出站" 'curl -4fsS --max-time 8 https://api.ipify.org' "检查 DNS / 默认路由 / 防火墙" || failed=1
  netcheck_one "DNS 解析" 'getent hosts github.com || nslookup github.com' "检查 /etc/resolv.conf 或 systemd-resolved" || failed=1
  netcheck_one "TaoBox Repo 访问" 'repo_connectivity_check' "GitHub 访问异常会影响自更新与 TCP 回退脚本下载" || failed=1
  netcheck_one "Cloudflare 访问" 'curl -fsS --max-time 12 https://www.cloudflare.com/cdn-cgi/trace' "Cloudflare 异常会影响 Argo Tunnel" || failed=1
  netcheck_one "HTTPS/443 出站" 'timeout 8 bash -c "</dev/tcp/1.1.1.1/443"' "检查机房出站 443" || failed=1
  if command -v ping >/dev/null 2>&1; then
    netcheck_one "ICMP 延迟" 'ping -c 3 -W 2 1.1.1.1' "ICMP 失败不一定影响代理，但可用于判断线路" || true
  fi
  echo "日志：$WORK_DIR/netcheck.log"
  [ "$failed" -eq 0 ] && success "Netcheck 完成：关键出站链路正常。" || { err "Netcheck 完成：发现关键链路异常。"; return 1; }
}

run_speedtest_cmd() {
  require_root
  section "TaoBox Speed · Speedtest"
  mkdir -p "$WORK_DIR"
  info "正在测速，结果用于评估上行带宽；失败不会影响安装。"
  if ! install_speedtest_cli; then
    err "speedtest CLI 安装失败。"
    echo "日志：$WORK_DIR/speedtest.log"
    return 1
  fi
  local measured
  if measured="$(speedtest_bandwidth_mbps)"; then
    local color
    color="$(bandwidth_color "$measured")"
    printf "%b◆ SPEEDTEST%b Upload: %b%s Mbps%b
" "$C_GREEN" "$C_RESET" "$color" "$measured" "$C_RESET"
    [ -n "${SPEEDTEST_SERVER:-}" ] && echo "Server: $SPEEDTEST_SERVER"
    echo "日志：$WORK_DIR/speedtest.log"
  else
    err "Speedtest 测速失败。日志：$WORK_DIR/speedtest.log"
    tail -n 80 "$WORK_DIR/speedtest.log" 2>/dev/null || true
    return 1
  fi
}

detect_bandwidth_profile() {
  BANDWIDTH_MBPS=""
  BANDWIDTH_SOURCE="default"
  BANDWIDTH_NOTE=""
  if [ -n "${SPEED_BANDWIDTH_MBPS:-}" ] && echo "$SPEED_BANDWIDTH_MBPS" | grep -Eq '^[0-9]+$'; then
    BANDWIDTH_MBPS="$SPEED_BANDWIDTH_MBPS"
    BANDWIDTH_SOURCE="manual"
    BANDWIDTH_NOTE="由 SPEED_BANDWIDTH_MBPS 指定"
    return 0
  fi
  if [ "${SPEED_AUTO_SPEEDTEST:-1}" = "1" ]; then
    progress_step 18 "正在执行 Speedtest 带宽探测"
    local measured
    if measured="$(speedtest_bandwidth_mbps 2>/dev/null)" && [ -n "$measured" ]; then
      BANDWIDTH_MBPS="$measured"
      BANDWIDTH_SOURCE="measured"
      BANDWIDTH_NOTE="Ookla Speedtest Upload 实测${SPEEDTEST_SERVER:+ · $SPEEDTEST_SERVER}"
      return 0
    fi
    BANDWIDTH_NOTE="Speedtest 未成功，已回退默认值；日志：$WORK_DIR/speedtest.log"
  else
    BANDWIDTH_NOTE="已关闭自动测速 SPEED_AUTO_SPEEDTEST=0"
  fi
  BANDWIDTH_MBPS="1000"
  BANDWIDTH_SOURCE="default"
  return 0
}

calculate_tcp_buffer_mb() {
  local bandwidth="$1" mem_mb="$2" region="${SPEED_REGION:-global}" buffer=128 cap
  if [ "$bandwidth" -le 200 ] 2>/dev/null; then buffer=32
  elif [ "$bandwidth" -le 500 ] 2>/dev/null; then buffer=64
  elif [ "$bandwidth" -le 1000 ] 2>/dev/null; then buffer=128
  elif [ "$bandwidth" -le 2500 ] 2>/dev/null; then buffer=256
  elif [ "$bandwidth" -le 5000 ] 2>/dev/null; then buffer=384
  else buffer=512
  fi
  case "$region" in
    asia|local) : ;;
    *) buffer=$((buffer + buffer / 2)) ;;
  esac
  if [ "$mem_mb" -lt 1024 ] 2>/dev/null; then cap=32
  elif [ "$mem_mb" -lt 2048 ] 2>/dev/null; then cap=64
  elif [ "$mem_mb" -lt 4096 ] 2>/dev/null; then cap=128
  elif [ "$mem_mb" -lt 8192 ] 2>/dev/null; then cap=256
  else cap=512
  fi
  [ "$buffer" -gt "$cap" ] && buffer="$cap"
  echo "$buffer"
}

clean_tcp_conflicts() {
  [ -f /etc/sysctl.conf ] && cp /etc/sysctl.conf "$WORK_DIR/sysctl.conf.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
  if [ -f /etc/sysctl.conf ]; then
    sed -i '/^net\.core\.rmem_max/s/^/# TaoBox Speed disabled conflict: /' /etc/sysctl.conf 2>/dev/null || true
    sed -i '/^net\.core\.wmem_max/s/^/# TaoBox Speed disabled conflict: /' /etc/sysctl.conf 2>/dev/null || true
    sed -i '/^net\.ipv4\.tcp_rmem/s/^/# TaoBox Speed disabled conflict: /' /etc/sysctl.conf 2>/dev/null || true
    sed -i '/^net\.ipv4\.tcp_wmem/s/^/# TaoBox Speed disabled conflict: /' /etc/sysctl.conf 2>/dev/null || true
  fi
  rm -f /etc/sysctl.d/99-sysctl.conf 2>/dev/null || true
  find /etc/sysctl.d -maxdepth 1 -type f ! -name '99-speed-slayer-tcp.conf' -print0 2>/dev/null | while IFS= read -r -d '' conf; do
    if grep -qE '^(net\.core\.(rmem_max|wmem_max)|net\.ipv4\.tcp_(rmem|wmem|congestion_control))' "$conf" 2>/dev/null; then
      cp "$conf" "${conf}.speed-slayer.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
      sed -i '/^net\.core\.rmem_max/s/^/# TaoBox Speed disabled conflict: /; /^net\.core\.wmem_max/s/^/# TaoBox Speed disabled conflict: /; /^net\.ipv4\.tcp_rmem/s/^/# TaoBox Speed disabled conflict: /; /^net\.ipv4\.tcp_wmem/s/^/# TaoBox Speed disabled conflict: /; /^net\.ipv4\.tcp_congestion_control/s/^/# TaoBox Speed disabled conflict: /' "$conf" 2>/dev/null || true
    fi
  done
}

bandwidth_color() {
  local mbps="$1"
  if [ "$mbps" -ge 2000 ] 2>/dev/null; then echo "$C_GREEN"
  elif [ "$mbps" -ge 500 ] 2>/dev/null; then echo "$C_CYAN"
  elif [ "$mbps" -ge 100 ] 2>/dev/null; then echo "$C_YELLOW"
  else echo "$C_RED"
  fi
}

native_speed_tcp_tune() {
  local ipv6_choice="$1"
  section "TaoBox Speed · TCP 加速配置"
  mkdir -p "$WORK_DIR"

  progress_step 8 "[步骤 1/6] 检测虚拟内存（SWAP）配置"
  local mem_mb swap_info swap_total swap_used vm_swappiness vm_dirty_ratio vm_min_free_kbytes
  mem_mb="$(detect_memory_mb)"; mem_mb="${mem_mb:-1024}"
  swap_info="$(detect_swap_status)"; swap_total="${swap_info%%:*}"; swap_used="${swap_info##*:}"
  printf "Memory=%b%sMB%b Swap=%b%sMB%b Used=%b%sMB%b\n" "$C_GREEN" "$mem_mb" "$C_RESET" "$C_YELLOW" "$swap_total" "$C_RESET" "$C_CYAN" "$swap_used" "$C_RESET"
  vm_swappiness=5; vm_dirty_ratio=15; vm_min_free_kbytes=65536
  if [ "$mem_mb" -lt 2048 ] 2>/dev/null; then
    vm_swappiness=20; vm_dirty_ratio=20; vm_min_free_kbytes=32768
  fi
  [ "$swap_total" -eq 0 ] 2>/dev/null && warn "未检测到 SWAP；小内存 VPS 建议配置 512MB-1GB SWAP。"

  progress_step 20 "[步骤 2/6] 检测服务器带宽并计算最优缓冲区"
  local bandwidth buffer_mb buffer_bytes region
  detect_bandwidth_profile
  bandwidth="$BANDWIDTH_MBPS"
  region="${SPEED_REGION:-global}"
  buffer_mb="$(calculate_tcp_buffer_mb "$bandwidth" "$mem_mb")"
  buffer_bytes=$((buffer_mb * 1024 * 1024))
  local bw_color
  bw_color="$(bandwidth_color "$bandwidth")"
  printf "Bandwidth=%b%sMbps%b Source=%s Region=%s Buffer=%sMB
" "$bw_color" "$bandwidth" "$C_RESET" "$BANDWIDTH_SOURCE" "$region" "$buffer_mb"
  [ -n "$BANDWIDTH_NOTE" ] && echo "BandwidthNote=${BANDWIDTH_NOTE}"

  progress_step 34 "[步骤 3/6] 清理配置冲突"
  clean_tcp_conflicts

  progress_step 50 "[步骤 4/6] 创建配置文件"
  modprobe tcp_bbr >/dev/null 2>&1 || true
  cat > /etc/modules-load.d/99-speed-slayer-bbr.conf <<'EOF'
tcp_bbr
EOF
  cat > /etc/sysctl.d/99-speed-slayer-tcp.conf <<EOF
# TaoBox Speed native TCP profile
# Generated on $(date)
# Bandwidth: ${bandwidth} Mbps | Region: ${region} | Memory: ${mem_mb} MB | Buffer: ${buffer_mb} MB
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_synack_retries = 3
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_abort_on_overflow = 0
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 250000
net.core.rmem_max = ${buffer_bytes}
net.core.wmem_max = ${buffer_bytes}
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.ipv4.tcp_rmem = 4096 87380 ${buffer_bytes}
net.ipv4.tcp_wmem = 4096 65536 ${buffer_bytes}
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
net.ipv4.tcp_syncookies = 1
net.ipv4.ip_local_port_range = 1024 65535
vm.swappiness = ${vm_swappiness}
vm.dirty_ratio = ${vm_dirty_ratio}
vm.dirty_background_ratio = 5
vm.overcommit_memory = 1
vm.min_free_kbytes = ${vm_min_free_kbytes}
vm.vfs_cache_pressure = 50
kernel.sched_autogroup_enabled = 0
kernel.numa_balancing = 0
EOF

  progress_step 66 "[步骤 5/6] 应用所有优化参数"
  local sysctl_output sysctl_rc
  sysctl_output="$(sysctl -p /etc/sysctl.d/99-speed-slayer-tcp.conf 2>&1)"; sysctl_rc=$?
  if [ "$sysctl_rc" -ne 0 ]; then
    warn "部分 sysctl 参数应用失败，已继续保留支持项："
    echo "$sysctl_output" | grep -iE 'error|invalid|unknown|cannot|permission' | head -6 || true
  fi

  progress_step 76 "应用 FQ 队列与持久化限制"
  local dev
  for dev in $(ls /sys/class/net 2>/dev/null | grep -vE '^(lo|docker|veth|br-|virbr|tun|tap)'); do
    tc qdisc replace dev "$dev" root fq >/dev/null 2>&1 || true
    printf "qdisc[%b%s%b]=%b%s%b\n" "$C_YELLOW" "$dev" "$C_RESET" "$C_CYAN" "$(tc qdisc show dev "$dev" 2>/dev/null | head -1 || true)" "$C_RESET"
  done
  if ! grep -q 'TaoBox Speed file descriptor limits' /etc/security/limits.conf 2>/dev/null; then
    cat >> /etc/security/limits.conf <<'EOF'
# TaoBox Speed file descriptor limits
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF
  fi
  mkdir -p /etc/systemd/system.conf.d /etc/systemd/user.conf.d /etc/systemd/resolved.conf.d
  cat > /etc/systemd/system.conf.d/99-speed-slayer-limits.conf <<'EOF'
[Manager]
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=1048576
EOF
  cat > /etc/systemd/user.conf.d/99-speed-slayer-limits.conf <<'EOF'
[Manager]
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=1048576
EOF
  systemctl daemon-reexec >/dev/null 2>&1 || true

  progress_step 84 "DNS 稳定性配置"
  cat > /etc/systemd/resolved.conf.d/99-speed-slayer-dns.conf <<'EOF'
[Resolve]
DNS=1.1.1.1 8.8.8.8
FallbackDNS=9.9.9.9 1.0.0.1
DNSSEC=no
EOF
  systemctl restart systemd-resolved >/dev/null 2>&1 || true

  progress_step 90 "IPv6 策略"
  if [[ "$ipv6_choice" =~ ^[Yy]$ ]]; then
    cat > /etc/sysctl.d/99-speed-slayer-disable-ipv6.conf <<'EOF'
# TaoBox Speed optional IPv6 disable
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
    sysctl -p /etc/sysctl.d/99-speed-slayer-disable-ipv6.conf >/dev/null 2>&1 || true
  else
    rm -f /etc/sysctl.d/99-speed-slayer-disable-ipv6.conf
  fi

  progress_step 100 "[步骤 6/6] 验证优化结果"
  echo "congestion=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
  echo "qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo unknown)"
  echo "buffer=${buffer_mb}MB nofile=$(ulimit -n 2>/dev/null || echo unknown)"
}

prepare_tcp_core_lib() {
  local src="$1" out
  out="$(mktemp /tmp/speed-slayer-tcp-core.XXXXXX.sh)"
  # 生成可加载的 TCP 函数库，避免启动交互菜单。
  sed '/^[[:space:]]*main[[:space:]]*"\$@"[[:space:]]*$/d' "$src" > "$out"
  bash -n "$out"
  echo "$out"
}

run_tcp_backend_silent() {
  local ipv6_choice="$1"
  if [ "${SPEED_TCP_MODE:-native}" = "native" ]; then
    native_speed_tcp_tune "$ipv6_choice"
    return 0
  fi

  local src core
  if [ -s "$TCP_CORE_LIB_LOCAL" ]; then
    core="$TCP_CORE_LIB_LOCAL"
  else
    if [ -s "$TCP_SCRIPT_LOCAL" ]; then
      src="$TCP_SCRIPT_LOCAL"
    else
      src="$(download_script "scripts/tcp-one-click-optimize.sh")"
    fi
    core="$(prepare_tcp_core_lib "$src")"
  fi
  # shellcheck disable=SC1090
  source "$core"
  AUTO_MODE=1
  echo "[15%] TCP 核心优化"
  bbr_configure_direct
  echo "[35%] DNS 与网络稳定性"
  dns_purify_and_harden
  echo "[55%] 首连稳定性修复"
  realm_fix_timeout
  if [[ "$ipv6_choice" =~ ^[Yy]$ ]]; then
    echo "[75%] IPv6 策略应用"
    disable_ipv6_permanent
  else
    echo "[75%] 跳过 IPv6 永久禁用"
  fi
  AUTO_MODE=""
}

run_tcp_optimize() {
  require_root
  render_header_once
  tcp_status_panel
  tcp_plan_panel
  warn "TCP 阶段会修改内核 / sysctl / DNS / IPv6 等系统网络配置，且可能要求重启。"
  if ! confirm_action "是否继续？默认回车 = Y"; then
    warn "已取消 TCP 优化。"
    return 0
  fi
  install_shortcut || true

  if ! is_xanmod_kernel; then
    if [ "${SPEED_FORCE_STOCK_FALLBACK:-0}" = "1" ]; then
      clear_state_silent
      SPEED_STOCK_FALLBACK_ACTIVE=1
      warn "已按续跑/降级策略跳过 XanMod 安装，使用当前系统内核加载 tcp_bbr 并继续 TCP 调优。"
      warn "此模式不是 XanMod/BBRv3；但可避免一键流程中断，后续节点部署会继续执行。"
    else
      save_pending_state "${SPEED_NEXT_ACTION:-continue}"
      section "安装 XanMod + BBR v3 内核"
      warn "当前不是 XanMod 内核。此阶段保留核心输出，避免隐藏安装失败或重启提示。"
      local kernel_install_code=0
      set +e
      run_tcp_backend_visible
      kernel_install_code=$?
      set -e
      if [ "$kernel_install_code" -eq 0 ]; then
        confirm_reboot_now
        return 0
      fi
      if [ "$kernel_install_code" -eq 3 ] && [ "${SPEED_ALLOW_STOCK_FALLBACK:-1}" = "1" ]; then
        clear_state_silent
        SPEED_STOCK_FALLBACK_ACTIVE=1
        warn "XanMod APT 源不可用，已启用降级路径：使用当前系统内核加载 tcp_bbr 并继续 TCP 调优。"
        warn "此模式不是 XanMod/BBRv3；但可避免一键流程中断，后续节点部署会继续执行。"
      else
        clear_state_silent
        err "内核组件安装失败，日志：$WORK_DIR/kernel-install.log"
        return 1
      fi
    fi
  fi

  local ipv6_choice="Y"
  if [ "${ASSUME_Y:-0}" != "1" ]; then
    printf "%b?%b TCP 调优最后是否永久禁用 IPv6？默认回车 = Y %b[Y/n]%b " "$C_YELLOW" "$C_RESET" "$C_GREEN" "$C_RESET"
    read -r ipv6_choice || ipv6_choice=""
    ipv6_choice="${ipv6_choice:-Y}"
  fi

  section "执行 TCP 网络调优"
  info "正在应用 TaoBox Speed TCP 加速配置。"
  if [ "${SPEED_TCP_MODE:-native}" = "native" ]; then
    native_speed_tcp_tune "$ipv6_choice" 2>&1 | tee "$WORK_DIR/tcp-optimize.log"
  else
    run_with_progress "TaoBox Speed TCP 加速配置" "$WORK_DIR/tcp-optimize.log" run_tcp_backend_silent "$ipv6_choice"
  fi
  progress_step 100 "TCP 调优完成"
  tcp_status_panel || true
}

run_tcp_optimize_only() {
  SPEED_NEXT_ACTION=tcp_only run_tcp_optimize
}

gen_uuid() {
  if [ -r /proc/sys/kernel/random/uuid ]; then
    cat /proc/sys/kernel/random/uuid
  elif command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr 'A-Z' 'a-z'
  else
    cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 32 | head -n 1 | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/'
  fi
}

shell_quote() { printf '%q' "$1"; }

write_argox_vmess_config() {
  require_root
  mkdir -p "$WORK_DIR"

  local uuid="${UUID:-}"
  local ws_path="${WS_PATH:-$DEFAULT_WS_PATH}"
  local start_port="${START_PORT:-$DEFAULT_START_PORT}"
  local nginx_port="${NGINX_PORT:-$DEFAULT_NGINX_PORT}"
  local node_name="${NODE_NAME:-$DEFAULT_NODE_NAME}"
  local argo_domain="${ARGO_DOMAIN:-}"
  local argo_auth="${ARGO_AUTH:-}"
  local server="${SERVER:-}"
  local server_port="${SERVER_PORT:-443}"

  [ -n "$uuid" ] || uuid="$(gen_uuid)"

  {
    echo '# Generated by TaoBox Speed'
    echo '# Native VMess + WebSocket config. No ArgoX install chain.'
    echo 'INSTALL_PROTOCOLS=(f)'
    printf 'START_PORT=%s\n' "$start_port"
    printf 'VMESS_WS_PORT=%s\n' "$start_port"
    printf 'NGINX_PORT=%s\n' "$nginx_port"
    printf 'UUID=%s\n' "$(shell_quote "$uuid")"
    printf 'WS_PATH=%s\n' "$(shell_quote "$ws_path")"
    printf 'NODE_NAME=%s\n' "$(shell_quote "$node_name")"
    [ -n "$argo_domain" ] && printf 'ARGO_DOMAIN=%s\n' "$(shell_quote "$argo_domain")"
    [ -n "$argo_auth" ] && printf 'ARGO_AUTH=%s\n' "$(shell_quote "$argo_auth")"
    if [ -n "$server" ]; then
      printf 'SERVER=%s\n' "$(shell_quote "$server")"
      printf 'SERVER_PORT=%s\n' "$(shell_quote "$server_port")"
    fi
  } > "$CONFIG_FILE"

  chmod 600 "$CONFIG_FILE"
  success "已生成 VMess+WS 配置：$CONFIG_FILE"
  info "协议：VMess + WebSocket | Path：/${ws_path}-vm | Xray：${start_port} | Nginx：${nginx_port}"
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64|64" ;;
    aarch64|arm64) echo "arm64|arm64-v8a" ;;
    *) err "暂只支持 x86_64 / arm64：$(uname -m)"; return 1 ;;
  esac
}

install_base_deps() {
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y curl wget unzip nginx openssl ca-certificates iproute2 >/dev/null 2>&1
  elif command -v yum >/dev/null 2>&1; then
    yum install -y curl wget unzip nginx openssl ca-certificates iproute >/dev/null 2>&1
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y curl wget unzip nginx openssl ca-certificates iproute >/dev/null 2>&1
  else
    err "暂不支持当前系统包管理器"
    return 1
  fi
}

download_speed_binaries() {
  local archs cf_arch xray_arch tmp
  archs="$(detect_arch)"; cf_arch="${archs%%|*}"; xray_arch="${archs##*|}"
  mkdir -p /etc/argox /etc/argox/subscribe
  if [ ! -x /etc/argox/cloudflared ]; then
    curl -LfsS "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${cf_arch}" -o /etc/argox/cloudflared
    chmod +x /etc/argox/cloudflared
  fi
  if [ ! -x /etc/argox/xray ]; then
    tmp="$(mktemp -d)"
    curl -LfsS "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${xray_arch}.zip" -o "$tmp/xray.zip"
    unzip -qo "$tmp/xray.zip" -d "$tmp"
    mv "$tmp/xray" /etc/argox/xray
    [ -f "$tmp/geoip.dat" ] && mv "$tmp/geoip.dat" /etc/argox/geoip.dat || true
    [ -f "$tmp/geosite.dat" ] && mv "$tmp/geosite.dat" /etc/argox/geosite.dat || true
    chmod +x /etc/argox/xray
    rm -rf "$tmp"
  fi
}

load_speed_config() {
  [ -s "$CONFIG_FILE" ] && . "$CONFIG_FILE"
  UUID="${UUID:-$(gen_uuid)}"
  WS_PATH="${WS_PATH:-$DEFAULT_WS_PATH}"
  VMESS_WS_PORT="${VMESS_WS_PORT:-${START_PORT:-$DEFAULT_START_PORT}}"
  NGINX_PORT="${NGINX_PORT:-$DEFAULT_NGINX_PORT}"
  NODE_NAME="${NODE_NAME:-Speed-Slayer}"
}

write_native_xray_config() {
  cat > /etc/argox/inbound.json <<EOF
{"log":{"loglevel":"warning","access":"/etc/argox/xray-access.log","error":"/etc/argox/xray-error.log"},"inbounds":[{"tag":"${NODE_NAME} vmess-ws","listen":"127.0.0.1","port":${VMESS_WS_PORT},"protocol":"vmess","settings":{"clients":[{"id":"${UUID}","alterId":0}]},"streamSettings":{"network":"ws","wsSettings":{"path":"/${WS_PATH}-vm"}},"sniffing":{"enabled":true,"destOverride":["http","tls"]}}],"outbounds":[{"protocol":"freedom","tag":"direct"}]}
EOF
}

json_escape() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip("\n"))[1:-1])'; }

make_vmess_url() {
  local host="$1" server="${SERVER:-www.visa.com}" port="${SERVER_PORT:-443}" payload
  payload=$(cat <<EOF
{"v":"2","ps":"$(printf '%s' "${NODE_NAME} vmess-ws" | json_escape)","add":"$(printf '%s' "$server" | json_escape)","port":"${port}","id":"${UUID}","aid":"0","scy":"none","net":"ws","type":"none","host":"$(printf '%s' "$host" | json_escape)","path":"/${WS_PATH}-vm","tls":"tls","sni":"$(printf '%s' "$host" | json_escape)","fp":"chrome"}
EOF
)
  printf 'vmess://%s\n' "$(printf '%s' "$payload" | base64 -w0)"
}

write_native_subscriptions() {
  local host="$1" vmess_url
  mkdir -p /etc/argox/subscribe
  vmess_url="$(make_vmess_url "$host")"
  printf '%s\n' "$vmess_url" > /etc/argox/vmess.txt
  printf '%s\n' "$vmess_url" | base64 -w0 > /etc/argox/subscribe/base64
  cat > /etc/argox/subscribe/clash <<EOF
proxies:
  - name: "${NODE_NAME} vmess-ws"
    type: vmess
    server: "${SERVER:-www.visa.com}"
    port: ${SERVER_PORT:-443}
    uuid: "${UUID}"
    alterId: 0
    cipher: none
    tls: true
    servername: "${host}"
    network: ws
    ws-opts:
      path: "/${WS_PATH}-vm"
      headers: { Host: "${host}" }
EOF
  cp /etc/argox/subscribe/base64 /etc/argox/subscribe/shadowrocket
  cat > /etc/argox/list <<EOF
Protocol : VMess
Network  : WebSocket
UUID     : ${UUID}
Host/SNI : ${host}
Path     : /${WS_PATH}-vm
CDN      : ${SERVER:-www.visa.com}:${SERVER_PORT:-443}

VMess URL:
${vmess_url}

Subscriptions:
https://${host}/${UUID}/base64
https://${host}/${UUID}/clash
https://${host}/${UUID}/shadowrocket
https://${host}/${UUID}/auto
EOF
}

write_native_nginx_config() {
  cat > /etc/argox/nginx.conf <<EOF
worker_processes auto;
events { worker_connections 1024; }
http { server { listen 127.0.0.1:${NGINX_PORT}; server_name _;
location /${WS_PATH}-vm { proxy_pass http://127.0.0.1:${VMESS_WS_PORT}; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$host; }
location /${UUID}/base64 { alias /etc/argox/subscribe/base64; default_type text/plain; }
location /${UUID}/clash { alias /etc/argox/subscribe/clash; default_type text/plain; }
location /${UUID}/shadowrocket { alias /etc/argox/subscribe/shadowrocket; default_type text/plain; }
location /${UUID}/auto { alias /etc/argox/subscribe/base64; default_type text/plain; }
location / { return 200 'TaoBox Speed OK'; }
} }
EOF
}

write_native_services() {
  cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=TaoBox Speed Xray VMess WS
After=network.target
[Service]
User=root
ExecStart=/etc/argox/xray run -c /etc/argox/inbound.json
Restart=on-failure
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
  cat > /etc/systemd/system/argo.service <<EOF
[Unit]
Description=TaoBox Speed Cloudflare Tunnel
After=network.target xray.service
[Service]
Type=simple
ExecStart=/etc/argox/cloudflared tunnel --edge-ip-version auto --no-autoupdate --url http://127.0.0.1:${NGINX_PORT} --metrics 127.0.0.1:0
Restart=on-failure
RestartSec=5
StandardOutput=append:/etc/argox/argo.log
StandardError=append:/etc/argox/argo.log
[Install]
WantedBy=multi-user.target
EOF
}

fetch_quick_tunnel_domain() {
  local domain i metrics
  for i in $(seq 1 45); do
    domain="$(grep -Eo 'https://[-a-zA-Z0-9.]+\.trycloudflare\.com' /etc/argox/argo.log 2>/dev/null | tail -n1 | sed 's#https://##' || true)"
    [ -n "$domain" ] && { echo "$domain"; return 0; }
    metrics="$(ss -lntp 2>/dev/null | awk '/cloudflared/ {print $4}' | awk -F: '{print $NF}' | tail -n1)"
    [ -n "$metrics" ] && domain="$(curl -fsS "http://127.0.0.1:${metrics}/quicktunnel" 2>/dev/null | awk -F'"' '{print $4}' || true)"
    [[ "${domain:-}" =~ trycloudflare\.com$ ]] && { echo "$domain"; return 0; }
    sleep 1
  done
  return 1
}

progress_step() {
  local pct="$1" msg="$2"
  printf "%b[%3s%%]%b %s\n" "$C_MAGENTA" "$pct" "$C_RESET" "$msg"
}

native_argo_install_staged() {
  section "TaoBox Speed · Argo VMess+WS"
  load_speed_config
  progress_step 5 "安装前检查端口与残留"
  preflight_argo_ports
  progress_step 10 "安装基础依赖"
  install_base_deps >>"$LOG_FILE" 2>&1
  progress_step 25 "下载 / 校验 cloudflared 与 Xray-core"
  download_speed_binaries >>"$LOG_FILE" 2>&1
  progress_step 45 "写入纯 VMess+WS Xray 配置"
  write_native_xray_config >>"$LOG_FILE" 2>&1
  progress_step 55 "写入 Nginx WebSocket 反代与订阅接口"
  write_native_nginx_config >>"$LOG_FILE" 2>&1
  progress_step 65 "写入 systemd 服务"
  write_native_services >>"$LOG_FILE" 2>&1
  progress_step 75 "启动 Xray / Nginx / Cloudflared"
  systemctl daemon-reload >>"$LOG_FILE" 2>&1
  systemctl enable --now xray >>"$LOG_FILE" 2>&1
  nginx -t -c /etc/argox/nginx.conf >>"$LOG_FILE" 2>&1
  pkill -f 'nginx.*argox/nginx.conf' >>"$LOG_FILE" 2>&1 || true
  nginx -c /etc/argox/nginx.conf >>"$LOG_FILE" 2>&1
  : > /etc/argox/argo.log
  systemctl enable --now argo >>"$LOG_FILE" 2>&1
  progress_step 88 "获取 Argo 隧道域名"
  local host
  host="${ARGO_DOMAIN:-}"
  [ -n "$host" ] || host="$(fetch_quick_tunnel_domain)"
  [ -n "$host" ] || { err "未获取到 Argo 临时域名，查看 /etc/argox/argo.log"; return 1; }
  progress_step 96 "生成 VMess URL 与订阅文件"
  write_native_subscriptions "$host" >>"$LOG_FILE" 2>&1
  progress_step 100 "完成"
}

verify_vmess_only() {
  local inbound="/etc/argox/inbound.json"
  [ -s "$inbound" ] || { err "未找到 inbound 配置：$inbound"; return 1; }
  python3 - "$inbound" <<'PYVERIFY'
import json, sys
path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    data = json.load(f)
inbounds = data.get('inbounds') or []
if len(inbounds) != 1:
    print(f"inbound 数量异常：{len(inbounds)}", file=sys.stderr)
    sys.exit(1)
ib = inbounds[0]
if ib.get('protocol') != 'vmess':
    print(f"协议异常：{ib.get('protocol')}", file=sys.stderr)
    sys.exit(1)
stream = ib.get('streamSettings') or {}
if stream.get('network') != 'ws':
    print(f"传输异常：{stream.get('network')}", file=sys.stderr)
    sys.exit(1)
print('VMess+WS 校验通过')
PYVERIFY
}

extract_vmess_only() { [ -s /etc/argox/list ] && cat /etc/argox/list || warn "尚未生成 /etc/argox/list"; }

install_argo_vmess_ws() {
  render_header_once
  require_root
  clean_argo_state >/dev/null 2>&1 || true
  write_argox_vmess_config
  info "正在部署 Argo VMess+WS 节点。"
  info "安装前会自动清理旧服务、旧进程和旧配置，支持重复安装。"
  if ! native_argo_install_staged; then
    fail_report "Argo VMess+WS 部署"
    return 1
  fi
  if ! verify_vmess_only; then
    fail_report "VMess+WS 配置校验"
    return 1
  fi
  success "Argo VMess+WS 安装流程结束"
  summarize_result || true
  health_check || true
}

show_argo_vmess_ws_info() {
  require_root
  extract_vmess_only
}

uninstall_argo_vmess_ws() {
  render_header_once
  require_root
  warn "卸载 TaoBox Speed Argo VMess+WS 服务"
  systemctl stop argo xray >/dev/null 2>&1 || true
  pkill -f 'nginx.*argox/nginx.conf' >/dev/null 2>&1 || true
  systemctl disable argo xray >/dev/null 2>&1 || true
  rm -f /etc/systemd/system/argo.service /etc/systemd/system/xray.service
  systemctl daemon-reload >/dev/null 2>&1 || true
  rm -rf /etc/argox
  success "TaoBox Speed Argo VMess+WS 已卸载"
}

clean_argo_state() {
  require_root
  warn "清理现有 Argo 配置并备份数据。"
  local ts
  ts="$(date +%Y%m%d%H%M%S)"
  systemctl stop argo xray >/dev/null 2>&1 || true
  systemctl disable argo xray >/dev/null 2>&1 || true
  pkill -f '/etc/argox/cloudflared' >/dev/null 2>&1 || true
  pkill -f '/etc/argox/xray' >/dev/null 2>&1 || true
  pkill -f 'nginx.*argox/nginx.conf' >/dev/null 2>&1 || true
  rm -f /etc/systemd/system/argo.service /etc/systemd/system/xray.service
  systemctl daemon-reload >/dev/null 2>&1 || true
  if [ -d /etc/argox ]; then
    mv /etc/argox "/etc/argox.bak.${ts}" 2>/dev/null || rm -rf /etc/argox
  fi
  mkdir -p /etc/argox /etc/argox/subscribe
  success "Argo 配置已备份清理。"
}

force_all() {
  render_header_once
  ASSUME_Y=1
  install_shortcut || true
  if ! is_xanmod_kernel; then
    save_pending_state
    run_tcp_optimize
    if [ "${SPEED_STOCK_FALLBACK_ACTIVE:-0}" = "1" ]; then
      install_argo_vmess_ws
      clear_state || true
    fi
    return 0
  fi
  run_tcp_optimize
  install_argo_vmess_ws
  clear_state || true
}

run_all() {
  render_header_once
  warn "--all 是安全主页模式：不会自动执行 BBR；请选择菜单项后再确认。"
  menu_body
}

continue_after_reboot() {
  render_header_once
  require_root
  install_shortcut || true
  local next_action="continue"
  if [ -s "$STATE_FILE" ]; then
    # shellcheck disable=SC1090
    . "$STATE_FILE"
    next_action="${NEXT_ACTION:-continue}"
  fi
  if ! is_xanmod_kernel; then
    if [ "${SPEED_ALLOW_STOCK_FALLBACK:-1}" = "1" ]; then
      warn "检测到续跑状态，但当前仍未进入 XanMod 内核。"
      warn "将清理旧续跑状态，并按 stock-kernel fallback 继续，避免卡在重启循环。"
      clear_state_silent
      ASSUME_Y=1
      SPEED_FORCE_STOCK_FALLBACK=1
      if [ "$next_action" = "tcp_only" ]; then
        run_tcp_optimize
        clear_state || true
        return 0
      fi
      run_tcp_optimize
      install_argo_vmess_ws
      clear_state || true
      return 0
    else
      err "当前仍未进入 XanMod 内核，暂停续跑，避免循环。"
      echo "当前内核: $(uname -r)"
      echo "建议检查 VPS 是否支持自定义内核、GRUB 启动项或重新执行 speed --optimize。"
      exit 1
    fi
  fi
  if [ "$next_action" = "tcp_only" ]; then
    info "检测到 XanMod 内核，继续执行纯 TCP 网络调优。"
    run_tcp_optimize
    clear_state || true
    return 0
  fi
  info "检测到 XanMod 内核，继续执行 TCP 网络调优 + Argo VMess+WS"
  run_tcp_optimize
  install_argo_vmess_ws
  clear_state || true
}

check_environment() {
  require_root
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo " TaoBox Speed · 环境检测"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "系统内核: $(uname -r)"
  echo "系统架构: $(uname -m)"
  echo "Root 权限: OK"
  for cmd in curl wget bash systemctl ss openssl; do
    if command -v "$cmd" >/dev/null 2>&1; then
      printf "%-12s: OK\n" "$cmd"
    else
      printf "%-12s: MISSING\n" "$cmd"
    fi
  done
  echo "TCP 拥塞控制: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
  echo "默认队列算法: $(sysctl -n net.core.default_qdisc 2>/dev/null || echo unknown)"
  if [ -s /etc/argox/list ]; then
    echo "TaoBox Speed 节点信息: FOUND /etc/argox/list"
  else
    echo "TaoBox Speed 节点信息: NOT FOUND"
  fi
}

field_from_list() {
  local key="$1"
  awk -F: -v k="$key" '$1 ~ k {sub(/^[[:space:]]+/,"",$2); print $2; exit}' /etc/argox/list 2>/dev/null
}

subscription_url() {
  local name="$1"
  grep -E "https://.*/${name}$" /etc/argox/list 2>/dev/null | head -1
}

kv() { printf "%b%-13s%b %b%s%b\n" "$C_DIM" "$1" "$C_RESET" "$3" "$2" "$C_RESET"; }

summarize_result() {
  echo ""
  line
  printf "%b%s%b\n" "$C_BOLD$C_GREEN" " TaoBox Speed · Installation Complete" "$C_RESET"
  line
  kv "Kernel" "$(uname -r)" "$C_WHITE"
  kv "BBR" "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)" "$C_GREEN"
  kv "Queue" "$(sysctl -n net.core.default_qdisc 2>/dev/null || echo unknown)" "$C_GREEN"

  if [ -s /etc/argox/list ]; then
    local uuid host path cdn vmess base64 clash shadowrocket auto
    uuid="$(field_from_list 'UUID')"
    host="$(field_from_list 'Host/SNI')"
    path="$(field_from_list 'Path')"
    cdn="$(field_from_list 'CDN')"
    vmess="$(grep -m1 '^vmess://' /etc/argox/list 2>/dev/null || true)"
    base64="$(subscription_url base64)"
    clash="$(subscription_url clash)"
    shadowrocket="$(subscription_url shadowrocket)"
    auto="$(subscription_url auto)"

    echo ""
    printf "%b%s%b\n" "$C_BOLD$C_CYAN" "Node" "$C_RESET"
    kv "Protocol" "VMess" "$C_GREEN"
    kv "Network" "WebSocket" "$C_GREEN"
    kv "TLS" "Enabled" "$C_GREEN"
    kv "Host/SNI" "$host" "$C_YELLOW"
    kv "Path" "$path" "$C_YELLOW"
    kv "UUID" "$uuid" "$C_MAGENTA"
    kv "CDN" "$cdn" "$C_CYAN"

    echo ""
    printf "%b%s%b\n" "$C_BOLD$C_MAGENTA" "VMess URL" "$C_RESET"
    printf "%b%s%b\n" "$C_GREEN" "$vmess" "$C_RESET"

    echo ""
    printf "%b%s%b\n" "$C_BOLD$C_MAGENTA" "Subscriptions" "$C_RESET"
    [ -n "$base64" ] && kv "Base64" "$base64" "$C_WHITE"
    [ -n "$clash" ] && kv "Clash" "$clash" "$C_WHITE"
    [ -n "$shadowrocket" ] && kv "Shadowrocket" "$shadowrocket" "$C_WHITE"
    [ -n "$auto" ] && kv "Auto" "$auto" "$C_WHITE"

    echo ""
    printf "%b%s%b\n" "$C_BOLD$C_CYAN" "Next Commands" "$C_RESET"
    printf "  %bspeed%b              进入 TaoBox Speed 控制台 / 重启后自动续跑\n" "$C_BOLD$C_GREEN" "$C_RESET"
    printf "  %bspeed --doctor%b     全链路诊断\n" "$C_BOLD$C_GREEN" "$C_RESET"
    printf "  %bspeed --logs%b       查看日志\n" "$C_BOLD$C_GREEN" "$C_RESET"
    printf "  %bspeed --repair%b     清理并重装节点\n" "$C_BOLD$C_GREEN" "$C_RESET"
    echo ""
    printf "%b完整信息：%b/etc/argox/list\n" "$C_DIM" "$C_RESET"
  else
    echo ""
    warn "未检测到节点信息。"
    printf "如果刚完成内核安装，请重启后执行：%bspeed%b\n" "$C_BOLD$C_GREEN" "$C_RESET"
    printf "如果需要单独部署节点，请执行：%bspeed --install-argo-vmess%b\n" "$C_BOLD$C_GREEN" "$C_RESET"
  fi
}

service_state() {
  local svc="$1"
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
      echo "running"
    elif systemctl list-unit-files "$svc" >/dev/null 2>&1 || systemctl status "$svc" >/dev/null 2>&1; then
      echo "installed-but-not-running"
    else
      echo "not-found"
    fi
  else
    if pgrep -f "$svc" >/dev/null 2>&1; then
      echo "running"
    else
      echo "unknown"
    fi
  fi
}

port_state() {
  local port="$1"
  if command -v ss >/dev/null 2>&1 && ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "(:|\\])${port}$"; then
    echo "listening"
  else
    echo "not-listening"
  fi
}

port_owner() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -lntp 2>/dev/null | awk -v p="$port" '$4 ~ ("(:|\\])" p "$") {print $0; exit}'
  else
    echo "unknown"
  fi
}

health_check() {
  require_root
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo " TaoBox Speed · 健康检查"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  local fail=0
  local argo_state xray_state nginx_state nginx_port argo_domain
  argo_state="$(service_state argo)"
  xray_state="$(service_state xray)"
  nginx_state="$(service_state nginx)"
  nginx_port="$(awk -F= '/^NGINX_PORT=/{print $2}' "$CONFIG_FILE" 2>/dev/null | tr -d "'\"")"
  nginx_port="${nginx_port:-8001}"

  printf "%-18s %s\n" "argo.service:" "$argo_state"
  printf "%-18s %s\n" "xray.service:" "$xray_state"
  printf "%-18s %s\n" "nginx.service:" "$nginx_state"
  printf "%-18s %s (%s)\n" "本地入口端口:" "$nginx_port" "$(port_state "$nginx_port")"
  [ "$(port_state "$nginx_port")" != "listening" ] || echo "端口占用: $(port_owner "$nginx_port")"

  [ "$argo_state" = "running" ] || fail=1
  [ "$xray_state" = "running" ] || fail=1
  [ "$(port_state "$nginx_port")" = "listening" ] || fail=1

  if [ -s /etc/argox/list ]; then
    echo "节点列表: FOUND /etc/argox/list"
    argo_domain="$(grep -Eo 'https?://[^/ ]+' /etc/argox/list | sed 's#https\?://##' | grep -E 'trycloudflare\.com|cloudflare|\.' | head -n1 || true)"
    [ -n "$argo_domain" ] && echo "Argo 域名: $argo_domain" || echo "Argo 域名: 未能从节点列表提取"
  else
    echo "节点列表: MISSING /etc/argox/list"
    fail=1
  fi

  if [ -s /etc/argox/subscribe/base64 ]; then
    echo "Base64订阅: FOUND"
  else
    echo "Base64订阅: MISSING"
    fail=1
  fi

  echo ""
  if [ "$fail" -eq 0 ]; then
    success "健康检查通过：Argo / Xray / 本地入口 / 订阅文件均可用"
    return 0
  fi

  warn "健康检查未完全通过，建议按以下方向排查："
  [ "$argo_state" = "running" ] || echo "- Argo 未运行：执行 systemctl status argo 或重新运行 --install-argo-vmess"
  [ "$xray_state" = "running" ] || echo "- Xray 未运行：执行 systemctl status xray，检查 /etc/argox/xray.log"
  [ "$(port_state "$nginx_port")" = "listening" ] || echo "- 本地入口端口未监听：检查 nginx 配置或端口占用 ss -lntp | grep $nginx_port"
  [ -s /etc/argox/list ] || echo "- 节点列表未生成：查看 $LOG_FILE，确认 Argo 是否拿到隧道域名"
  [ -s /etc/argox/subscribe/base64 ] || echo "- 订阅文件缺失：重新执行 --show-url 或 --install-argo-vmess"
  return 1
}

remote_version() {
  local tmp
  tmp="$(mktemp /tmp/speed-slayer-version.XXXXXX)"
  if download_repo_file "scripts/taobox-speed.sh" "$tmp" 2>/dev/null; then
    grep -m1 '^SPEED_SLAYER_VERSION=' "$tmp" | cut -d= -f2- | tr -d '"'
  fi
  rm -f "$tmp"
}

version_rank() {
  printf '%s\n' "$1" | sed -nE 's/^([0-9]{4})\.([0-9]{2})\.([0-9]{2})-r([0-9]+)$/\1\2\3\4/p'
}

is_newer_version() {
  local remote="$1" current="$2" rr cr
  rr="$(version_rank "$remote")"; cr="$(version_rank "$current")"
  [ -n "$rr" ] && [ -n "$cr" ] && [ "$rr" -gt "$cr" ]
}

check_self_update_hint() {
  [ "${SKIP_UPDATE_CHECK:-0}" = "1" ] && return 0
  [ -t 1 ] || return 0
  local rv
  rv="$(remote_version || true)"
  if [ -n "$rv" ] && is_newer_version "$rv" "$SPEED_SLAYER_VERSION"; then
    warn "检测到新版本：${rv}（当前：${SPEED_SLAYER_VERSION}）。建议先执行：speed --update-self"
  fi
}

update_self() {
  require_root
  mkdir -p "$WORK_DIR"
  download_repo_file "scripts/taobox-speed.sh" "$INSTALLED_BIN.tmp"
  bash -n "$INSTALLED_BIN.tmp"
  mv "$INSTALLED_BIN.tmp" "$INSTALLED_BIN"
  chmod +x "$INSTALLED_BIN"
  success "speed 已更新到最新版本：$INSTALLED_BIN"
  "$INSTALLED_BIN" --version || true
}

show_roadmap() {
  section "TaoBox Speed · Roadmap"
  cat <<'EOF'
当前进度：约 97%

已完成：
- 一键完整流程与重启续跑
- BBR v3 / TCP 加速配置
- Argo VMess+WS 部署与订阅生成
- 重复安装预清理与 JSON 校验
- 日志菜单与修复命令
- 版本号与自更新
- 产品化文案清理

正在施工：
- 稳定性与失败提示收口
- 重复安装与残留处理继续加固
- 菜单结构产品化

下一步：
1. 收拢主页为二级菜单
2. 增强 doctor：端口、服务、配置、订阅全链路诊断
3. 输出最终安装摘要与复制友好节点信息
4. README / CHANGELOG / 发布版本收口

预计剩余：
- 可用 Beta：已接近，可进入实机回归
- 接近 V1.0：约 1 轮施工
EOF
}

show_logs() {
  require_root
  local target="${1:-menu}"
  case "$target" in
    kernel) tail -n 160 "$WORK_DIR/kernel-install.log" 2>/dev/null || warn "暂无内核安装日志" ;;
    tcp) tail -n 160 "$WORK_DIR/tcp-optimize.log" 2>/dev/null || warn "暂无 TCP 日志" ;;
    install) tail -n 160 "$LOG_FILE" 2>/dev/null || warn "暂无安装日志" ;;
    argo) tail -n 160 /etc/argox/argo.log 2>/dev/null || warn "暂无 Argo 日志" ;;
    xray) tail -n 160 /etc/argox/xray-error.log 2>/dev/null || warn "暂无 Xray 错误日志" ;;
    menu)
      section "TaoBox Speed · 日志"
      echo "1. 安装总日志      $LOG_FILE"
      echo "2. 内核安装日志    $WORK_DIR/kernel-install.log"
      echo "3. TCP 调优日志    $WORK_DIR/tcp-optimize.log"
      echo "4. Argo 日志       /etc/argox/argo.log"
      echo "5. Xray 错误日志   /etc/argox/xray-error.log"
      echo "0. 返回"
      read -r -p "请选择: " log_choice
      case "$log_choice" in
        1) show_logs install ;;
        2) show_logs kernel ;;
        3) show_logs tcp ;;
        4) show_logs argo ;;
        5) show_logs xray ;;
        *) return 0 ;;
      esac
      ;;
    *) err "未知日志类型：$target"; return 1 ;;
  esac
}

repair_install() {
  require_root
  section "TaoBox Speed · 修复"
  warn "将清理 Argo 服务/进程/配置残留，然后重新部署 VMess+WS。"
  if ! confirm_action "是否继续修复？默认回车 = Y"; then
    warn "已取消修复。"
    return 0
  fi
  clean_argo_state
  install_argo_vmess_ws
}

doctor_check() {
  local label="$1" cmd="$2" fix="${3:-}"
  if eval "$cmd" >/dev/null 2>&1; then
    printf "%b[OK]%b   %s\n" "$C_GREEN" "$C_RESET" "$label"
  else
    printf "%b[FAIL]%b %s\n" "$C_RED" "$C_RESET" "$label"
    [ -n "$fix" ] && printf "       修复建议：%s\n" "$fix"
    return 1
  fi
}

doctor_warn() {
  local label="$1" cmd="$2" fix="${3:-}"
  if eval "$cmd" >/dev/null 2>&1; then
    printf "%b[OK]%b   %s\n" "$C_GREEN" "$C_RESET" "$label"
  else
    printf "%b[WARN]%b %s\n" "$C_YELLOW" "$C_RESET" "$label"
    [ -n "$fix" ] && printf "       建议：%s\n" "$fix"
  fi
}

doctor() {
  require_root
  section "TaoBox Speed · Doctor"
  local failed=0
  doctor_check "Root 权限" '[ "$(id -u)" -eq 0 ]' "使用 root 执行 speed" || failed=1
  doctor_check "systemd 可用" 'command -v systemctl && [ -d /run/systemd/system ]' "当前系统可能不支持 systemd，建议使用 Debian/Ubuntu VPS" || failed=1
  doctor_check "curl 可用" 'command -v curl' "apt install -y curl" || failed=1
  doctor_check "ss 可用" 'command -v ss' "apt install -y iproute2" || failed=1
  doctor_check "python3 可用" 'command -v python3' "apt install -y python3" || failed=1

  echo ""
  echo "服务状态："
  doctor_warn "xray.service 运行" 'systemctl is-active --quiet xray' "执行 speed --repair"
  doctor_warn "argo.service 运行" 'systemctl is-active --quiet argo' "执行 speed --repair"
  doctor_warn "入口端口监听" '[ "$(port_state "${NGINX_PORT:-8001}")" = "listening" ]' "检查 nginx 或执行 speed --repair"
  doctor_warn "内部 WS 端口监听" '[ "$(port_state "${VMESS_WS_PORT:-30000}")" = "listening" ]' "检查 xray 或执行 speed --repair"

  echo ""
  echo "配置与订阅："
  doctor_check "inbound.json 存在" '[ -s /etc/argox/inbound.json ]' "执行 speed --install-argo-vmess" || failed=1
  if [ -s /etc/argox/inbound.json ]; then
    doctor_check "VMess+WS 配置有效" 'verify_vmess_only' "执行 speed --repair" || failed=1
  fi
  doctor_warn "节点信息已生成" '[ -s /etc/argox/list ]' "执行 speed --install-argo-vmess"
  doctor_warn "Base64 订阅存在" '[ -s /etc/argox/subscribe/base64 ]' "执行 speed --install-argo-vmess"

  echo ""
  echo "网络加速："
  doctor_warn "BBR 已启用" '[ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" = "bbr" ]' "执行 speed --optimize"
  doctor_warn "队列算法 fq" '[ "$(sysctl -n net.core.default_qdisc 2>/dev/null)" = "fq" ]' "执行 speed --optimize"

  echo ""
  if [ "$failed" -eq 0 ]; then
    success "Doctor 完成：核心链路未发现阻断项。"
  else
    err "Doctor 完成：发现阻断项，建议优先执行 speed --repair 或查看 speed --logs。"
    return 1
  fi
}

usage() {
  cat <<'EOF'
TaoBox Speed

Usage:
  bash taobox-speed.sh [command]

Commands:
  --tcp-status           查看 TCP / BBR / 内核状态
  --optimize             执行全自动 TCP 优化：BBR v3 + 网络调优
  --optimize-only        仅执行 XanMod / BBRv3 / TCP 调优，不部署节点
  --install-argo-vmess   安装/重装 Argo VMess + WS，并生成节点/订阅 URL
  --all                  显示交互主页（安全默认，不直接修改系统）
  --force-all            无人值守完整流程；如需重启，重启后执行 speed 即可继续
  --continue             重启后继续：TCP 网络调优 + Argo VMess + WS
  --show-url             查看已生成的节点/订阅信息
  --uninstall-argo       卸载 Argo VMess + WS 相关服务
  --clean-argo           清理现有 Argo 配置，备份 /etc/argox 后重装 VMess+WS
  --write-config         仅生成 Argo VMess + WS 配置文件，不安装
  --install-shortcut     安装 speed 快捷命令到 /usr/local/bin/speed
  --clear-state          清理续跑状态
  --check                检测当前环境和已安装状态
  --summary              输出结果摘要
  --health               安装后健康检查
  --doctor               一键诊断：环境检测 + 结果摘要 + 健康检查
  --logs [type]          查看日志：install/kernel/tcp/argo/xray
  --repair               清理残留并重装 Argo VMess+WS
  --speedtest            执行 Ookla Speedtest 测速
  --netcheck             检查 DNS / GitHub / Cloudflare / 出站连通性
  --update-self          更新 /usr/local/bin/speed 到 GitHub 最新版本
  --version              显示当前 TaoBox Speed 版本
  -h, --help             显示帮助

Optional environment variables:
  UUID                   指定 VMess UUID，默认自动生成
  WS_PATH                指定 WS Path 前缀，默认 argox，实际 path 为 /<WS_PATH>-vm
  START_PORT             指定 Xray VMess 内部监听端口，默认 30000
  NGINX_PORT             指定 Nginx/Argo 本地入口端口，默认 8001
  NODE_NAME              指定节点名，默认 VPS-Argo-VMess
  ARGO_DOMAIN            固定 Argo 域名；不填则使用 trycloudflare 临时域名
  ARGO_AUTH              Argo Token / Json / Cloudflare API 信息；固定隧道时使用
  SERVER                 CDN 优选地址，默认 www.visa.com
  SERVER_PORT            优选 CDN 端口，默认 443

Examples:
  bash taobox-speed.sh --all
  WS_PATH=zaki NODE_NAME=Zaki-VPS bash taobox-speed.sh --install-argo-vmess
  ARGO_DOMAIN=tunnel.example.com ARGO_AUTH='eyJhIj...' bash taobox-speed.sh --install-argo-vmess
EOF
}

menu_section_node() {
  section "TaoBox Speed · 节点管理"
  cat <<'EOF'
1. 安装/重装 Argo VMess+WS
2. 查看节点/订阅信息
3. 修复 Argo 安装
4. 卸载 Argo VMess+WS
5. 清理 Argo 配置
0. 返回主页
EOF
  read -r -p "请选择: " choice
  case "$choice" in
    1) install_argo_vmess_ws ;;
    2) show_argo_vmess_ws_info ;;
    3) repair_install ;;
    4) uninstall_argo_vmess_ws ;;
    5) clean_argo_state ;;
    0) menu_body ;;
    *) err "无效选择"; return 1 ;;
  esac
}

menu_section_tcp() {
  section "TaoBox Speed · TCP 加速"
  cat <<'EOF'
1. 查看 TCP / BBR / 内核状态
2. 执行 TCP 优化
3. 重启后继续安装
0. 返回主页
EOF
  read -r -p "请选择: " choice
  case "$choice" in
    1) tcp_status_panel ;;
    2) run_tcp_optimize ;;
    3) continue_after_reboot ;;
    0) menu_body ;;
    *) err "无效选择"; return 1 ;;
  esac
}

menu_section_diag() {
  section "TaoBox Speed · 诊断与日志"
  cat <<'EOF'
1. 一键诊断 doctor
2. 环境检测
3. 结果摘要
4. 健康检查
5. 查看日志
6. Speedtest 测速
7. Netcheck 网络检测
0. 返回主页
EOF
  read -r -p "请选择: " choice
  case "$choice" in
    1) doctor ;;
    2) check_environment ;;
    3) summarize_result ;;
    4) health_check ;;
    5) show_logs ;;
    6) run_speedtest_cmd ;;
    7) run_netcheck ;;
    0) menu_body ;;
    *) err "无效选择"; return 1 ;;
  esac
}

menu_section_system() {
  section "TaoBox Speed · 更新"
  cat <<'EOF'
1. 安装 speed 快捷命令
2. 更新 speed 自身
0. 返回主页
EOF
  read -r -p "请选择: " choice
  case "$choice" in
    1) install_shortcut ;;
    2) update_self ;;
    0) menu_body ;;
    *) err "无效选择"; return 1 ;;
  esac
}

menu_body() {
  cat <<'EOF'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 『TaoBox Speed 控制台』
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  1. 一键执行完整流程        2. 节点管理
  3. TCP 加速                4. 诊断与日志
  5. 修复与清理              6. 更新
  0. 退出
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
  read -r -p "请输入选择: " choice
  case "$choice" in
    1) force_all ;;
    2) menu_section_node ;;
    3) menu_section_tcp ;;
    4) menu_section_diag ;;
    5) repair_install ;;
    6) menu_section_system ;;
    0) exit 0 ;;
    *) err "无效选择"; exit 1 ;;
  esac
}

menu() {
  render_header_once
  menu_body
}

default_action() {
  render_header_once
  check_self_update_hint
  require_root
  if [ -s "$STATE_FILE" ]; then
    info "检测到续跑状态，自动继续完整流程。"
    continue_after_reboot
  else
    menu
  fi
}

case "${1:-}" in
  --tcp-status) tcp_status_panel ;;
  --optimize) run_tcp_optimize ;;
  --optimize-only) run_tcp_optimize_only ;;
  --install-argo-vmess) install_argo_vmess_ws ;;
  --all) run_all ;;
  --force-all) force_all ;;
  --continue) continue_after_reboot ;;
  --show-url) show_argo_vmess_ws_info ;;
  --uninstall-argo) uninstall_argo_vmess_ws ;;
  --clean-argo) clean_argo_state ;;
  --write-config) write_argox_vmess_config ;;
  --install-shortcut) install_shortcut ;;
  --clear-state) clear_state ;;
  --check) check_environment ;;
  --summary) summarize_result ;;
  --health) health_check ;;
  --doctor) doctor ;;
  --logs) show_logs "${2:-menu}" ;;
  --repair) repair_install ;;
  --speedtest) run_speedtest_cmd ;;
  --netcheck) run_netcheck ;;
  --update-self) update_self ;;
  --version) echo "TaoBox Speed ${SPEED_SLAYER_VERSION}" ;;
  -h|--help) usage ;;
  "") default_action ;;
  *) err "未知参数：$1"; usage; exit 1 ;;
esac
