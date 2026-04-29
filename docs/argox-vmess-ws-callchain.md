# ArgoX VMess + WS + Argo 调用链审计

目标：从 `scripts/upstream/argox.sh` 中只保留/调用 **VMess + WebSocket + Cloudflare Argo Tunnel** 相关能力。

## 关键结论

ArgoX 原脚本的协议列表中，`VMess + WS` 对应协议字母为：

```bash
f) VMESS_WS_PORT=$(( START_PORT + i ))
```

节点 tag：

```bash
NODE_TAG[4]="vmess-ws"
```

最终 Xray inbound 对应代码块位于 `install_argox()` 中的 `case "$proto" in f)` 分支：

```json
{
  "tag": "${NODE_NAME} vmess-ws",
  "protocol": "vmess",
  "port": ${VMESS_WS_PORT},
  "listen": "127.0.0.1",
  "settings": {
    "clients": [
      {
        "id": "${UUID}",
        "alterId": 0
      }
    ]
  },
  "streamSettings": {
    "network": "ws",
    "wsSettings": {
      "path": "/${WS_PATH}-vm"
    }
  }
}
```

## Argo 隧道链路

Argo 隧道变量由 `argo_variable()` 处理：

- 空 `ARGO_DOMAIN` + 空认证信息：使用 Cloudflare 临时隧道 `trycloudflare.com`
- 有 `ARGO_TOKEN` + `ARGO_DOMAIN`：使用 Token 固定隧道
- 有 `ARGO_JSON` + `ARGO_DOMAIN`：使用 Json 固定隧道
- 有 Cloudflare API Token + 域名：可自动创建 Tunnel 与 DNS

`install_argox()` 中根据变量生成 `ARGO_RUNS`：

```bash
# Json 固定隧道
$WORK_DIR/cloudflared tunnel --edge-ip-version auto --config $WORK_DIR/tunnel.yml run

# Token 固定隧道
$WORK_DIR/cloudflared tunnel --edge-ip-version auto run --token ${ARGO_TOKEN}

# 临时隧道
$WORK_DIR/cloudflared tunnel --edge-ip-version auto --no-autoupdate --url http://localhost:${NGINX_PORT}
```

## 订阅 / 节点输出链路

节点输出由 `export_list()` 生成。

VMess + WS 输出核心：

```bash
vmess://$(echo -n "$VMESS" | base64 -w0)
```

订阅文件写入：

```bash
$WORK_DIR/subscribe/base64
$WORK_DIR/subscribe/clash
$WORK_DIR/subscribe/shadowrocket
$WORK_DIR/subscribe/sing-box
$WORK_DIR/list
```

主要订阅 URL：

```text
https://${ARGO_DOMAIN}/${UUID}/base64
https://${ARGO_DOMAIN}/${UUID}/clash
https://${ARGO_DOMAIN}/${UUID}/shadowrocket
https://${ARGO_DOMAIN}/${UUID}/auto
```

## V1 实施策略

不直接手工删除 ArgoX 大量函数，先用 `-f config` 非交互安装方式强制协议只选 `f`。

原因：

1. ArgoX 内部依赖复杂，包括架构检测、依赖安装、cloudflared/xray/nginx 下载、systemd/openrc、订阅模板、临时隧道域名探测。
2. 直接瘦身风险较高，容易遗漏隐式变量或工具函数。
3. V1 应优先保证 VMess+WS+Argo 能真实跑通。

V1 包装脚本应生成临时配置：

```bash
INSTALL_PROTOCOLS=(f)
START_PORT=30000
VMESS_WS_PORT=30000
WS_PATH="argox"
NGINX_PORT=8001
UUID="..."
NODE_NAME="..."
```

然后调用本仓库归档的 ArgoX：

```bash
bash scripts/upstream/argox.sh -f /tmp/config
```

## 后续 V2 瘦身方向

可保留：

- 系统/架构检测
- 依赖安装
- `argo_variable`
- `xray_variable` 中 VMess+WS 所需变量部分
- `install_argox` 中 `f)` VMess block
- nginx 反代/订阅输出相关
- `export_list` 中 `vmess-ws` 输出部分
- `uninstall`

可删除：

- Reality / Hysteria2 / Trojan / Shadowsocks / XHTTP / Direct 协议
- 协议增删菜单
- BBR 外链菜单
- sing-box/sba 外链菜单
- 无关检测项
