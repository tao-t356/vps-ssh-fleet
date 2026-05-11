# TaoBox

TaoBox 是一个面向 VPS 的一体化命令行工具箱，入口脚本会安装到服务器本地，并提供 SSH 登录管理、TCP/BBR 调优、节点部署、Docker + Nginx Proxy Manager、网络诊断、系统工具和自更新能力。

当前主线更偏向「登录 VPS 后直接用菜单完成常用运维与节点部署」，仓库中仍保留早期的 Ansible / SSH 配置生成文件，适合需要批量管理多台 VPS 的场景。

## 当前版本

- TaoBox VPS Toolbox：`v0.12.5`
- TaoBox Speed：`v1.0.0-taobox.4`
- 默认安装路径：`~/ssh-key-menu.sh`
- 默认快捷命令：`f`

## 快速安装 / 更新

> 当前 CTF/受控网络环境访问 GitHub 时需要携带 `jshook` 请求头。下面命令默认使用 `JSHOOK` 环境变量；未设置时使用脚本默认值 `123`。

推荐使用 GitHub API + 时间戳安装，避免 `raw.githubusercontent.com` 缓存导致拉到旧版本：

```bash
tmp=$(mktemp)
curl -fsSL \
  -H "Accept: application/vnd.github.raw" \
  -H "Cache-Control: no-cache" \
  -H "jshook: ${JSHOOK:-123}" \
  "https://api.github.com/repos/tao-t356/TaoBox/contents/bootstrap-vps.sh?ref=main&ts=$(date +%s)" \
  -o "$tmp"
bash "$tmp"
```

如果你明确知道当前网络不受 raw 缓存影响，也可以使用：

```bash
curl -fsSL -H "jshook: ${JSHOOK:-123}" \
  https://raw.githubusercontent.com/tao-t356/TaoBox/main/bootstrap-vps.sh | bash
```

安装完成后，直接输入：

```bash
f
```

即可再次打开 TaoBox。

## 主菜单

```text
1. SSH 登录管理
2. TaoBox Speed（一体）
3. VLESS + Hysteria2 节点搭建
4. Docker + NPM 安装 / 容器管理
5. 网络工具 / BBR
6. 系统工具 / DD
7. 更新工具箱
0. 退出
```

## 功能说明

### 1. SSH 登录管理

用于把 VPS 从密码登录逐步切换到公钥登录。

包含：

- 生成本机 SSH 密钥对
- 手动导入一行公钥
- 从 GitHub 用户名导入 `https://github.com/<user>.keys`
- 从 URL 导入公钥
- 编辑 `authorized_keys`
- 查看本机密钥和 `authorized_keys`
- 关闭 / 开启密码登录

建议流程：

1. 先导入公钥
2. 新开一个 SSH 会话确认公钥能登录
3. 再关闭密码登录

### 2. TaoBox Speed（一体）

用于 TCP 加速与节点部署的一体化流程。

包含：

- XanMod / BBRv3 安装尝试
- 当前系统内核 BBR + `fq` 降级调优
- TCP sysctl 参数调优
- DNS / IPv6 / 网络稳定性处理
- Argo VMess WebSocket 节点部署
- 重启后续跑
- 诊断、日志、修复、测速、健康检查

说明：

- 如果 `deb.xanmod.org` 被 Cloudflare challenge 或网络策略拦截，TaoBox Speed 不会直接中断。
- 默认会自动降级为「当前系统内核 + `tcp_bbr` + `fq` + TCP 调优」，并继续后续节点部署。
- 如需禁止降级，可设置：

```bash
SPEED_ALLOW_STOCK_FALLBACK=0 speed --force-all
```

常用命令：

```bash
speed
speed --force-all
speed --tcp-status
speed --doctor
speed --logs kernel
speed --update-self
```

### 3. VLESS + Hysteria2 节点搭建

该菜单会下载并执行独立项目：

- 仓库：`https://github.com/tao-t356/vless-xhttp-reality-self`
- 脚本：`scripts/install.sh`

支持：

- VLESS-XHTTP-REALITY
- Hysteria2
- 同时安装 / 重装 VLESS + Hysteria2
- 证书申请 / 续签
- 查看节点 URL / 二维码
- 服务状态、日志、重启
- 参数重置、备份恢复、卸载

TaoBox 下载该远程脚本时使用 GitHub API + 时间戳，并携带 `jshook`，避免缓存旧脚本。

### 4. Docker + NPM 安装 / 容器管理

第 4 项已整合原来的「Docker 容器管理」。进入后包含：

```text
1. 安装 / 重装 Docker + Nginx Proxy Manager
2. 查看 Docker 状态
3. 查看全部容器
4. 启动全部容器
5. 停止全部容器
6. 重启全部容器
7. 查看容器日志
8. Docker system prune
0. 返回
```

Nginx Proxy Manager 安装脚本来自：

- `https://github.com/tao-t356/Docker-Nginx-Proxy-Manager`

同样通过 GitHub API + 时间戳拉取，避免 raw 缓存。

### 5. 网络工具 / BBR

包含：

- 普通内核启用 BBR
- 查看 BBR 状态
- 安装 NextTrace
- Ping 测试
- Traceroute / Tracepath
- 查看本机路由

### 6. 系统工具 / DD

包含：

- 查看监听端口
- 查看高占用进程
- 查看常见服务状态
- 重启 SSH 服务
- 查看最近登录
- 重启服务器
- DD 重装系统入口

DD 重装入口当前提供：

- Debian 12
- Debian 13
- Ubuntu 22.04
- Ubuntu 24.04

> DD 重装属于危险操作，请确认服务商支持、备份数据并确保你知道 root 密码。

### 7. 更新工具箱

会重新下载 `bootstrap-vps.sh` 并覆盖本地 `~/ssh-key-menu.sh`。当前更新逻辑也使用 GitHub API + 时间戳，避免缓存旧版本。

## jshook 说明

本项目在当前 CTF/受控环境中访问真实域名时统一支持 `jshook` 请求头。

默认值：

```bash
JSHOOK=123
```

临时指定：

```bash
export JSHOOK=facker
f
```

或单次运行：

```bash
JSHOOK=facker bash bootstrap-vps.sh
```

涉及 GitHub、XanMod、DD 脚本、远程安装器等下载动作时，脚本会尽量自动携带该请求头。

## 文件结构

```text
bootstrap-vps.sh              # 自包含安装器，会写入 ~/ssh-key-menu.sh
ssh-key-menu.sh               # 已展开的菜单脚本版本
scripts/taobox-speed.sh       # TaoBox Speed 一体化脚本
scripts/tcp-one-click-optimize.sh
scripts/lib/tcp-core.sh       # TCP 调优兼容库
inventory/                    # 早期 Ansible 批量管理示例
playbooks/                    # 早期 Ansible playbook
scripts/render_ssh_config.py  # 根据 inventory 生成 SSH config
quick-start.ps1               # Windows 快速辅助脚本
```

## Windows + GitHub 公钥登录建议

在 Windows PowerShell 生成密钥：

```powershell
ssh-keygen -t ed25519 -C "your-name@windows"
```

复制公钥：

```powershell
Get-Content $HOME\.ssh\id_ed25519.pub | Set-Clipboard
```

上传到 GitHub 账号 SSH keys 页面：

```text
https://github.com/settings/keys
```

然后在 VPS 的 TaoBox 中选择：

```text
1. SSH 登录管理
3. GitHub 导入已有公钥
```

确认新会话可以用密钥登录后，再关闭密码登录。

## Ansible / 批量 SSH 管理

仓库仍保留早期批量管理能力：

```bash
pip install -r requirements.txt
ansible-playbook -i inventory/hosts.yml playbooks/bootstrap_public_key.yml --ask-pass
python scripts/render_ssh_config.py --inventory inventory/hosts.yml --output generated/ssh_config
```

相关示例见：

- `inventory/hosts.example.yml`
- `playbooks/bootstrap_public_key.yml`
- `playbooks/harden_ssh.yml`

## 安全提醒

- 私钥文件，例如 `id_ed25519`，不要上传 GitHub，不要发给别人。
- `.pub` 公钥可以导入 VPS 和 GitHub。
- 关闭密码登录前，务必先新开终端验证公钥登录成功。
- DD 重装、Docker prune、覆盖 Xray/Nginx 配置等操作具有破坏性，请提前备份。

## License

见 `LICENSE`。
