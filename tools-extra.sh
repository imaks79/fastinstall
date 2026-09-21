#!/usr/bin/env bash
# Ставит набор дополнительных TUI/CLI-инструментов (не входящих в setup.sh),
# см. TOOLS-EXTRA.md с описанием каждого. macOS и Linux (apt/dnf/pacman/
# zypper/apk): сперва пробуется нативный пакетный менеджер, если пакета там
# нет — сборка через `cargo install` (rust уже должен быть, см. setup.sh) или
# бинарь с GitHub Releases (lazygit/lazydocker/k9s/fastfetch). Список сделан
# таблицей одной функции (install_tool в lib/tools_extra.sh) специально для
# дальнейшего расширения — дописать инструмент это одна строка там плюс одна
# в tool_desc() и TOOLS_EXTRA_NAMES.
#
# Использование:
#   ./tools-extra.sh                  — TUI-диалог выбора инструментов
#   ./tools-extra.sh --all            — поставить все инструменты без диалога
#   ./tools-extra.sh bat yazi lnav    — поставить только перечисленные
#   ./tools-extra.sh --list           — список с описаниями, ничего не ставить
#
# Диалог — синий чекбокс-список (ncurses dialog, как в debconf/Clonezilla/
# установщике Ubuntu Server): стрелки — перемещение, Пробел — отметить/
# снять пункт, Enter — установить отмеченное, Esc/Cancel — отмена.
# Без TTY (например, запуск из другого скрипта) диалог пропускается, ставится всё.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/packages.sh"
source "$SCRIPT_DIR/lib/tools_extra.sh"
source "$SCRIPT_DIR/lib/tui_select.sh"

usage() {
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

list_tools() {
    local n
    for n in "${TOOLS_EXTRA_NAMES[@]}"; do
        printf '  %-10s %s\n' "$n" "$(tool_desc "$n")"
    done
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    --list) list_tools; exit 0 ;;
esac

detect_os

TARGETS=()
INSTALL_ALL=0
for arg in "$@"; do
    case "$arg" in
        --all) INSTALL_ALL=1 ;;
        *) TARGETS+=("$arg") ;;
    esac
done

if [[ ${#TARGETS[@]} -eq 0 ]]; then
    if [[ "$INSTALL_ALL" == "1" ]]; then
        TARGETS=("${TOOLS_EXTRA_NAMES[@]}")
    elif [[ -t 0 && -t 1 ]]; then
        items=()
        for n in "${TOOLS_EXTRA_NAMES[@]}"; do
            items+=("$n" "$(tool_desc "$n")")
        done
        if tui_checklist "Выберите инструменты для установки (tools-extra.sh):" "${items[@]}"; then
            TARGETS=("${TUI_SELECTED[@]}")
        else
            info "Отменено, ничего не устанавливаю."
            exit 0
        fi
        if [[ ${#TARGETS[@]} -eq 0 ]]; then
            warn "Ничего не выбрано, установка пропущена."
            exit 0
        fi
    else
        warn "Нет TTY — диалог выбора пропущен, ставлю все инструменты (используйте --all, чтобы убрать это предупреждение)"
        TARGETS=("${TOOLS_EXTRA_NAMES[@]}")
    fi
fi

for t in "${TARGETS[@]}"; do
    if ! tool_desc "$t" >/dev/null 2>&1; then
        err "Неизвестный инструмент: $t (список: ./tools-extra.sh --list)"
        exit 1
    fi
done

for t in "${TARGETS[@]}"; do
    step "install_tool($t)" install_tool "$t"
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
