---
title: MoviePilot v3 部署与认证
category: 影视自动化
subcategory: MoviePilot
tags:
  - MoviePilot
  - Docker
  - PT
  - IYUU
created: 2026-08-24
updated: 2026-08-24
AIGC:
  ContentProducer: '001191110102MAD55U9H0F10002'
  ContentPropagator: '001191110102MAD55U9H0F10002'
  Label: '1'
  ProduceID: '1fcb973b-509b-475a-8cf0-4c94a4101a0b'
  PropagateID: '1fcb973b-509b-475a-8cf0-4c94a4101a0b'
  ReservedCode1: 'f4ba4b92-37bb-4fb8-854f-45ba0852dd2b'
  ReservedCode2: 'f4ba4b92-37bb-4fb8-854f-45ba0852dd2b'
---

# MoviePilot v3 部署与认证

## 架构概览

```
PT 站点 → MoviePilot 搜索/订阅 → Qbittorrent 下载到 NAS 本地临时目录
    → MoviePilot 整理（移动/复制）→ 115 网盘媒体目录
    → CloudDrive2 FUSE 挂载 → 飞牛影视（TrimeMedia）自动刮削
```

### 关键架构要点

- **115 网盘是"文件存储"模块**，不是下载器
- **下载器仅支持三种类型**：Qbittorrent、Transmission、Rtorrent
- **下载流程**：PT 种子 → QB 下载到 NAS 本地 → MoviePilot 整理到 115 网盘 → 飞牛影视刮削
- **站点核心逻辑**是 Cython 编译的 `.so` 文件，不可修改
- **QQ 通知是原生模块**，无需 NapCat 或 OneBot 中间件

## Docker Compose 部署

### docker-compose.yml 模板

```yaml
services:
  moviepilot:
    image: jxxghp/moviepilot-v3:latest
    container_name: moviepilot-v3
    hostname: moviepilot-v3
    restart: unless-stopped
    ports:
      - "13000:3000"   # Web UI
      - "13001:3001"   # 后端 API
    environment:
      NGINX_PORT: "3000"
      PORT: "3001"
      PUID: "0"
      PGID: "0"
      UMASK: "000"
      TZ: Asia/Shanghai
      SUPERUSER: admin
      AUTH_SITE: "iyuu"
      IYUU_SIGN: "<IYUU令牌>"
    volumes:
      - ./config:/config
      - ./core:/moviepilot/.cloakbrowser
      - <QB下载目录>:/downloads
```

### 关键配置项说明

| 环境变量 | 说明 | 必填 |
|---------|------|------|
| `SUPERUSER` | 管理员用户名 | 是 |
| `AUTH_SITE` | 认证站点（iyuu / 其他受支持站点） | 是 |
| `IYUU_SIGN` | IYUU 令牌 | AUTH_SITE=iyuu 时必填 |
| `NGINX_PORT` / `PORT` | Web UI / 后端端口 | 是 |
| `PUID` / `PGID` | 运行用户 UID/GID | 是 |

### 首次登录与密码重置

- 首次访问 `http://<NAS_IP>:13000`，使用 SUPERUSER 指定的用户名登录
- **密码重置**：通过 SSH 操作 SQLite 数据库（容器内无 sqlite3 命令）：

```bash
echo '<sudo密码>' | sudo -S docker exec moviepilot-v3 python3 -c "
import sqlite3
conn = sqlite3.connect('/config/user.db')
conn.execute(\"UPDATE users SET password='<新密码>' WHERE name='admin'\")
conn.commit()
conn.close()
"
```

> 注意：密码字段为明文存储，直接 UPDATE 即可。

## IYUU 认证机制

### 认证流程概述

MoviePilot v3 要求用户先通过一个受支持的 PT 站点认证才能使用站点搜索/订阅/下载功能。IYUU 是注册最简单的认证站点（微信扫码即可注册）。

### IYUU 认证前置条件

1. **注册 IYUU 账号**：访问 `https://iyuu.cn`，微信扫码注册，获取 UID 和令牌
2. **IYUU 账号必须绑定一个"合作站点"（PT 站点）**，否则认证返回"用户未绑定合作站点账号"错误
3. IYUU 支持 30 个合作站点，包括：pthome, m-team, hdhome, ourbits 等
4. 绑定 PT 站点需要提供该站点的 **UID** 和 **passkey**
5. **IYUU 绑定页面**：`https://vip.iyuu.cn/app/user/bind`

### Web UI 认证步骤

1. 登录 MoviePilot Web UI
2. 点击右上角用户头像 → "用户认证"
3. 填入 IYUU 令牌
4. 点击"开始认证"
5. 如果 IYUU 已绑定合作站点，认证成功
6. 如果未绑定合作站点，报错"用户未绑定合作站点账号"

> **已知行为**：`.so` 编译文件可能报"环境变量 IYUU_SIGN 未设置"，但不影响 Web UI 认证流程。

### 认证完成后添加 PT 站点

认证通过后，可在 MoviePilot 中添加 PT 站点：
- 需要提供站点的 Cookie 和 User-Agent
- 站点搜索/订阅功能依赖站点核心逻辑（.so 编译文件）

## SSH 操作 MoviePilot 数据库

容器内无 `sqlite3` 命令，需使用 Python3 操作数据库：

```bash
# 查询数据
echo '<sudo密码>' | sudo -S docker exec moviepilot-v3 python3 -c "
import sqlite3
conn = sqlite3.connect('/config/user.db')
cursor = conn.execute('SELECT * FROM users')
print(cursor.fetchall())
conn.close()
"
```

### 通过数据库修改 MoviePilot 配置

MoviePilot 的系统配置存储在 `systemconfig` 表中，键值对格式：

```bash
# 查看所有配置键
echo '<sudo密码>' | sudo -S docker exec moviepilot-v3 python3 -c "
import sqlite3, json
conn = sqlite3.connect('/config/user.db')
cursor = conn.execute('SELECT key, value FROM systemconfig')
for row in cursor:
    print(f'{row[0]}: {row[1][:200]}')
conn.close()
"

# 修改目录配置（如传输方式 move → copy）
echo '<sudo密码>' | sudo -S docker exec moviepilot-v3 python3 -c "
import sqlite3, json
conn = sqlite3.connect('/config/user.db')
row = conn.execute(\"SELECT value FROM systemconfig WHERE key='Directories'\").fetchone()
config = json.loads(row[0])
config[0]['transfer_type'] = 'copy'
conn.execute(\"UPDATE systemconfig SET value=? WHERE key='Directories'\", (json.dumps(config),))
conn.commit()
conn.close()
"
```

> **注意**：修改数据库后需重启 MoviePilot 容器使配置生效。

## 容器内脚本持久化

> **关键陷阱**：写入容器内 `/tmp/` 的脚本和缓存文件在容器重启后会丢失。必须持久化到 `/config/scripts/` 目录。

| 容器内路径 | NAS 路径 | 说明 |
|-----------|---------|------|
| `/config/scripts/` | `/vol2/1000/docker/MoviePilot/config/scripts/` | 自定义脚本和缓存 |
| `/config/user.db` | `/vol2/1000/docker/MoviePilot/config/user.db` | 配置数据库 |
| `/config/app.env` | `/vol2/1000/docker/MoviePilot/config/app.env` | 环境变量配置 |

## 容器内 cron 自动启动持久化

> **关键陷阱**：MoviePilot 容器默认不运行 cron 守护进程，容器重启后 crontab 配置丢失。

**持久化方案三步走**：

1. **备份 crontab**：`crontab -l > /config/scripts/crontab.txt`
2. **创建启动脚本** `/config/scripts/start_cron.sh`：
   ```bash
   #!/bin/bash
   crontab /config/scripts/crontab.txt
   /usr/sbin/cron
   ```
3. **修改 entrypoint.sh**，在 nginx 启动前插入调用：
   ```bash
   cp /app/docker/entrypoint.sh /config/scripts/entrypoint.sh.bak
   sed -i '/nginx/i /config/scripts/start_cron.sh > /dev/null 2>&1 &' /app/docker/entrypoint.sh
   ```

> 容器更新可能覆盖 entrypoint.sh，更新后需重新检查。

## 相关笔记

- [[下载器与存储对接]]
- [[媒体服务器对接]]
- [[QQ机器人通知订阅]]
- [[PT站点保号策略]]