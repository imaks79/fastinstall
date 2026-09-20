#!/usr/bin/env bash
# Универсальный бутстрап окружения для UNIX-подобных ОС (macOS / Linux).
#
# Использование:
#   ./setup.sh              — установить пакеты
#
# Устанавливает: oh-my-zsh (+ плагины zsh-autosuggestions,
# zsh-syntax-highlighting), oh-my-tmux, git, ssh, stow, mc, alacritty, nvim,
# htop, pass, gpg, eza;
# шрифты Hack/0xProto/JetBrainsMono Nerd Font; rust, uv, omp-manager.
# Neovim IDE-ядро (AstroNvim/NvChad/LunarVim) сюда не входит — опционально
# через `./tools-extra.sh ide` (диалог выбора).
# zsh становится оболочкой по умолчанию (chsh).
# На Linux дополнительно ставит flatpak + репозиторий flathub, на macOS — Homebrew.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/packages.sh"

cmd_install() {
    detect_os
    step "ensure_prereqs"          ensure_prereqs
    step "install_core_packages"   install_core_packages
    step "set_default_shell_zsh"   set_default_shell_zsh
    step "install_terminal"        install_terminal
    step "install_rust"            install_rust
    step "install_uv"              install_uv
    step "install_omp_manager"     install_omp_manager
    step "install_fonts"           install_fonts
    step "install_oh_my_zsh"       install_oh_my_zsh
    step "install_oh_my_zsh_plugins" install_oh_my_zsh_plugins
    step "install_oh_my_tmux"      install_oh_my_tmux
    step "install_alacritty_theme" install_alacritty_theme

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
    info "Neovim IDE (AstroNvim/NvChad/LunarVim) поставится по выбору: ./tools-extra.sh ide"
    print_astra
}

case "${1:-install}" in
    install) cmd_install ;;
    -h|--help|help)
        sed -n '2,10p' "$0"
        ;;
    *)
        err "Неизвестная команда: $1 (доступно: install, help)"
        exit 1
        ;;
esac
