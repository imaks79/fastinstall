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
#   ./tools-extra.sh                  — поставить все инструменты
#   ./tools-extra.sh bat yazi lnav     — поставить только перечисленные
#   ./tools-extra.sh --list            — список с описаниями, ничего не ставить

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/packages.sh"
source "$SCRIPT_DIR/lib/tools_extra.sh"

usage() {
    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
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

TARGETS=("$@")
if [[ ${#TARGETS[@]} -eq 0 ]]; then
    TARGETS=("${TOOLS_EXTRA_NAMES[@]}")
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
