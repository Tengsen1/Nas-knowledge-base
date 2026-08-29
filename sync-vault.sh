#!/bin/bash
# NAS 每日知识库同步脚本
# 每天 00:00 执行：拉取最新 Vault → 提交推送（如果有变更）
export HOME=/vol1/1000

VAULT_DIR=/vol1/1000/knowledge-base
LOG_FILE=$VAULT_DIR/sync.log

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始同步..." >> $LOG_FILE

cd $VAULT_DIR || exit 1

# 拉取远程最新变更
git fetch origin >> $LOG_FILE 2>&1
git pull origin main >> $LOG_FILE 2>&1

# 检查是否有变更需要提交
git add -A >> $LOG_FILE 2>&1
if git diff --cached --quiet; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] 无变更需要提交" >> $LOG_FILE
else
  git commit -m "vault backup: $(date '+%Y-%m-%d %H:%M:%S')" >> $LOG_FILE 2>&1
  git push origin main >> $LOG_FILE 2>&1
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] 已提交并推送变更" >> $LOG_FILE
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 同步完成" >> $LOG_FILE
echo "----------------------------------------" >> $LOG_FILE
