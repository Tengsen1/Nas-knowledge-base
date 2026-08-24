---
title: QQ 机器人通知与订阅
category: 影视自动化
subcategory: MoviePilot
tags:
  - MoviePilot
  - QQ
  - 机器人
  - 通知
created: 2026-08-24
updated: 2026-08-24
AIGC:
  ContentProducer: '001191110102MAD55U9H0F10002'
  ContentPropagator: '001191110102MAD55U9H0F10002'
  Label: '1'
  ProduceID: '6cce5e0a-d514-490e-8696-0ea29c4c7cf6'
  PropagateID: '6cce5e0a-d514-490e-8696-0ea29c4c7cf6'
  ReservedCode1: '9556279e-7264-4591-aaa1-87610e7d4bb5'
  ReservedCode2: '9556279e-7264-4591-aaa1-87610e7d4bb5'
---

# QQ 机器人通知与订阅

MoviePilot v3 原生支持 QQ 开放平台官方 Bot API，**无需 NapCat 或 OneBot 中间件**。接入后可实现：订阅命中 → QQ 推送通知 → 用户回复确认下载 → 下载完成通知 → 自动转存 115。

## 架构说明

- **QQ Bot 模块代码**：容器内 `/app/app/modules/qqbot/`
- **双向通道**：
  - **主动推送**：通过 QQ 开放平台 API（`https://api.sgroup.qq.com`）发送消息
  - **被动接收**：通过 Gateway WebSocket 接收用户消息
- **通知配置存储**：MoviePilot 数据库 `systemconfig` 表的 `Notifications` 键
- **Gateway WebSocket**：每 30 分钟 session 超时后自动重连

## QQ 开放平台注册

1. 访问 QQ 开放平台 `https://q.qq.com`，注册机器人应用
2. 获取 **AppID** 和 **AppSecret**
3. 配置机器人能力（C2C 私聊消息收发）
4. **必须在开放平台完成发布上线**，否则用户在 QQ 中搜不到机器人

## MoviePilot 中配置 QQ 通知

1. MoviePilot Web UI → 设置 → 通知
2. 新增通知渠道，类型选择 QQ
3. 填写 QQ 开放平台的 AppID 和 AppSecret
4. 填写接收通知的用户 OpenID（用户需先向机器人发一条消息触发 OpenID 上报）
5. 开启通知事件（资源下载、整理入库、订阅等）
6. 保存并测试

## QQ 消息发送机制

| 消息类型 | 限制 | 说明 |
|---------|------|------|
| 主动消息 | 每天 1000 条/用户 | 无需用户先发消息，可直接推送 |
| 被动消息 | 用户发消息后 60 分钟内可回复 4 次 | 需递增 `msg_seq` 参数 |

> 主动消息每天 1000 条/用户的配额完全够用。

## MoviePilot 内置 QQ 聊天订阅

> **MoviePilot 已内置 QQ 聊天订阅功能**，直接在 QQ 中向机器人发送指令即可触发订阅。

| 指令 | 说明 |
|------|------|
| `订阅 片名` | 添加订阅 |
| `搜索 片名` | 搜索资源 |
| `洗版 片名` | 添加洗版订阅 |
| `/subscribes` | 查看已有订阅 |

- AI Agent 未启用时走传统媒体交互流程
- 推送提示文案应引导用户使用"订阅 片名"格式

## AUTO_DOWNLOAD_USER 配置

通过 MoviePilot API 设置 QQ 搜索后自动下载：

```bash
curl -X POST "http://<NAS_IP>:13001/api/v1/system/env?token=<API_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"key": "AUTO_DOWNLOAD_USER", "value": "all"}'
```

> **MoviePilot API 鉴权方式**：token 作为 query parameter（`?token=xxx`），不是 Bearer header。

## 通过容器内 Python 发送 QQ 消息（调试用）

```bash
echo '<sudo密码>' | sudo -S docker exec moviepilot-v3 python3 -c "
from app.modules.qqbot.api import QQBotApi
api = QQBotApi(app_id='<AppID>', app_secret='<AppSecret>')
token = api.get_access_token()
api.send_proactive_c2c_message(
    access_token=token,
    openid='<用户OpenID>',
    content='测试消息',
    msg_id=None
)
"
```

## 自动发现热点资源

| 方式 | 说明 | 适用场景 |
|------|------|----------|
| 订阅（Subscribe） | 添加关键词/类型规则，站点发布即自动搜索下载 | 追剧、追特定类型 |
| TMDB 推荐 | 首页"热门/即将上映"一键订阅 | 发现新片 |
| 豆瓣榜单 | 同步豆瓣想看/在看榜单为订阅 | 跟踪热门 |
| 站点排行榜 | 浏览各 PT 站点热门资源并一键下载 | 抢首发做种 |

## 相关笔记

- [[MoviePilot部署与认证]]
- [[PT站点保号策略]]