---
title: Docker Compose 项目管理
category: NAS运维
subcategory: fnOS系统管理
tags:
  - fnOS
  - Docker
  - Compose
created: 2026-08-24
updated: 2026-08-24
AIGC:
  ContentProducer: '001191110102MAD55U9H0F10002'
  ContentPropagator: '001191110102MAD55U9H0F10002'
  Label: '1'
  ProduceID: '4973a9af-a1ec-4297-a6d2-b8e38b96907f'
  PropagateID: '4973a9af-a1ec-4297-a6d2-b8e38b96907f'
  ReservedCode1: '16e32774-74f6-4586-a195-b2e424e9485d'
  ReservedCode2: '16e32774-74f6-4586-a195-b2e424e9485d'
---

# Docker Compose 项目管理

## 创建 Compose 项目（浏览器 UI）

1. 打开 Docker 应用 → 点击"Compose"标签
2. 点击"新增项目"
3. 填写项目名称
4. 选择来源："创建docker-compose.yml"（在线编辑）或"上传docker-compose.yml"
5. 在编辑器中填入 docker-compose.yml 内容
6. **必须选择路径**：点击路径选择图标 → 在弹出对话框中选中目标文件夹 → 点击"确认"
   - 路径选择是必填项，不选会报"请选择路径"错误
   - 路径选择对话框中元素 ref 易失效，需先 snapshot 再点击
7. 勾选"创建项目后立即启动"（可选）
8. 点击"确认"创建项目

## 关键陷阱：Compose 文件存储位置

> **飞牛的 Compose 文件存储在所选路径的根目录下，而非项目子目录中。**

例如：选择路径为 `/vol2/1000/docker`，项目名为 `mihomo`，则：
- `docker-compose.yml` 位于 `/vol2/1000/docker/docker-compose.yml`（不是 `/vol2/1000/docker/mihomo/docker-compose.yml`）
- Compose 中的相对路径 `./mihomo` 解析为 `/vol2/1000/docker/mihomo/`

## 删除 Compose 项目

1. Compose 页面 → 找到目标项目
2. 点击"更多" → "删除"
3. 确认删除

## 删除容器

1. 容器页面 → 找到目标容器
2. 先点击"停止"按钮停止容器
3. 等待容器停止（按钮变为"启动"）
4. 点击"更多" → "删除"
5. 确认删除

## 删除本地镜像

1. 本地镜像页面 → 找到目标镜像
2. 点击"更多" → "删除镜像"
3. 确认删除

## 通过 SSH 重新部署 Compose 项目

当修改了 docker-compose.yml 后，需要重新创建容器：

```bash
sshpass -p '<密码>' ssh <用户名>@<NAS_IP> \
  "echo '<密码>' | sudo -S docker rm -f <容器名> && \
   cd <compose文件目录> && \
   echo '<密码>' | sudo -S docker compose up -d"
```

## 相关笔记

- [[浏览器操作fnOS]]
- [[SSH操作NAS]]