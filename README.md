# vps-ssh-fleet

用**一套你自己生成的 SSH 密钥**统一管理多台 VPS 的 GitHub 项目模板。

> 适合：你有很多自己的 VPS，想把同一把公钥分发到所有机器，然后通过统一的 SSH 别名和配置来管理。

## 项目目标

- 用你自己的 SSH 公钥登录全部 VPS
- 不再依赖“别人帮你生成”的可疑密钥
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
├─ ansible.cfg
├─ requirements.txt
├─ README.md
├─ docs/
│  └─ SECURITY.md
├─ inventory/
│  └─ hosts.example.yml
├─ playbooks/
│  ├─ bootstrap_public_key.yml
│  └─ harden_ssh.yml
└─ scripts/
   └─ render_ssh_config.py
```

---

## 快速开始

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

