#!/usr/bin/env bash
# Устанавливает семейство tui-tools (https://github.com/tui-tools) — TUI для
# администрирования Linux-сервера: firewall, systemd, снапшоты, сеть, аудит
# защищённости, пользователи, обновления, диски, ssh, логи, cron, сертификаты,
# контейнеры, samba. Каждый инструмент показывает точную команду ПЕРЕД тем,
# как её выполнить (preview-confirm-run) — сама установка ничего в системе не
# меняет, но после установки внимательно читайте, что предлагает выполнить
# каждый инструмент, особенно tui-firewall/tui-users/tui-cron/tui-secure —
# они умеют менять firewall, пользователей и cron.
#
# Использование:
#   ./tui-tools.sh                 — поставить все 14 инструментов
#   ./tui-tools.sh firewall users  — поставить только перечисленные (имя без "tui-")
#   ./tui-tools.sh --list          — показать список с описаниями, ничего не ставить
#
# Только Linux (проект целится в Linux-серверы, macOS-сборок не публикует).
# Ставит статические бинарники со страницы Releases каждого репозитория
# (раздел README "Any distribution, static binary") с проверкой sha256 по
# checksums.txt из того же релиза — работает одинаково на apt/dnf/pacman/
# zypper/apk, но в отличие от подключения репозитория tui.tools (см. README
# каждого инструмента) не даёт автообновлений вместе с системой.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

GH_OWNER="tui-tools"
TUI_NAMES=(firewall systemd snapper network secure users update disk ssh logs cron cert containers samba)

# Не используем ассоциативные массивы (declare -A) — их нет в bash 3.2,
# который на macOS до сих пор /bin/bash по умолчанию (сюда мы не должны
# дойти, macOS вообще не поддерживается этим скриптом, но парситься и
# падать с понятным сообщением скрипт обязан на любой версии bash).
tui_desc() {
    case "$1" in
        firewall)   echo "ufw/firewalld/nftables — предпросмотр каждой команды перед выполнением" ;;
        systemd)    echo "Юниты systemd: что упало и почему, действия с предпросмотром" ;;
        snapper)    echo "Снапшоты Btrfs/LVM через snapper" ;;
        network)    echo "Сетевые интерфейсы, маршруты, соединения" ;;
        secure)     echo "Аудит защищённости сервера" ;;
        users)      echo "Пользователи и группы" ;;
        update)     echo "Обновления пакетов" ;;
        disk)       echo "Диски и точки монтирования" ;;
        ssh)        echo "Конфигурация и активные сессии SSH" ;;
        logs)       echo "Системные логи (journald и файлы)" ;;
        cron)       echo "Задания cron и systemd-таймеры" ;;
        cert)       echo "TLS-сертификаты" ;;
        containers) echo "Контейнеры Docker/Podman" ;;
        samba)      echo "Шары, учётки и live-подключения Samba" ;;
        *)          return 1 ;;
    esac
}

usage() {
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

list_tools() {
    local n
    for n in "${TUI_NAMES[@]}"; do
        printf '  %-12s %s\n' "tui-$n" "$(tui_desc "$n")"
    done
}

# install_tui_tool <name-без-tui->
install_tui_tool() {
    local name="$1" bin="tui-$1" repo="tui-$1"
    if command -v "$bin" >/dev/null 2>&1; then
        ok "$bin уже установлен"
        return 0
    fi

    local arch
    case "$(uname -m)" in
        x86_64|amd64) arch=amd64 ;;
        aarch64|arm64) arch=arm64 ;;
        *) warn "$bin: неизвестная архитектура $(uname -m), пропускаю"
           MANUAL_TODO+=("$bin -> https://github.com/$GH_OWNER/$repo/releases")
           return 1 ;;
    esac

    info "Ставлю $bin..."
    local api_url="https://api.github.com/repos/$GH_OWNER/$repo/releases/latest"
    local tag
    tag="$(curl -fsSL "$api_url" 2>/dev/null | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -1)"
    if [[ -z "$tag" ]]; then
        warn "$bin: не удалось узнать версию последнего релиза"
        MANUAL_TODO+=("$bin -> https://github.com/$GH_OWNER/$repo/releases")
        return 1
    fi

    local base_url="https://github.com/$GH_OWNER/$repo/releases/download/v$tag"
    local asset="${repo}_${tag}_linux_${arch}.tar.gz"
    local tmp; tmp="$(mktemp -d)"

    if ! curl -fsSL -o "$tmp/checksums.txt" "$base_url/checksums.txt"; then
        warn "$bin: не удалось скачать checksums.txt"
        rm -rf "$tmp"; MANUAL_TODO+=("$bin -> $base_url"); return 1
    fi
    if ! curl -fsSL -o "$tmp/$asset" "$base_url/$asset"; then
        warn "$bin: не удалось скачать $asset"
        rm -rf "$tmp"; MANUAL_TODO+=("$bin -> $base_url"); return 1
    fi
    if ! (cd "$tmp" && awk -v f="$asset" '$2 == f' checksums.txt | sha256sum -c - >/dev/null 2>&1); then
        warn "$bin: контрольная сумма не совпала, НЕ устанавливаю"
        rm -rf "$tmp"; MANUAL_TODO+=("$bin: проверьте вручную -> $base_url"); return 1
    fi

    tar -xzf "$tmp/$asset" -C "$tmp" "$bin"
    $SUDO install -m0755 "$tmp/$bin" "/usr/local/bin/$bin"
    rm -rf "$tmp"

    if command -v "$bin" >/dev/null 2>&1; then
        ok "$bin установлен (v$tag)"
    else
        MANUAL_TODO+=("$bin -> $base_url")
    fi
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    --list) list_tools; exit 0 ;;
esac

detect_os
if [[ "$OS" != "linux" ]]; then
    err "tui-tools — инструменты для администрирования Linux-сервера (ufw/firewalld/systemd/samba и т.п.), на macOS их нет."
    err "Смотрите https://github.com/tui-tools — сборок под macOS проект не публикует."
    exit 1
fi

command -v curl >/dev/null 2>&1 || { err "Нужен curl"; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { err "Нужен sha256sum"; exit 1; }
command -v tar >/dev/null 2>&1 || { err "Нужен tar"; exit 1; }

TARGETS=("$@")
if [[ ${#TARGETS[@]} -eq 0 ]]; then
    TARGETS=("${TUI_NAMES[@]}")
fi

warn "tui-tools может менять firewall/пользователей/cron на этой машине — сами"
warn "инструменты просят подтверждения перед каждым изменением, но проверяйте"
warn "предложенную команду, прежде чем соглашаться."
echo

for t in "${TARGETS[@]}"; do
    if ! tui_desc "$t" >/dev/null 2>&1; then
        err "Неизвестный инструмент: tui-$t (доступные: ${TUI_NAMES[*]})"
        exit 1
    fi
done

for t in "${TARGETS[@]}"; do
    step "install_tui_tool($t)" install_tui_tool "$t"
done

echo
if [[ ${#FAILED_STEPS[@]} -gt 0 ]]; then
    warn "Не удалось поставить:"
    printf '    - %s\n' "${FAILED_STEPS[@]}"
fi
if [[ ${#MANUAL_TODO[@]} -gt 0 ]]; then
    warn "Сделайте вручную:"
    printf '    - %s\n' "${MANUAL_TODO[@]}"
fi
ok "Готово."
