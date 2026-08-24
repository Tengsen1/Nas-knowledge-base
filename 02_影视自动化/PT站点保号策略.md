---
title: PT 站点保号策略（M-Team）
category: 影视自动化
subcategory: MoviePilot
tags:
  - MoviePilot
  - M-Team
  - PT
  - 保号
  - 做种
created: 2026-08-24
updated: 2026-08-24
AIGC:
  ContentProducer: '001191110102MAD55U9H0F10002'
  ContentPropagator: '001191110102MAD55U9H0F10002'
  Label: '1'
  ProduceID: 'f7fce91d-6659-417a-8b06-7f867adb8404'
  PropagateID: 'f7fce91d-6659-417a-8b06-7f867adb8404'
  ReservedCode1: '8d335dd8-ea6f-46b7-b8b0-ab2b3cecd5fc'
  ReservedCode2: '8d335dd8-ea6f-46b7-b8b0-ab2b3cecd5fc'
---

# PT 站点保号策略（M-Team）

## M-Team 新人考核指标

| 考核项 | 达标要求 | 说明 |
|--------|----------|------|
| 下载量 | ≥ 15 GB | 容易达成 |
| 上传量 | ≥ 30 GB | 通过做种上传积累 |
| 魔力值 | ≥ 6000 | **最难点**，靠做种时间积累 |
| 分享率 | 自注册之日起考核 | 上传量 ÷ 下载量，建议 ≥ 1.0 |

> 具体数值以站内规则页面为准，不同时期可能调整。

## 魔力值提升策略

1. **长期保种**：不要删种，QB 中保持做种状态
2. **选择冷门种子**：做种人数少的种子，魔力值产出更高
3. **不要用魔力值兑换上传量**：保留魔力值用于考核
4. **多下载并保种**：增加做种数量，但注意控制下载量
5. **选择 free/2x 促销资源**：免下载流量或双倍上传

## 关键陷阱：传输方式 move 导致做种中断

> **这是保号失败最常见的原因。** 如果 MoviePilot 整理方式设为 `move`，文件被移动到 115 网盘后本地无文件，MoviePilot 的 `_can_delete_torrent` 逻辑检测到本地文件不存在，会自动删除种子，导致无法持续做种。

**根因分析**：
- `move`：文件移动后本地消失 → `_can_delete_torrent` 判定可删种 → 种子被删除 → 做种中断
- `copy`：文件复制后本地保留 → 种子保持做种 → 魔力值持续积累

**解决方案**：将传输方式改为 `copy`，确保本地存储空间充足。

## 自动做种与批量下载

批量下载免费高做种资源用于保号的推荐流程：

1. 通过 M-Team API 搜索免费（`free`/`2X_FREE`）且做种数高的资源
2. 调用 `genDlLink` 接口获取种子直接下载 URL
3. 通过 qBittorrent `POST /api/v2/torrents/add` 的 `urls` 参数批量添加（多个 URL 换行分隔）
4. 确保 QB 做种配置已优化（不限制分享率和做种时间）
5. 确保传输方式为 `copy`，避免 MoviePilot 自动删种

> **关键陷阱**：逐个调用 `genDlLink` → 下载种子文件 → 上传到 QB 的方式非常慢。应使用 `genDlLink` 返回的直接 URL 通过 QB 的 `urls` 参数批量添加。

## RSS 自动做种方案

> **RSS 方案由 qBittorrent RSS 自动下载规则驱动，无需手动调用 API。**

**工作原理**：M-Team RSS Feed → qBittorrent RSS 自动下载规则 → 自动下载并做种

**配置步骤**：

1. **生成 RSS 链接**：通过 M-Team API（`POST https://api.m-team.cc/api/rss/genlink`）生成 RSS Feed URL
2. **启用 qBittorrent RSS**：在 QB Settings 中启用 RSS 功能
3. **添加 RSS 源**：`POST /api/v2/rss/addFeed`
4. **创建自动下载规则**：`POST /api/v2/rss/setRule`，需传 `ruleDef` JSON 参数
5. **调整并发限制**：通过 `setPreferences` 设置 max_active 等

> **RSS 下载链接有签名有效期**，过期后返回 JSON 错误。需设置 cron 定时任务（如每天凌晨 3 点）重新生成 RSS 链接并更新 QB RSS 源。

> **qBittorrent 容器可能无法解析 RSS 域名**（如 `rss.m-team.cc`）。需通过 `custom-cont-init.d` 脚本在容器启动时自动添加 hosts 记录。

## MoviePilot 辅助保号

- **不要开启"下载完即删种"**
- 设置 QB 做种限速，避免占用过多带宽
- 利用 MoviePilot 订阅功能自动下载热门资源并长期保种
- **确保传输方式为 `copy`**

## 相关笔记

- [[MoviePilot部署与认证]]
- [[下载器与存储对接]]
- [[QQ机器人通知订阅]]