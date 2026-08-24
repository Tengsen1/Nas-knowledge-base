---
title: Sun-Panel 导航面板部署
category: NAS运维
subcategory: 应用部署
tags:
  - fnOS
  - Docker
  - Sun-Panel
created: 2026-08-24
updated: 2026-08-24
AIGC:
  ContentProducer: '001191110102MAD55U9H0F10002'
  ContentPropagator: '001191110102MAD55U9H0F10002'
  Label: '1'
  ProduceID: '5b15c220-6536-42b4-b28c-1631d241c117'
  PropagateID: '5b15c220-6536-42b4-b28c-1631d241c117'
  ReservedCode1: 'd3a4483a-e695-4dfd-b3bc-5d55535cdeec'
  ReservedCode2: 'd3a4483a-e695-4dfd-b3bc-5d55535cdeec'
---

# Sun-Panel 导航面板部署

Sun-Panel 是一个 NAS/服务器导航面板，支持 Docker 部署，可通过挂载 docker.sock 显示容器状态。

## docker-compose.yml

```yaml
services:
  sun-panel:
    image: hslr/sun-panel:latest
    container_name: sun-panel
    restart: unless-stopped
    ports:
      - "3002:3002"
    volumes:
      - ./conf:/app/conf
      - ./uploads:/app/uploads
      - ./database:/app/database
      - /var/run/docker.sock:/var/run/docker.sock
```

访问地址：`http://10.0.0.100:3002`

## 关键陷阱：数据库实际路径与 volume 挂载不一致

> **Sun-Panel 的 SQLite 数据库实际存储在 `./conf/database/database.db`（由 conf.ini 中 `file_path=./conf/database/database.db` 指定），而非 `./database/database.db`。即使 docker-compose.yml 挂载了 `./database:/app/database`，该挂载对 SQLite 数据库无效。**

- 清理旧数据时**必须删除 `conf/` 目录**（含 `conf/database/`），仅删除 `database/` 目录不会清除实际数据库
- 备份/迁移数据时应备份 `conf/database/database.db`，而非 `database/` 目录
- 此陷阱可推广至任何通过配置文件指定数据库路径的应用：**始终以应用配置文件中的路径为准，不要假设 volume 挂载路径就是数据实际位置**

## 关键陷阱：密码重置必须用容器内置命令

> **Sun-Panel 密码使用加盐哈希存储，直接修改 SQLite 数据库中的 password 字段为 MD5 值无法登录。必须使用容器内置重置命令。**

```bash
# 正确的密码重置方式
sshpass -p '<密码>' ssh <用户名>@<NAS_IP> \
  "echo '<密码>' | sudo -S docker exec sun-panel ./sun-panel -password-reset"
```

重置后默认凭据：`admin@sun.cc` / `12345678`

> **注意**：默认密码是 `12345678`（8 位），不是 `123456`。

## 从 1Panel 迁移到 fnOS 原生 Compose 部署

1. **检查 1Panel 版数据是否为空**
2. **删除 1Panel 容器**：`docker rm -f 1Panel-<应用名>-<随机后缀>`
3. **备份旧数据**：`cp -a <旧目录> <旧目录>.bak-$(date +%Y%m%d)`
4. **在 `/vol2/1000/docker/<应用名>/` 下创建新的 Compose 项目**
5. **启动并验证**：`docker compose up -d`

> 1Panel 管理的容器名格式为 `1Panel-<应用名>-<随机后缀>`，可通过 `docker ps --filter name=1Panel` 查找。

## 相关笔记

- [[Docker-Compose管理]]
- [[SSH操作NAS]]