#!/usr/bin/env bash
# Универсальный бутстрап окружения для UNIX-подобных ОС (macOS / Linux).
#
# Использование:
#   ./setup.sh              — TUI-диалог выбора пакетов, затем установка
#   ./setup.sh --all        — установить всё без диалога выбора
#   ./setup.sh -y           — то же самое, короткая форма
#   ./setup.sh --list       — список всех программ с описанием, языком,
#                             поддерживаемой ОС и ссылкой на первоисточник,
#                             ничего не ставить
#
# Диалог — синий чекбокс-список (ncurses dialog, как в debconf/Clonezilla/
# установщике Ubuntu Server): стрелки — перемещение, Пробел — отметить/
# снять пункт, Enter — установить отмеченное, Esc/Cancel — отмена.
#
# Устанавливает (через диалог выбора — можно снять любой пункт, кроме
# базовых предпосылок): oh-my-zsh (+ плагины zsh-autosuggestions,
# zsh-syntax-highlighting), oh-my-tmux, tpm (+ плагины tmux-sensible,
# tmux-resurrect, tmux-continuum, tmux-yank, tmux-thumbs, tmux-fzf,
# tmux-fzf-url, catppuccin-tmux, tmux-sessionx, tmux-floax), git, ssh, stow,
# mc, vifm, nvim, htop, pass, gpg, eza; alacritty-theme (набор тем для
# alacritty — сам терминал сюда не входит, см. ниже);
# шрифты Hack/0xProto/JetBrainsMono Nerd Font; rust, uv, Oh My Posh (движок
# темы шелла, ohmyposh.dev — TUI-мастер настройки omp-manager сюда не
# входит, см. ниже).
# Терминал alacritty, TUI-мастер omp-manager и Neovim IDE-ядро
# (AstroNvim/NvChad/LunarVim) сюда не входят — опционально через
# `./tools-extra.sh alacritty` / `./tools-extra.sh omp-manager` /
# `./tools-extra.sh ide` (диалог выбора).
# zsh становится оболочкой по умолчанию (chsh), если выбран этот пункт.
# На Linux дополнительно ставит flatpak + репозиторий flathub, на macOS — Homebrew
# (это всегда, до диалога выбора — без них не работает ничего остального).
# Без TTY (например, запуск из другого скрипта) диалог пропускается, ставится всё.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/packages.sh"
source "$SCRIPT_DIR/lib/tui_select.sh"

# Шаги, которые можно выбрать через TUI. ensure_prereqs сюда не входит —
# он обязателен (Homebrew/flatpak, curl, git), без него не работает ничего
# из списка ниже.
OPTIONAL_STEP_NAMES=(
    install_core_packages
    set_default_shell_zsh
    install_rust
    install_uv
    install_oh_my_posh
    install_fonts
    install_oh_my_zsh
    install_oh_my_zsh_plugins
    install_oh_my_tmux
    install_tpm
    install_tmux_plugins
    install_alacritty_theme
)
OPTIONAL_STEP_DESCS=(
    "Базовые пакеты: git, ssh, stow, mc, vifm, htop, nvim, tmux, zsh, pass, gnupg, eza, wireguard-tools"
    "zsh — оболочка по умолчанию (chsh)"
    "Rust (rustup)"
    "uv — менеджер Python-пакетов/окружений"
    "Oh My Posh — движок темы шелла (ohmyposh.dev); TUI-мастер настройки — ./tools-extra.sh omp-manager"
    "Nerd Fonts: Hack, 0xProto, JetBrainsMono"
    "oh-my-zsh"
    "Плагины oh-my-zsh: zsh-autosuggestions, zsh-syntax-highlighting"
    "oh-my-tmux"
    "tpm — менеджер плагинов tmux"
    "Плагины tmux: sensible, resurrect, continuum, yank, thumbs, fzf, fzf-url, catppuccin, sessionx, floax"
    "Темы alacritty (сам терминал — ./tools-extra.sh alacritty)"
)

# cmd_install <install_all: 0|1>
cmd_install() {
    local install_all="$1"
    detect_os
    step "ensure_prereqs" ensure_prereqs

    local selected=("${OPTIONAL_STEP_NAMES[@]}")
    if [[ "$install_all" != "1" ]]; then
        if [[ -t 0 && -t 1 ]]; then
            local items=() i
            for ((i = 0; i < ${#OPTIONAL_STEP_NAMES[@]}; i++)); do
                items+=("${OPTIONAL_STEP_NAMES[i]}" "${OPTIONAL_STEP_DESCS[i]}")
            done
            if tui_checklist "Выберите, что установить (setup.sh):" "${items[@]}"; then
                selected=("${TUI_SELECTED[@]}")
            else
                info "Отменено, ничего (кроме базовых предпосылок) не устанавливаю."
                exit 0
            fi
        else
            warn "Нет TTY — диалог выбора пропущен, ставлю всё (используйте --all, чтобы убрать это предупреждение)"
        fi
    fi

    if [[ ${#selected[@]} -eq 0 ]]; then
        warn "Ничего не выбрано, установка пакетов пропущена."
    fi

    local name
    for name in "${selected[@]}"; do
        step "$name" "$name"
    done

    echo
    ok "Готово."
    if [[ ${#FAILED_STEPS[@]} -gt 0 ]]; then
        warn "Эти шаги упали с ошибкой (см. вывод выше), остальное всё равно доставилось:"
        printf '    - %s\n' "${FAILED_STEPS[@]}"
    fi
    if [[ ${#MANUAL_TODO[@]} -gt 0 ]]; then
        warn "Не удалось поставить автоматически, сделайте вручную:"
        local item
        for item in "${MANUAL_TODO[@]}"; do
            printf '    - %s\n' "$item"
        done
    fi
    info "Перезапустите терминал (или выполните: exec zsh), чтобы подхватить zsh/tmux."
    info "Терминал alacritty (тема alacritty-theme уже поставлена выше) — по выбору: ./tools-extra.sh alacritty"
    info "omp-manager (TUI-мастер настройки Oh My Posh: темы, шрифты, шеллы) — по выбору: ./tools-extra.sh omp-manager"
    info "Neovim IDE (AstroNvim/NvChad/LunarVim) поставится по выбору: ./tools-extra.sh ide"
}

# cmd_list — `./setup.sh --list`: все программы, которые ставит setup.sh,
# сгруппированные так же, как в PACKAGES.md, с описанием, языком реализации
# и ссылкой на первоисточник (git-репозиторий, а если его нет — сайт
# разработчика). Ничего не устанавливает.
cmd_list() {
    local group name
    for group in "${CORE_GROUP_NAMES[@]}"; do
        printf '\n== %s ==\n' "$group"
        for name in $(core_group_members "$group"); do
            printf '  %s\n' "$name"
            printf '      %s\n' "$(core_pkg_desc "$name")"
            printf '      Язык:          %s\n' "$(core_pkg_lang "$name")"
            printf '      ОС:            %s\n' "$(core_pkg_os "$name")"
            printf '      Первоисточник: %s\n' "$(core_pkg_url "$name")"
        done
    done
    echo
    info "Дополнительные инструменты (не входят в setup.sh): ./tools-extra.sh --list"
}

CMD="install"
INSTALL_ALL=0
for arg in "$@"; do
    case "$arg" in
        --all|-y) INSTALL_ALL=1 ;;
        install) CMD="install" ;;
        --list) CMD="list" ;;
        -h|--help|help) CMD="help" ;;
        *) err "Неизвестный аргумент: $arg (доступно: install, --all/-y, --list, help)"; exit 1 ;;
    esac
done

case "$CMD" in
    install) cmd_install "$INSTALL_ALL" ;;
    list) cmd_list ;;
    help) sed -n '2,33p' "$0" ;;
esac
