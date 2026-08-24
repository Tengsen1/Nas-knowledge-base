---
title: mihomo 代理网关部署与排障
category: NAS运维
subcategory: 代理网关
tags:
  - fnOS
  - mihomo
  - Clash
  - 代理
created: 2026-08-24
updated: 2026-08-24
AIGC:
  ContentProducer: '001191110102MAD55U9H0F10002'
  ContentPropagator: '001191110102MAD55U9H0F10002'
  Label: '1'
  ProduceID: 'fd26197b-b697-4688-93ca-8bda6f634042'
  PropagateID: 'fd26197b-b697-4688-93ca-8bda6f634042'
  ReservedCode1: '3991d4da-9ced-4be5-b2ae-66703a7b451c'
  ReservedCode2: '3991d4da-9ced-4be5-b2ae-66703a7b451c'
---

# mihomo 代理网关部署与排障

## 推荐方案

在飞牛 NAS 上部署透明代理网关，推荐使用 **mihomo（Clash Meta 内核）+ MetaCubeXD Web 面板**：
- 项目参考：https://github.com/Lgugeng/mihomo-nas-proxy
- Docker 镜像：`metacubex/mihomo:Alpha`
- Web 面板：MetaCubeXD（从 GitHub releases 下载）

## docker-compose.yml 模板

```yaml
services:
  mihomo:
    image: docker.io/metacubex/mihomo:Alpha
    container_name: mihomo
    restart: unless-stopped
    network_mode: host
    cap_add:
      - NET_ADMIN
      - NET_RAW
    volumes:
      - ./mihomo:/root/.config/mihomo
      - /dev/net/tun:/dev/net/tun
      - /etc/localtime:/etc/localtime:ro
    healthcheck:
      test: ["CMD-SHELL", "wget -q -O /dev/null --header 'Authorization: Bearer <密钥>' http://127.0.0.1:9090/version || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 15s
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

## 关键陷阱：健康检查 401 Unauthorized

> **当 config.yaml 中设置了 `secret` 密钥时，健康检查的 `wget` 请求 `/version` 接口会返回 401 Unauthorized，导致容器状态为 unhealthy。**

**解决方案**：在 docker-compose.yml 的 healthcheck 命令中加上 `--header 'Authorization: Bearer <密钥>'`。

## 关键陷阱：MMDB 下载失败（鸡生蛋问题）

> **mihomo 首次启动时需要下载 GeoIP MMDB 数据库，但如果 NAS 本身无法访问外网（代理尚未启动），下载会超时失败，导致容器崩溃循环。**

**解决方案**：
1. 在本机（有代理的环境）下载 MMDB 文件：
   ```bash
   curl -L -o geoip.metadb https://github.com/MetaCubeX/meta-rules-dat/releases/latest/download/geoip.metadb
   ```
2. 通过 SCP 上传到 NAS 的 mihomo 配置目录：
   ```bash
   sshpass -p '<密码>' scp geoip.metadb <用户名>@<NAS_IP>:/vol2/1000/docker/mihomo/geoip.metadb
   ```
3. 重启容器

## 关键陷阱：TUN 模式下 BT 流量经过代理

> **mihomo 使用 host 网络模式 + TUN 模式（`enable: true`, `auto-route: true`）时，会劫持 NAS 所有网络流量。如果 rules 最后一条是 `MATCH,PROXY`，未匹配的 BT 国际 peer 流量会被发送到代理服务器，导致代理机场被封（如 636GB/天 BT 流量打爆代理）。**

**根因分析**：
- TUN 模式劫持所有流量 → BT 连接的国际 peer IP 不匹配任何域名/GEOIP 规则 → 命中 `MATCH,PROXY` 兜底规则 → BT 流量经过代理
- Docker bridge 网络的容器（如 qBittorrent，子网 `172.23.0.0/16`）流量也被 TUN 劫持

**解决方案**：在 `MATCH,PROXY` 之前插入直连规则，让特定子网走直连：

```yaml
rules:
  # ... 已有规则 ...
  - SRC-IP-CIDR,172.23.0.0/16,DIRECT   # Docker bridge 网络容器直连
  - MATCH,PROXY                          # 兜底规则
```

> **注意**：`SRC-IP-CIDR` 规则匹配源 IP。需根据实际 Docker 网络子网调整（通过 `docker network inspect <网络名>` 查看 Subnet）。

## 关键陷阱：容器内用 sed 修改 YAML 配置导致格式错误

> **在 mihomo 容器内使用 `sed -i` 修改 config.yaml 时，极易引入 YAML 格式错误（缩进不对、缺少空格等），导致 mihomo 解析失败、容器卡在"加载中"状态无法启动。**

**安全做法**：
1. **修改前务必备份**：`cp config.yaml config.yaml.bak`
2. **优先通过宿主机文件管理编辑**：mihomo 配置目录映射到宿主机（如 `/vol2/1000/docker/mihomo/config.yaml`），通过 fnOS 文件管理或 SSH 直接编辑宿主机文件更安全
3. **修改后验证 YAML 格式**：在容器内执行 `wget -q -O- http://127.0.0.1:9090/version` 或查看容器日志确认无解析错误
4. **恢复方法**：如果容器卡在"加载中"，通过 fnOS 文件管理找到宿主机上的 `config.yaml.bak`，覆盖回 `config.yaml`，然后通过 Docker UI 重启容器

> **mihomo 容器内没有 /bin/bash，需用 /bin/sh 连接终端。** BusyBox 环境下 `wget` 不支持 PUT 方法，无法通过 API 热重载配置，只能重启容器。

## 关键陷阱：proxy-providers UA 问题

> **mihomo 的 `proxy-providers` 配置为 `type: http` 时，默认 User-Agent 可能导致订阅服务器返回 base64 编码内容而非 Clash YAML 格式。**

**解决方案**：将订阅内容下载为本地文件，改用 `type: file` 引用：

```yaml
proxy-providers:
  airport:
    type: file
    path: ./providers/airport.yaml
    health-check:
      enable: true
      interval: 600
      url: https://www.gstatic.com/generate_204
```

操作步骤：
1. 在本机用带 clash UA 的 curl 下载订阅内容：
   ```bash
   curl -L -o airport.yaml --header "User-Agent: clash" "<订阅URL>"
   ```
2. 验证文件内容为 YAML 格式（开头应为 `proxies:`）
3. 通过 SCP 上传到 NAS 的 mihomo providers 目录
4. 修改 config.yaml 中 proxy-providers 为 `type: file`
5. 重启 mihomo 容器

## config.yaml 关键配置项

| 配置项 | 说明 | 推荐值 |
|--------|------|--------|
| `mixed-port` | HTTP+SOCKS 混合代理端口 | 7890 |
| `external-controller` | API 监听地址 | `0.0.0.0:9090`（允许局域网访问 Web UI） |
| `secret` | API 密钥 | 随机 32 位 hex（`openssl rand -hex 16`） |
| `tun.enable` | TUN 透明代理 | `true`（全内网代理时开启） |
| `tun.auto-route` | 自动路由 | `true` |
| `proxy-providers` | 订阅源 | type: file（推荐）或 type: http + clash UA |

## MetaCubeXD UI 部署

```bash
# 下载并解压
curl -L -o metacubexd.tgz https://github.com/MetaCubeX/metacubexd/releases/latest/download/compressed-dist.tgz
mkdir -p metacubexd-ui && tar -xzf metacubexd.tgz -C metacubexd-ui

# 上传到 NAS
sshpass -p '<密码>' scp -r metacubexd-ui/* <用户名>@<NAS_IP>:/vol2/1000/docker/mihomo/ui/
```

## 部署后验证

```bash
# 检查容器状态
sshpass -p '<密码>' ssh <用户名>@<NAS_IP> "echo '<密码>' | sudo -S docker ps --filter name=mihomo --format '{{.Names}} {{.Status}}'"

# 检查 API
curl -s --noproxy '*' -H "Authorization: Bearer <密钥>" http://<NAS_IP>:9090/version

# 检查订阅节点
curl -s --noproxy '*' -H "Authorization: Bearer <密钥>" http://<NAS_IP>:9090/providers/proxies

# 检查 Web UI
curl -s --noproxy '*' -o /dev/null -w "%{http_code}" http://<NAS_IP>:9090/ui/
```

## 验证时绕过本机代理

> **本机可能设置了 `http_proxy` 环境变量，导致 curl 请求 NAS 时走了本地代理而失败（502 Bad Gateway）。**

验证 NAS 服务时，务必加 `--noproxy '*'` 参数。

## 完整部署流程清单

1. [ ] 登录飞牛 fnOS Web UI
2. [ ] 通过 Compose 界面创建项目（填入 docker-compose.yml，选择路径）
3. [ ] 等待镜像拉取完成
4. [ ] 通过 SSH 创建 config.yaml 并 SCP 上传到配置目录
5. [ ] 创建 providers 和 ui 子目录
6. [ ] 下载 MetaCubeXD UI 并 SCP 上传到 ui 目录
7. [ ] 下载 GeoIP MMDB 并 SCP 上传到配置目录（避免鸡生蛋问题）
8. [ ] 修改 docker-compose.yml 健康检查命令（加 Authorization header）
9. [ ] 通过 SSH 重新部署容器
10. [ ] 等待健康检查通过（`docker ps` 确认 healthy）
11. [ ] 验证 API、Web UI、订阅节点

## 相关笔记

- [[SSH操作NAS]]
- [[MoviePilot部署与认证]]