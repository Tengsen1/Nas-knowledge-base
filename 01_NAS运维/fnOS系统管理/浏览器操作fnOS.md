---
title: 浏览器操作 fnOS Web UI
category: NAS运维
subcategory: fnOS系统管理
tags:
  - fnOS
  - 浏览器
  - Playwright
created: 2026-08-24
updated: 2026-08-24
AIGC:
  ContentProducer: '001191110102MAD55U9H0F10002'
  ContentPropagator: '001191110102MAD55U9H0F10002'
  Label: '1'
  ProduceID: 'e1754631-ae7a-4356-9739-3ad390a385d5'
  PropagateID: 'e1754631-ae7a-4356-9739-3ad390a385d5'
  ReservedCode1: '0e2ae9fb-4872-4f13-a110-55bab21677c9'
  ReservedCode2: '0e2ae9fb-4872-4f13-a110-55bab21677c9'
---

# 浏览器操作 fnOS Web UI

## 登录流程

1. 导航到 `http://<NAS_IP>:5666`
2. 填写用户名和密码文本框
3. 点击"登录"按钮
4. 登录后进入桌面，可见应用图标（文件管理、Docker、1Panel 等）

## 关键陷阱：iframe 嵌套

> **fnOS 的 Docker 管理界面内嵌在 iframe 中**，iframe URL 格式为 `http://<NAS_IP>:5666/apps/docker/compose`（或 `/containers`、`/images` 等）。

- Playwright 快照中的元素 ref 以 `f1e` 开头时，操作需通过 iframe 定位
- 点击操作示例：`page.locator('iframe').contentFrame().getByRole('button', { name: '容器' }).click()`
- 如果直接用页面级 ref 点击会报 "Ref not found"

## 关键陷阱：页面导航后需重新登录

- 导航到 `http://<NAS_IP>:5666/` 或刷新页面后，可能跳回登录页
- 需要重新填写凭据并登录
- **建议**：操作中途避免不必要的页面导航；如需导航，做好重新登录的准备

## 关键陷阱：元素 ref 快速失效

- fnOS 路径选择对话框等弹出层中的元素 ref 极易失效
- **对策**：每次点击弹出层元素前，先调用 `playwright_browser_snapshot` 获取最新 ref，再立即点击
- 不要依赖上一次快照的 ref 来操作弹出层

## 远程访问入口

- 通过 fnOS DDNS 域名访问（如 `https://<用户名>.fnos.net/`）
- 需在 fnOS 系统设置中提前开启远程访问并绑定域名
- Playwright 浏览器可正常操作，登录流程与本地访问一致
- 登录后桌面可见应用图标，操作方式与本地完全相同

## 通过 Docker Web UI 进入容器终端

> **当 SSH 不可用时，可通过 fnOS Docker 管理界面进入容器终端执行命令，等效于 `docker exec -it <容器> /bin/bash`。**

操作路径：桌面 → Docker → 容器列表 → 目标容器 → 更多 → 终端 → /bin/bash → 连接

- 适用于需要在容器内执行命令但无法 SSH 的场景
- 可执行任意容器内命令（安装软件、编辑文件、运行脚本等）
- **注意**：终端中无法直接使用 SCP 上传文件，需通过文件管理器或其他方式

## FN Connect 隧道限制

> **fnOS 快捷访问（FN Connect）的远程隧道需要浏览器会话/cookie 才能穿透，curl 直接访问返回 403。**

- `curl` 请求 FN Connect 隧道地址返回 `403 "FN Connect 暂无权限访问该服务"`
- 浏览器中有 fnOS 登录会话，可正常访问隧道内的服务（如 qBittorrent WebUI）
- **不要用 curl 测试 FN Connect 隧道服务的连通性**，应通过浏览器验证
- qBittorrent WebUI 通过 FN Connect 打开时显示 "Unauthorized" 是**登录认证页面**，不是错误，输入凭据即可进入

## fnOS 远程访问已知限制

| 限制 | 说明 |
|------|------|
| 无系统级定时任务 | fnOS 系统设置中没有 cron/计划任务功能，定时任务需在容器内配置 |
| 1Panel 远程不可访问 | 1Panel 仅限内网访问，远程无法使用 |
| 文件管理无法浏览系统根目录 | 管理员视角的文件管理无法浏览 `/` 系统根目录，只能操作挂载的磁盘卷 |

## 相关笔记

- [[SSH操作NAS]]
- [[Docker-Compose管理]]