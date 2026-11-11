#!/bin/bash
#
# TradingAgents-Astock · macOS 双击启动器
#
# 双击本文件即可：检查 Python → 建虚拟环境 → 装依赖（仅首次）→ 启动 Web UI → 自动打开浏览器。
# 也可以从终端运行：./启动.command
#
# 可选环境变量：
#   TAGENT_PYTHON        指定解释器路径（默认自动查找 Python ≥ 3.10）
#   TAGENT_PIP_INDEX     pip 镜像地址（默认清华源，官方源慢时可换）
#   TAGENT_PORT          指定端口（默认从 8501 起找空位）
#   TAGENT_SKIP_INSTALL  =1 跳过依赖安装检查（调试用）
#   TAGENT_NO_BREW       =1 禁止自动 brew install Python
#
set -uo pipefail

# ── 路径：双击时工作目录是家目录，必须按脚本自身位置定位 ──────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "$SCRIPT_DIR" || exit 1
PROJECT_DIR="$SCRIPT_DIR"
VENV_DIR="$PROJECT_DIR/.venv"
ENV_FILE="$PROJECT_DIR/.env"
APP_FILE="$PROJECT_DIR/web/app.py"
STATE_FILE="$VENV_DIR/.launcher.state"
PIP_INDEX="${TAGENT_PIP_INDEX:-https://pypi.tuna.tsinghua.edu.cn/simple}"
MIN_PY="3.10"

# Finder 双击启动时 PATH 只有 /usr/bin:/bin:/usr/sbin:/sbin，补上 Homebrew / 本地路径
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$PATH"
export PYTHONUNBUFFERED=1

printf '\033]0;%s\007' "TradingAgents A股分析"

echo "=============================================="
echo "  TradingAgents-Astock · A股多Agent投研"
echo "=============================================="
echo

# ── 小工具 ────────────────────────────────────────────────────────────────
pause_exit() {
    echo
    echo "$1"
    if [ -t 0 ]; then
        read -r -p "按回车键关闭窗口..." _
    fi
    exit 1
}

# 解释器是否满足 Python ≥ 3.10
py_ok() {
    [ -n "${1:-}" ] && [ -x "$1" ] && "$1" -c \
        "import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)" >/dev/null 2>&1
}

py_version() {
    "$1" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null
}

# 只清理「自己写下」的状态文件，避免误删另一个实例的记录
cleanup() {
    [ -f "$STATE_FILE" ] || return 0
    { read -r state_pid _; } < "$STATE_FILE" 2>/dev/null || return 0
    [ "${state_pid:-}" = "$$" ] && rm -f "$STATE_FILE" 2>/dev/null
    return 0
}
trap cleanup EXIT

# ── 1. 找 Python ≥ 3.10 ───────────────────────────────────────────────────
PYTHON=""
if [ -n "${TAGENT_PYTHON:-}" ]; then
    if py_ok "$TAGENT_PYTHON"; then
        PYTHON="$TAGENT_PYTHON"
    else
        pause_exit "❌ TAGENT_PYTHON=$TAGENT_PYTHON 不是可用的 Python ≥ ${MIN_PY}。"
    fi
fi

# 已有 .venv 且版本够用 → 直接复用（启动最快）
if [ -z "$PYTHON" ] && py_ok "$VENV_DIR/bin/python"; then
    PYTHON="$VENV_DIR/bin/python"
fi

# 系统里逐个找：优先高版本，避免踩到 macOS 自带的 3.9
if [ -z "$PYTHON" ]; then
    for cand in python3.13 python3.12 python3.11 python3.10 python3; do
        path="$(command -v "$cand" 2>/dev/null)"
        if [ -n "$path" ] && py_ok "$path"; then
            PYTHON="$path"
            break
        fi
    done
fi

# 常见 Homebrew 路径兜底（PATH 被清空时也能找到）
if [ -z "$PYTHON" ]; then
    for path in /opt/homebrew/bin/python3.13 /opt/homebrew/bin/python3.12 \
                /opt/homebrew/bin/python3.11 /opt/homebrew/bin/python3.10 \
                /usr/local/bin/python3.13 /usr/local/bin/python3.12; do
        if py_ok "$path"; then
            PYTHON="$path"
            break
        fi
    done
fi

# 实在没有 → 用 Homebrew 装（不覆盖系统 Python），或给出手动指引
if [ -z "$PYTHON" ]; then
    echo "🔍 未找到 Python ≥ ${MIN_PY}（系统自带的 3.9 太旧，项目要求 ≥ 3.10）。"
    if [ "${TAGENT_NO_BREW:-0}" != "1" ] && command -v brew >/dev/null 2>&1; then
        echo "📥 正在用 Homebrew 安装 python@3.12，首次约需 1~3 分钟，请稍候..."
        echo
        if ! brew install python@3.12; then
            pause_exit "❌ Homebrew 安装失败。请手动执行：brew install python@3.12，然后重新双击本文件。"
        fi
        echo
        for path in /opt/homebrew/bin/python3.12 /usr/local/bin/python3.12; do
            if py_ok "$path"; then
                PYTHON="$path"
                break
            fi
        done
    fi
    if [ -z "$PYTHON" ]; then
        pause_exit "❌ 需要 Python ≥ 3.10。任选其一安装后重新双击：
   • Homebrew：brew install python@3.12
   • 官网安装包：https://www.python.org/downloads/macos/"
    fi
fi

echo "🐍 Python：$(py_version "$PYTHON")  ($PYTHON)"

# ── 2. 准备虚拟环境（.venv）───────────────────────────────────────────────
# 已有的 .venv 若是旧版 Python 建的就删掉重建（venv 不能跨版本升级）
if [ -d "$VENV_DIR" ] && ! py_ok "$VENV_DIR/bin/python"; then
    if [ "$VENV_DIR" = "$PROJECT_DIR/.venv" ]; then
        echo "🧹 现有 .venv 版本不满足要求，重建中..."
        rm -rf "$VENV_DIR"
    fi
fi

if [ ! -x "$VENV_DIR/bin/python" ]; then
    echo "📦 创建虚拟环境 .venv ..."
    if ! "$PYTHON" -m venv "$VENV_DIR"; then
        pause_exit "❌ 创建虚拟环境失败，请检查磁盘空间或 Python 安装是否完整。"
    fi
fi

PY="$VENV_DIR/bin/python"
if ! py_ok "$PY"; then
    pause_exit "❌ 虚拟环境异常：$PY 不可用。可删除 .venv 后重新双击。"
fi

# ── 3. 依赖：按 pyproject.toml 指纹判断是否需要安装 ────────────────────────
if [ "${TAGENT_SKIP_INSTALL:-0}" != "1" ]; then
    STAMP="$VENV_DIR/.deps-$(shasum -a 256 "$PROJECT_DIR/pyproject.toml" 2>/dev/null | cut -c1-16)"
    need_install=0
    [ -f "$STAMP" ] || need_install=1
    if [ "$need_install" -eq 0 ]; then
        # 只查已安装的包版本，不 import：import mootdx 等会在用户主目录建配置文件，
        # 既慢又有副作用。
        if ! "$PY" -c 'import importlib.metadata as m
for pkg in ("streamlit", "langchain-core", "langgraph", "mootdx",
            "pandas", "python-dotenv", "tradingagents-astock"):
    m.version(pkg)' >/dev/null 2>&1; then
            need_install=1
        fi
    fi

    if [ "$need_install" -eq 1 ]; then
        echo
        echo "📦 正在安装依赖，首次约 3~8 分钟（下次启动秒开），请勿关闭窗口..."
        echo "   pip 源：$PIP_INDEX"
        echo
        "$PY" -m pip install --upgrade pip setuptools wheel --quiet --index-url "$PIP_INDEX" \
            || echo "⚠️  pip 自身升级失败，继续尝试安装依赖..."
        if ! "$PY" -m pip install -e "$PROJECT_DIR" --index-url "$PIP_INDEX"; then
            pause_exit "❌ 依赖安装失败（常见原因：网络、代理、镜像缺包）。
   可重试：双击本文件；或换官方源：
     TAGENT_PIP_INDEX=https://pypi.org/simple ./启动.command"
        fi
        rm -f "$VENV_DIR"/.deps-* 2>/dev/null
        touch "$STAMP"
        echo
        echo "✅ 依赖安装完成"
    fi
fi

# ── 4. 配置 .env（API Key）────────────────────────────────────────────────
if [ ! -f "$ENV_FILE" ]; then
    if [ -f "$PROJECT_DIR/.env.example" ]; then
        cp "$PROJECT_DIR/.env.example" "$ENV_FILE"
        echo "📝 已创建 .env（从 .env.example 复制）"
    fi
fi

has_key=0
if [ -f "$ENV_FILE" ]; then
    if grep -qE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*[^[:space:]]+' "$ENV_FILE"; then
        has_key=1
    fi
fi
if [ "$has_key" -eq 0 ]; then
    echo
    echo "⚠️  还没在 .env 里填任何 API Key，点「开始分析」会报鉴权错误。"
    echo "   填写方法：用文本编辑器打开 $ENV_FILE"
    echo "   填一个即可，例如 DEEPSEEK_API_KEY=sk-xxxx / MINIMAX_API_KEY=xxxx"
    echo "   （若侧栏选 Ollama 本地模型，则不需要 Key）"
    echo
fi

# ── 5. 已在运行就直接开浏览器 ─────────────────────────────────────────────
if [ -f "$STATE_FILE" ]; then
    read -r OLD_PID OLD_PORT < "$STATE_FILE" 2>/dev/null || true
    if [ -n "${OLD_PID:-}" ] && [ -n "${OLD_PORT:-}" ] && kill -0 "$OLD_PID" 2>/dev/null \
        && curl -sf -o /dev/null --max-time 2 "http://127.0.0.1:$OLD_PORT/_stcore/health"; then
        echo "✅ 检测到已在运行（端口 ${OLD_PORT}），直接打开浏览器。"
        open "http://127.0.0.1:$OLD_PORT"
        exit 0
    fi
fi

# ── 6. 选端口（8501 起找空位，多开互不冲突）────────────────────────────────
PORT="${TAGENT_PORT:-}"
if [ -z "$PORT" ]; then
    PORT="$("$PY" - <<'PYEOF'
import socket

for port in range(8501, 8541):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.bind(("127.0.0.1", port))
    except OSError:
        continue
    finally:
        s.close()
    print(port)
    break
PYEOF
)"
fi
if [ -z "$PORT" ]; then
    pause_exit "❌ 8501~8540 端口都被占用了，请先关闭占用程序再重试。"
fi

echo
echo "🚀 启动 Web UI：http://127.0.0.1:$PORT"
echo "   （浏览器会自动打开；关闭本窗口或按 Ctrl+C 即停止服务）"
echo

# ── 7. 等健康检查通过后开浏览器（避免打开过早看到报错页）──────────────────
(
    for _ in $(seq 1 120); do
        if curl -sf -o /dev/null --max-time 1 "http://127.0.0.1:$PORT/_stcore/health"; then
            open "http://127.0.0.1:$PORT"
            exit 0
        fi
        sleep 1
    done
) &
OPENER_PID=$!

printf '%s %s\n' "$$" "$PORT" > "$STATE_FILE"

"$PY" -m streamlit run "$APP_FILE" \
    --server.port="$PORT" \
    --server.address=127.0.0.1 \
    --server.headless=true \
    --browser.gatherUsageStats=false

STATUS=$?
kill "$OPENER_PID" 2>/dev/null || true
# 状态文件由 trap cleanup 统一清理（只删自己写的）

if [ "$STATUS" -ne 0 ] && [ "$STATUS" -ne 130 ]; then
    pause_exit "❌ Web 服务异常退出（退出码 ${STATUS}）。上方日志里有具体错误。"
fi
