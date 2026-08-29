#!/bin/bash
# sync-skills-to-obsidian.sh
# 将 TeleAgent 技能文件同步到 Obsidian 知识库
# 用法: bash sync-skills-to-obsidian.sh

set -euo pipefail

# ===== 路径配置 =====
SKILLS_DIR="$HOME/.config/TeleAgent/skills"
VAULT_DIR="$HOME/Documents/TeleAgent/我的知识库"

# ===== 技能 → Vault 目录映射 =====
# 格式: "技能文件夹名|Vault中的子目录路径|笔记标题前缀"
declare -a MAPPINGS=(
  "fnos-nas-management|01_NAS运维/fnOS系统管理|fnOS"
  "moviepilot-deployment|02_影视自动化|MoviePilot"
)

# ===== 颜色输出 =====
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN} TeleAgent 技能 → Obsidian 知识库同步 ${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""

# 检查技能目录是否存在
if [ ! -d "$SKILLS_DIR" ]; then
  echo -e "${RED}错误: 技能目录不存在: $SKILLS_DIR${NC}"
  exit 1
fi

# 检查 Vault 目录是否存在
if [ ! -d "$VAULT_DIR" ]; then
  echo -e "${RED}错误: Vault 目录不存在: $VAULT_DIR${NC}"
  exit 1
fi

synced_count=0
skipped_count=0

for mapping in "${MAPPINGS[@]}"; do
  IFS='|' read -r skill_name target_dir title_prefix <<< "$mapping"
  
  skill_path="$SKILLS_DIR/$skill_name"
  skill_file="$skill_path/SKILL.md"
  
  echo -e "${YELLOW}处理技能: $skill_name${NC}"
  
  # 检查技能文件是否存在
  if [ ! -f "$skill_file" ]; then
    echo -e "  ${RED}跳过: SKILL.md 不存在${NC}"
    skipped_count=$((skipped_count + 1))
    continue
  fi
  
  # 检查是否有 templates 和 references 子目录
  target_path="$VAULT_DIR/$target_dir"
  mkdir -p "$target_path"
  
  # 复制 SKILL.md 作为完整参考文档
  cp "$skill_file" "$target_path/_原始技能文档.md"
  echo -e "  ${GREEN}已同步 SKILL.md → _原始技能文档.md${NC}"
  
  # 同步 templates 目录（如果存在）
  if [ -d "$skill_path/templates" ]; then
    mkdir -p "$target_path/templates"
    cp -r "$skill_path/templates/"* "$target_path/templates/" 2>/dev/null || true
    echo -e "  ${GREEN}已同步 templates/ 目录${NC}"
  fi
  
  # 同步 references 目录（如果存在）
  if [ -d "$skill_path/references" ]; then
    mkdir -p "$target_path/references"
    cp -r "$skill_path/references/"* "$target_path/references/" 2>/dev/null || true
    echo -e "  ${GREEN}已同步 references/ 目录${NC}"
  fi
  
  # 检查是否有新增的文件需要同步
  for extra_file in "$skill_path"/*.md; do
    [ -f "$extra_file" ] || continue
    filename=$(basename "$extra_file")
    [ "$filename" = "SKILL.md" ] && continue
    cp "$extra_file" "$target_path/$filename"
    echo -e "  ${GREEN}已同步额外文件: $filename${NC}"
  done
  
  synced_count=$((synced_count + 1))
  echo ""
done

echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN} 同步完成${NC}"
echo -e "  已同步: ${synced_count} 个技能"
echo -e "  已跳过: ${skipped_count} 个技能"
echo -e "${GREEN}════════════════════════════════════════${NC}"

# 如果 Vault 是 Git 仓库，提示可以提交
if [ -d "$VAULT_DIR/.git" ]; then
  echo ""
  echo -e "${YELLOW}提示: Vault 已初始化 Git，可执行以下命令提交变更:${NC}"
  echo "  cd \"$VAULT_DIR\""
  echo "  git add -A && git commit -m \"sync: $(date '+%Y-%m-%d %H:%M') 技能同步\" && git push"
fi
