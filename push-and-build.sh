#!/usr/bin/env bash
#
# push-and-build.sh — 一键把本工程推到 GitHub 并触发云端编译
#
# 用法（在 Git Bash / macOS / Linux 下）：
#   GITHUB_TOKEN=ghp_xxxx ./push-and-build.sh [仓库名] [public|private]
#
# 例：
#   GITHUB_TOKEN=ghp_xxxx ./push-and-build.sh saqiang-wcassets public
#
# 说明：
#   - token 只在本脚本运行时通过环境变量使用，不会被写进 git 配置或仓库。
#   - 需要 token 具备 repo（建仓 + 推送）和 workflow 权限。
#   - 若仓库已存在会直接复用；不存在则自动创建。
#   - 推送后轮询 Actions，打印每次运行的结论。
#

set -euo pipefail

REPO_NAME="${1:-saqiang-wcassets}"
VISIBILITY="${2:-public}"
TOKEN="${GITHUB_TOKEN:-}"

if [ -z "$TOKEN" ]; then
  echo "错误：请先设置 GITHUB_TOKEN 环境变量" >&2
  echo "  GITHUB_TOKEN=ghp_xxxx $0 $REPO_NAME $VISIBILITY" >&2
  exit 1
fi

case "$VISIBILITY" in
  public)  PRIVATE=false ;;
  private) PRIVATE=true ;;
  *) echo "错误：可见性只能是 public 或 private" >&2; exit 1 ;;
esac

API="https://api.github.com"
AUTH=(-H "Authorization: Bearer ${TOKEN}" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")

echo "==> 确认 GitHub 账号"
USER_JSON=$(curl -fsS "${AUTH[@]}" "$API/user")
OWNER=$(python -c 'import sys,json; print(json.load(sys.stdin)["login"])' <<<"$USER_JSON")
echo "    账号：$OWNER"

REPO_URL="$API/repos/$OWNER/$REPO_NAME"
if curl -fsS "${AUTH[@]}" "$REPO_URL" >/dev/null 2>&1; then
  echo "==> 仓库 $OWNER/$REPO_NAME 已存在，直接复用"
else
  echo "==> 创建仓库 $OWNER/$REPO_NAME ($VISIBILITY)"
  curl -fsS "${AUTH[@]}" -X POST "$API/user/repos" \
    -d "{\"name\":\"$REPO_NAME\",\"private\":$PRIVATE,\"description\":\"SaoqiangWCAssets rebuilt tweak\"}" \
    >/dev/null
fi

echo "==> 配置 remote 并推送"
git -C "$(dirname "$0")" remote remove origin 2>/dev/null || true
git -C "$(dirname "$0")" remote add origin "https://github.com/$OWNER/$REPO_NAME.git"
git -C "$(dirname "$0")" branch -M main
# 用 extraHeader 传 token，避免把凭据写进 .git/config
git -C "$(dirname "$0")" -c http.extraHeader="AUTHORIZATION: bearer ${TOKEN}" push -u origin main

echo "==> 推送完成，等待 Actions 启动..."
sleep 8

RUNS_URL="$REPO_URL/actions/runs?per_page=1"
RUN_JSON=$(curl -fsS "${AUTH[@]}" "$RUNS_URL")
COUNT=$(python -c 'import sys,json; print(json.load(sys.stdin).get("total_count",0))' <<<"$RUN_JSON")
if [ "$COUNT" -eq 0 ]; then
  echo "    还没检测到运行记录，请到 Actions 页手动点 Run workflow"
  echo "    https://github.com/$OWNER/$REPO_NAME/actions"
  exit 0
fi

RUN_ID=$(python -c 'import sys,json; print(json.load(sys.stdin)["workflow_runs"][0]["id"])' <<<"$RUN_JSON")
echo "    运行 ID：$RUN_ID"

for i in $(seq 1 40); do
  STATUS_JSON=$(curl -fsS "${AUTH[@]}" "$REPO_URL/actions/runs/$RUN_ID")
  STATUS=$(python -c 'import sys,json; print(json.load(sys.stdin).get("status",""))' <<<"$STATUS_JSON")
  CONCLUSION=$(python -c 'import sys,json; print(json.load(sys.stdin).get("conclusion") or "")' <<<"$STATUS_JSON")
  if [ "$STATUS" = "completed" ]; then
    echo "==> 编译结束：${CONCLUSION:-unknown}"
    echo "    详情：https://github.com/$OWNER/$REPO_NAME/actions/runs/$RUN_ID"
    if [ "$CONCLUSION" = "success" ]; then
      echo "    下载产物：打开上面链接 → 页面底部 Artifacts → SaoqiangWCAssets-build"
    fi
    exit 0
  fi
  echo "    [$i/40] 状态：$STATUS ..."
  sleep 15
done

echo "    等待超时，请到 Actions 页查看：https://github.com/$OWNER/$REPO_NAME/actions/runs/$RUN_ID"
