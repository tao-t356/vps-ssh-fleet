# vps-ssh-fleet

用**一套你自己生成的 SSH 密钥**统一管理多台 VPS 的 GitHub 项目模板。

> 适合：你有很多自己的 VPS，想把同一把公钥分发到所有机器，然后通过统一的 SSH 别名和配置来管理。

## Windows + GitHub + VPS 完整流程（推荐先看）

如果你和我刚才的对话场景一样：

- 本机是 **Windows**
- 公钥想统一放在 **GitHub 账号**
- 登录到每台 VPS 后，用菜单脚本导入公钥

那就按下面这套流程走。

---

### 第 1 步：在 Windows 生成 SSH 密钥对

打开 **PowerShell**，执行：

```powershell
ssh-keygen -t ed25519 -C "你的GitHub用户名@windows"
```

常见提示：

1. 看到保存路径：

   ```text
   Enter file in which to save the key (C:\Users\你的用户名\.ssh\id_ed25519):
   ```

   直接回车即可。

2. 看到 passphrase：

   ```text
   Enter passphrase (empty for no passphrase):
   ```

   - 想省事：直接回车
   - 想更安全：设置一个口令

生成完成后，通常会得到两个文件：

- 私钥：`C:\Users\你的Windows用户名\.ssh\id_ed25519`
- 公钥：`C:\Users\你的Windows用户名\.ssh\id_ed25519.pub`

可以用下面命令确认：

```powershell
Get-ChildItem $HOME\.ssh
```

---

### 第 2 步：复制 Windows 公钥

查看公钥：

```powershell
Get-Content $HOME\.ssh\id_ed25519.pub
```

复制到剪贴板：

```powershell
Get-Content $HOME\.ssh\id_ed25519.pub | Set-Clipboard
```

> 注意：
>
> - **`.pub` 是公钥**，可以上传到 GitHub、可以导入 VPS
> - **没有后缀的 `id_ed25519` 是私钥**，绝对不要上传到 GitHub，也不要发给别人

---

### 第 3 步：把公钥上传到 GitHub 账号

注意：这里是 **GitHub 账号设置**，**不是仓库设置**。

直接打开：

[https://github.com/settings/keys](https://github.com/settings/keys)

或者手动点击：

1. 右上角头像
2. **Settings**
3. 左侧 **Access**
4. **SSH and GPG keys**
5. **New SSH key** / **Add SSH key**

填写建议：

- **Title**：例如 `facker-windows`
- **Key type**：`Authentication Key`
- **Key**：粘贴刚才复制的 `id_ed25519.pub` 整整一行

保存后，GitHub 会给你发一封提醒邮件，这是正常的。

如果想确认 GitHub 上已经有这把公钥，可以执行：

```powershell
curl.exe -H "jshook: <YOUR_JSHOOK>" https://github.com/你的GitHub用户名.keys
```

如果你当前环境里的 `jshook` 就是 `123`，那就是：

```powershell
curl.exe -H "jshook: 123" https://github.com/你的GitHub用户名.keys
```

返回内容里如果能看到你的 `ssh-ed25519 ...` 那一行，就说明上传成功了。

---

### 第 4 步：登录 VPS，让 VPS 自己从 GitHub 拉脚本

先正常用密码登录 VPS。

登录后执行：

```bash
curl -fsSL -H "jshook: <YOUR_JSHOOK>" https://raw.githubusercontent.com/tao-t356/vps-ssh-fleet/main/bootstrap-vps.sh | bash
```

如果你当前环境里的 `jshook` 是 `123`，可直接用：

```bash
curl -fsSL -H "jshook: 123" https://raw.githubusercontent.com/tao-t356/vps-ssh-fleet/main/bootstrap-vps.sh | bash
```

这一步会自动：

1. 从 GitHub 拉取最新菜单脚本
2. 保存到 `~/ssh-key-menu.sh`
3. 自动加执行权限
4. 默认安装快捷命令 `f`
5. 立即打开菜单

以后你在 VPS 里直接输入：

```bash
f
```

就可以再次打开菜单。

---

### 第 5 步：在 VPS 工具箱里从 GitHub 导入公钥

菜单打开后，输入：

```text
1
```

也就是：

- `1. SSH 登录管理`

进入 SSH 子菜单后，再输入：

```text
3
```

也就是：

- `3. GitHub 导入已有公钥`

然后依次输入：

1. **GitHub 用户名**
2. **jshook**

脚本会把：

```text
https://github.com/你的GitHub用户名.keys
```

里的公钥导入到当前用户的：

```text
~/.ssh/authorized_keys
```

你可以在 VPS 上确认一下：

```bash
cat ~/.ssh/authorized_keys
```

---

### 第 6 步：回到 Windows 测试密钥登录

#### PowerShell 命令行测试

如果你给 `root` 导入了公钥：

```powershell
ssh root@你的VPSIP
```

如果你是普通用户，就换成对应用户名。

#### 如果你用的是图形 SSH 客户端（例如 Termius）

要点只有一个：

- **私钥文件** 要选：

  ```text
  C:\Users\你的Windows用户名\.ssh\id_ed25519
  ```

- **不要选 `.pub` 文件**

如果你在生成密钥时设置了 passphrase，客户端要求输入的是：

- **私钥口令**

不是 VPS 的登录密码。

---

### 第 7 步：确认密钥登录成功后，再关闭密码登录

这一步一定要最后做。

先确认：

- 新开一个终端 / 客户端
- 用密钥能成功登录 VPS

确认成功后，再回到 VPS 菜单，输入：

```text
8
```

也就是：

- `8. 关闭密码登录`

---

### 最常见的几个坑

#### 1）把仓库设置当成账号设置

错误位置：

- `https://github.com/你的用户名/某个仓库/settings`

正确位置：

- `https://github.com/settings/keys`

#### 2）把私钥上传到 GitHub

绝对不要上传：

```text
C:\Users\你的Windows用户名\.ssh\id_ed25519
```

上传到 GitHub 的只能是：

```text
C:\Users\你的Windows用户名\.ssh\id_ed25519.pub
```

#### 3）客户端里选错文件

连接 VPS 时，客户端应该选：

- 私钥：`id_ed25519`

不是：

- 公钥：`id_ed25519.pub`

#### 4）还没测试成功就关闭密码登录

一定先测试：

- 密钥登录成功

再去菜单里选：

- `8. 关闭密码登录`

---

## 现在最简单的用法

如果你想要的是：

- 公钥统一挂在 GitHub 账号上
- 本地只运行一个脚本
- 一路按几次回车，就把多台 VPS 开成密钥登录

那就优先用下面这个 **极简模式**。

---

## VPS 内一键菜单模式（更接近你截图那种）

如果你的习惯是：

- 先手动登录进 VPS
- 然后在 VPS 里面顺手改 SSH 登录方式
- 希望有一个交互菜单，按数字选择

那就用这个单文件脚本：

`D:\vs\vps-ssh-fleet\ssh-key-menu.sh`

### 用法

先把脚本传到 VPS：

```powershell
scp D:\vs\vps-ssh-fleet\ssh-key-menu.sh root@你的VPSIP:/root/
```

然后登录 VPS 执行：

```bash
chmod +x ~/ssh-key-menu.sh
./ssh-key-menu.sh
```

### 当前工具箱主菜单

- `1` SSH 登录管理
- `2` 系统信息查询
- `3` 应用市场
- `4` 系统清理
- `5` Docker 管理
- `6` 常用端口放行
- `9` 更新工具箱
- `0` 退出

### SSH 登录管理子菜单

- `1` 生成本机密钥对
- `2` 手动输入一行公钥
- `3` 从 `GitHub 用户名.keys` 导入公钥
- `4` 从 URL 导入已有公钥
- `5` 编辑 `~/.ssh/authorized_keys`
- `6` 查看本机密钥
- `7` 查看当前 `authorized_keys`
- `8` 关闭密码登录
- `9` 开启密码登录

### 应用市场

- `1` 运行 `vless-xhttp-reality-self`
- `2` 查看 `vless-xhttp-reality-self` 说明
- `3` 安装 `Docker + Nginx Proxy Manager`
- `4` 查看 `Docker + Nginx Proxy Manager` 说明
- `5` 安装 `NextTrace`
- `6` 查看 `NextTrace` 说明
- `7` 启用 `BBR`
- `8` 查看 `BBR` 状态

### Docker 管理

- `1` 查看 Docker 状态
- `2` 查看全部容器
- `3` 启动全部容器
- `4` 停止全部容器
- `5` 重启全部容器
- `6` 查看容器日志
- `7` `docker system prune`

### 常用端口放行

- `1` 放行 `22/tcp`
- `2` 放行 `80/tcp`
- `3` 放行 `443/tcp`
- `4` 一次放行 `22/80/443`
- `5` 放行自定义端口
- `6` 查看防火墙状态

> 如果你在当前这个本地环境里用 GitHub / URL 导入，脚本会让你输入 `jshook`。

---

## VPS 直接一键拉取运行

如果你已经登录进 VPS，想让 VPS **自己从 GitHub 拉脚本并立刻运行**，直接执行：

```bash
curl -fsSL -H "jshook: 123" https://raw.githubusercontent.com/tao-t356/vps-ssh-fleet/main/bootstrap-vps.sh | bash
```

它会：

1. 从 GitHub 拉取最新工具箱脚本
2. 保存到 `~/ssh-key-menu.sh`
3. 自动加执行权限
4. 默认安装一个快捷命令 `f`
5. 立即打开 VPS 工具箱

以后你在 VPS 里直接输入：

```bash
f
```

就能再次打开菜单。

如果你只想下载，不想立刻运行：

```bash
curl -fsSL -H "jshook: 123" https://raw.githubusercontent.com/tao-t356/vps-ssh-fleet/main/bootstrap-vps.sh | bash -s -- --no-run
```

如果你想换成别的快捷命令，比如 `menu`：

```bash
curl -fsSL -H "jshook: 123" https://raw.githubusercontent.com/tao-t356/vps-ssh-fleet/main/bootstrap-vps.sh | bash -s -- --shortcut menu
```

---

## 极简模式（Windows / 一路回车）

### 0) 先准备一份主机清单

第一次只要填这一个文件：

`inventory/hosts.csv`

如果还没有，就复制：

```powershell
Copy-Item .\inventory\hosts.csv.example .\inventory\hosts.csv
```

格式很简单：

```csv
alias,host,port,user,password
hk-1,203.0.113.10,22,root,
us-1,198.51.100.20,22,root,
sg-1,192.0.2.30,22,root,
```

说明：

- `alias`：你以后本地连接用的名字
- `host`：VPS IP / 域名
- `port`：默认 22
- `user`：现在还能密码登录的用户，通常是 `root`
- `password`：可以留空；脚本会统一问你一次密码

---

### 1) 确保你的公钥已经在 GitHub 上

也就是这个地址能返回你的公钥：

```text
https://github.com/<你的用户名>.keys
```

> 注意：上传到 GitHub 的只能是**公钥**，私钥永远不要上传。

---

### 2) 运行一键脚本

在项目根目录执行：

```powershell
.\quick-start.ps1
```

它会做这些事：

1. 读取 `inventory/hosts.csv`
2. 从 `github.com/<用户名>.keys` 拉取公钥
3. 用密码 SSH 登录每台 VPS
4. 把公钥写入 `~/.ssh/authorized_keys`
5. 自动生成 `generated/ssh_config`
6. 可选：验证成功后关闭密码登录

默认就是**尽量少输入**：

- GitHub 用户名
- jshook（仅当前这个本地环境需要）
- SSH 密码（可统一输入一次）
- 是否关闭密码登录（默认否，更安全）

---

### 3) 完成后直接连接

```powershell
ssh -F .\generated\ssh_config hk-1
```

---

## 项目目标

- 用你自己的 SSH 公钥登录全部 VPS
- 不再依赖“别人帮你生成”的可疑密钥
- 支持 GitHub `username.keys` 作为统一公钥来源
- 用 Ansible 批量下发公钥
- 自动生成本地 `ssh_config`
- 可选执行 SSH 基础加固

## 安全原则

1. **不要把私钥上传到 GitHub**
2. **不要继续使用别人脚本生成的私钥**
3. 只把**公钥**部署到服务器
4. 建议为私钥设置 passphrase
5. 建议把真实主机清单放在 `inventory/hosts.yml`，并保持未提交状态

---

## 目录结构

```text
vps-ssh-fleet/
├─ .gitignore
├─ quick-start.ps1
├─ ansible.cfg
├─ requirements.txt
├─ README.md
├─ docs/
│  └─ SECURITY.md
├─ inventory/
│  ├─ hosts.csv.example
│  └─ hosts.example.yml
├─ playbooks/
│  ├─ bootstrap_public_key.yml
│  └─ harden_ssh.yml
└─ scripts/
   ├─ enable_github_key_login.py
   └─ render_ssh_config.py
```

---

## 快速开始

> 如果你是 Windows 用户，并且想要“少输命令、少折腾”，优先看上面的 **极简模式**。下面是更通用的高级模式。

### 1) 在你自己的电脑生成密钥

```bash
ssh-keygen -t ed25519 -C "admin@my-vps-fleet"
```

默认会得到：

- 私钥：`~/.ssh/id_ed25519`
- 公钥：`~/.ssh/id_ed25519.pub`

---

### 2) 复制示例清单

```bash
cp inventory/hosts.example.yml inventory/hosts.yml
```

然后把你的 VPS 信息填进去。

---

### 3) 批量下发你的公钥

如果目标机器目前仍然允许密码登录，可以通过 Ansible 一次性把公钥写入各台 VPS 的 `authorized_keys`：

```bash
ansible-playbook -i inventory/hosts.yml playbooks/bootstrap_public_key.yml --ask-pass
```

如果你连接的是普通用户且需要 sudo：

```bash
ansible-playbook -i inventory/hosts.yml playbooks/bootstrap_public_key.yml --ask-pass --ask-become-pass
```

---

### 4) 生成本地 SSH 配置

先安装依赖：

```bash
pip install -r requirements.txt
```

再执行：

```bash
python scripts/render_ssh_config.py --inventory inventory/hosts.yml --output generated/ssh_config
```

生成后，你可以这样连接：

```bash
ssh -F generated/ssh_config hk-1
ssh -F generated/ssh_config us-1
```

如果你想长期使用，可把生成文件 `Include` 到你本地的 SSH 配置中：

```sshconfig
Include /absolute/path/to/generated/ssh_config
```

Windows OpenSSH 示例：

```sshconfig
Include C:/Users/YourUser/.ssh/generated_vps_config
```

---

### 5) 可选：执行 SSH 基础加固

确认公钥登录已经成功后，再考虑执行：

```bash
ansible-playbook -i inventory/hosts.yml playbooks/harden_ssh.yml
```

这个 playbook 会：

- 关闭密码登录
- 保留公钥登录
- 默认把 root 登录改成 `prohibit-password`

> **先验证公钥登录可用，再做这一步。**

---

## inventory 示例说明

见：`inventory/hosts.example.yml`

核心字段：

- `ssh_public_key_path`：你的本地公钥路径
- `ssh_private_key_path`：你的本地私钥路径（仅用于生成 ssh config）
- `managed_ssh_user`：要写入公钥的远程用户
- `ansible_host`：服务器 IP / 域名
- `ansible_user`：当前 Ansible 首次登录用的用户
- `ansible_port`：SSH 端口
- `ssh_alias`：本地连接别名

---

## 推荐工作流

1. 自己重新生成一套密钥
2. 用本项目把公钥分发到所有 VPS
3. 确认都能用公钥登录
4. 删除旧公钥
5. 再禁用密码登录

---

## Windows 用户建议

如果你本机是 Windows：

- 生成 ssh config：直接用 Python 即可
- 跑 Ansible：推荐用 **WSL / Linux 控制机**
- 如果你只是想快速切到密钥登录：直接用 `quick-start.ps1`

---

## 以后可以继续扩展

这个项目后面可以继续加：

- 分环境清单（prod / dev / test）
- 自动检查连通性
- 批量执行运维命令
- Fail2ban / UFW / 基础安全策略
- GitHub Actions 做语法检查

---

## 重要提醒

如果你现在使用的是“别人脚本生成的密钥”：

- 请把它视为**不可信**
- 最好尽快替换成你自己生成的新密钥
- 并清理所有 VPS 上的旧公钥记录
