---
title: SSH 操作飞牛 NAS
category: NAS运维
subcategory: fnOS系统管理
tags:
  - fnOS
  - SSH
  - Docker
created: 2026-08-24
updated: 2026-08-24
AIGC:
  ContentProducer: '001191110102MAD55U9H0F10002'
  ContentPropagator: '001191110102MAD55U9H0F10002'
  Label: '1'
  ProduceID: 'e9704343-7eaf-4e02-a2a5-1fe6491eef0c'
  PropagateID: 'e9704343-7eaf-4e02-a2a5-1fe6491eef0c'
  ReservedCode1: 'a4c6c59e-251c-455d-8017-96c5e11d1e9b'
  ReservedCode2: 'a4c6c59e-251c-455d-8017-96c5e11d1e9b'
---

# SSH 操作飞牛 NAS

## SSH 连接方式

飞牛 NAS 默认开启 SSH。使用 `sshpass` 实现非交互式密码认证：

```bash
# 安装 sshpass（macOS）
brew install hudochenkov/sshpass/sshpass

# SSH 连接
sshpass -p '<密码>' ssh -o StrictHostKeyChecking=no <用户名>@<NAS_IP> "命令"

# SCP 上传文件
sshpass -p '<密码>' scp -o StrictHostKeyChecking=no <本地文件> <用户名>@<NAS_IP>:<远程路径>
```

## SSH 已知行为

- 登录时可能出现 `Could not chdir to home directory /home/<用户名>: No such file or directory` 警告，不影响命令执行
- Docker 命令需要 sudo 权限：`echo '<密码>' | sudo -S docker <命令>`
- SSH 连接偶尔被拒绝（Permission denied），重试即可

## SSH vs 浏览器 UI 选择策略

| 操作类型 | 推荐方式 | 原因 |
|---------|---------|------|
| 查看容器列表/状态 | SSH (`docker ps`) | 快速、信息完整 |
| 停止/删除容器 | 浏览器 UI 或 SSH | 均可 |
| 创建 Compose 项目 | 浏览器 UI | fnOS Compose 管理界面更直观 |
| 创建/编辑配置文件 | SSH + SCP | 浏览器文本框输入大文件极低效 |
| 上传文件到 NAS | SSH + SCP | 唯一可行方式 |
| 下载文件到 NAS | SSH + curl/wget | 在 NAS 上直接下载 |
| 查看容器日志 | SSH (`docker logs`) | 快速、完整 |

## 通过 SSH 重新部署 Compose 项目

当修改了 docker-compose.yml 后，需要重新创建容器：

```bash
# 删除旧容器后重新部署（避免名称冲突）
sshpass -p '<密码>' ssh <用户名>@<NAS_IP> \
  "echo '<密码>' | sudo -S docker rm -f <容器名> && \
   cd <compose文件目录> && \
   echo '<密码>' | sudo -S docker compose up -d"
```

## 相关笔记

- [[浏览器操作fnOS]]
- [[Docker-Compose管理]]
- [[mihomo部署与排障]]