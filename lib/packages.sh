#!/usr/bin/env bash
# Установка пакетного менеджера-прослойки и пакетов.

ensure_prereqs() {
    if [[ "$OS" == "macos" ]]; then
        if ! command -v brew >/dev/null 2>&1; then
            info "Homebrew не найден, устанавливаю..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            if [[ -x /opt/homebrew/bin/brew ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"
            elif [[ -x /usr/local/bin/brew ]]; then eval "$(/usr/local/bin/brew shellenv)"
            fi
        fi
        ok "Homebrew готов: $(brew --version | head -1)"
    else
        case "$PKG_MANAGER" in
            apt)    $SUDO apt-get update -y ;;
            zypper) $SUDO zypper --non-interactive refresh ;;
        esac
        # curl/git/ca-certificates нужны почти всем шагам ниже (клонирование
        # репозиториев, скачивание установщиков) — на минимальных образах
        # (например, "docker run ubuntu") их по умолчанию нет вообще.
        info "Базовые зависимости: curl, git, ca-certificates"
        case "$PKG_MANAGER" in
            apt)    $SUDO apt-get install -y curl git ca-certificates ;;
            dnf)    $SUDO dnf install -y curl git ca-certificates ;;
            pacman) $SUDO pacman -S --noconfirm --needed curl git ca-certificates ;;
            zypper) $SUDO zypper --non-interactive install curl git ca-certificates ;;
            apk)    $SUDO apk add curl git ca-certificates ;;
        esac
        if ! command -v flatpak >/dev/null 2>&1; then
            info "Устанавливаю flatpak..."
            case "$PKG_MANAGER" in
                apt)    $SUDO apt-get install -y flatpak ;;
                dnf)    $SUDO dnf install -y flatpak ;;
                pacman) $SUDO pacman -S --noconfirm flatpak ;;
                zypper) $SUDO zypper --non-interactive install flatpak ;;
                apk)    $SUDO apk add flatpak ;;
            esac
        fi
        if command -v flatpak >/dev/null 2>&1; then
            flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
            ok "flatpak + репозиторий flathub готовы"
        else
            warn "flatpak установить не удалось, часть пакетов может быть недоступна"
        fi
    fi
}

# pkg_native <apt> <dnf> <pacman> <zypper> <apk>
# Устанавливает пакет через нативный менеджер macOS/Linux. Пустая строка = имя недоступно/пропустить.
pkg_native() {
    local brew_name="$1" apt_name="$2" dnf_name="$3" pacman_name="$4" zypper_name="$5" apk_name="$6"
    if [[ "$OS" == "macos" ]]; then
        [[ -n "$brew_name" ]] && brew list --formula "$brew_name" >/dev/null 2>&1 && return 0
        [[ -n "$brew_name" ]] && brew install "$brew_name"
        return $?
    fi
    case "$PKG_MANAGER" in
        apt)    [[ -n "$apt_name" ]]    && $SUDO apt-get install -y "$apt_name" ;;
        dnf)    [[ -n "$dnf_name" ]]    && $SUDO dnf install -y "$dnf_name" ;;
        pacman) [[ -n "$pacman_name" ]] && $SUDO pacman -S --noconfirm --needed "$pacman_name" ;;
        zypper) [[ -n "$zypper_name" ]] && $SUDO zypper --non-interactive install "$zypper_name" ;;
        apk)    [[ -n "$apk_name" ]]    && $SUDO apk add "$apk_name" ;;
        *) return 1 ;;
    esac
}

pkg_cask() {
    local cask_name="$1" flatpak_id="$2"
    if [[ "$OS" == "macos" ]]; then
        brew list --cask "$cask_name" >/dev/null 2>&1 && return 0
        brew install --cask "$cask_name"
        return $?
    fi
    if [[ -n "$flatpak_id" ]] && command -v flatpak >/dev/null 2>&1; then
        flatpak install -y --noninteractive flathub "$flatpak_id"
        return $?
    fi
    return 1
}

install_core_packages() {
    info "Базовые пакеты: git, ssh, stow, mc, htop, nvim, tmux, zsh, eza"
    pkg_native git    git        git    git    git    git
    pkg_native ""     openssh-client openssh-clients openssh openssh openssh-client
    command -v ssh >/dev/null 2>&1 || pkg_native openssh openssh openssh openssh openssh openssh
    pkg_native stow   stow       stow   stow   stow   stow
    pkg_native mc     mc         mc     mc     mc     mc
    pkg_native htop   htop       htop   htop   htop   htop
    pkg_native neovim neovim     neovim neovim neovim neovim
    pkg_native tmux   tmux       tmux   tmux   tmux   tmux
    pkg_native zsh    zsh        zsh    zsh    zsh    zsh
    pkg_native pass   pass       pass   pass   pass   pass
    pkg_native gnupg  gnupg      gnupg2 gnupg  gpg2   gnupg
    pkg_native eza    eza        eza    eza    eza    eza
    pkg_native wireguard-tools wireguard-tools wireguard-tools wireguard-tools wireguard-tools wireguard-tools
}

# Делает zsh логин-шеллом пользователя по умолчанию (chsh).
# chsh требует, чтобы бинарь zsh был в /etc/shells — дописываем при необходимости
# (актуально и для brew-версии zsh на macOS, её пути там по умолчанию нет).
registered_shell() {
    if [[ "$OS" == "macos" ]]; then
        dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}'
    else
        getent passwd "$USER" 2>/dev/null | cut -d: -f7
    fi
}

set_default_shell_zsh() {
    local zsh_path
    zsh_path="$(command -v zsh)"
    if [[ -z "$zsh_path" ]]; then
        warn "zsh не найден, пропускаю смену оболочки по умолчанию"
        return 1
    fi

    local current_shell
    current_shell="$(registered_shell)"
    [[ -n "$current_shell" ]] || current_shell="$SHELL"
    info "Текущая оболочка в системе (passwd): ${current_shell:-<не определена>}"

    if [[ "$current_shell" == "$zsh_path" ]]; then
        ok "zsh уже оболочка по умолчанию"
        return 0
    fi

    if ! grep -qxF "$zsh_path" /etc/shells 2>/dev/null; then
        info "Добавляю $zsh_path в /etc/shells"
        echo "$zsh_path" | $SUDO tee -a /etc/shells >/dev/null
    fi

    info "Делаю zsh ($zsh_path) оболочкой по умолчанию для $USER"
    local chsh_status
    if chsh -s "$zsh_path" "$USER"; then
        chsh_status=0
    else
        chsh_status=$?
    fi

    # chsh может отрапортовать успех, но реально не поменять запись (PAM,
    # nsswitch на LDAP/AD и т.п.) — поэтому перечитываем passwd, а не верим
    # только коду возврата.
    local new_shell
    new_shell="$(registered_shell)"
    if [[ "$new_shell" == "$zsh_path" ]]; then
        ok "zsh теперь оболочка по умолчанию (подействует в НОВОМ логин-сеансе — новое окно терминала может быть недостаточно, если оно не запускает login shell; попробуйте перелогиниться)"
    else
        warn "chsh завершился с кодом $chsh_status, но по passwd оболочка всё ещё: ${new_shell:-<не определена>}"
        warn "Проверьте вручную: getent passwd \$USER | cut -d: -f7   и   chsh -s $zsh_path"
        MANUAL_TODO+=("chsh -s $zsh_path (после chsh оболочка в passwd не поменялась — см. вывод выше)")
    fi
}

install_terminal() {
    info "alacritty"
    if ! command -v alacritty >/dev/null 2>&1; then
        if [[ "$OS" == "macos" ]]; then
            pkg_cask alacritty ""
        else
            pkg_native "" alacritty alacritty alacritty alacritty alacritty || pkg_cask "" org.alacritty.Alacritty
        fi
    else
        ok "alacritty уже установлен"
    fi
}

install_fonts() {
    info "Nerd Fonts: Hack, 0xProto, JetBrainsMono"
    if [[ "$OS" == "macos" ]]; then
        brew install --cask font-hack-nerd-font font-0xproto-nerd-font font-jetbrains-mono-nerd-font
    else
        if ! command -v getnf >/dev/null 2>&1; then
            bash -c "$(curl -sSL https://raw.githubusercontent.com/getnf/getnf/main/install.sh)"
            export PATH="$HOME/.local/bin:$PATH"
        fi
        if command -v getnf >/dev/null 2>&1; then
            getnf -i Hack,0xProto,JetBrainsMono
        else
            warn "getnf не установился, шрифты нужно поставить вручную: https://www.nerdfonts.com/font-downloads"
            MANUAL_TODO+=("Nerd Fonts (Hack, 0xProto, JetBrainsMono) -> https://www.nerdfonts.com/font-downloads")
        fi
        fc-cache -f >/dev/null 2>&1 || true
    fi
}

install_oh_my_zsh() {
    local zsh_dir="$HOME/.config/.oh-my-zsh"
    # Проверяем не просто наличие каталога, а маркер внутри — если предыдущая
    # попытка прервалась на середине (сеть, нехватка места), останется пустой
    # или частично заполненный каталог, и его надо переустановить, а не молча
    # считать готовым.
    if [[ -f "$zsh_dir/oh-my-zsh.sh" ]]; then
        ok "oh-my-zsh уже установлен"
        return 0
    fi
    info "Устанавливаю oh-my-zsh в $zsh_dir"
    # $(curl ...) при сетевой ошибке возвращает пустую строку, а `sh -c ""`
    # молча завершается кодом 0 (пустой скрипт — не ошибка) — поэтому curl
    # запускаем отдельной командой и проверяем её код возврата явно, иначе
    # неудачное скачивание тихо считалось бы успехом.
    if ! retry 3 bash -c '
        [[ -d "$1" ]] && rm -rf "$1"
        installer="$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || exit 1
        ZSH="$1" sh -c "$installer" "" --unattended --keep-zshrc
    ' _ "$zsh_dir"; then
        err "oh-my-zsh не установился за 3 попытки (см. вывод выше) — похоже на сетевой сбой, а не ошибку конфигурации"
        return 1
    fi
}

install_oh_my_zsh_plugins() {
    local custom="${ZSH_CUSTOM:-$HOME/.config/.oh-my-zsh/custom}"
    clone_or_update https://github.com/zsh-users/zsh-syntax-highlighting.git "$custom/plugins/zsh-syntax-highlighting"
    clone_or_update https://github.com/zsh-users/zsh-autosuggestions.git     "$custom/plugins/zsh-autosuggestions"
}

install_oh_my_tmux() {
    clone_or_update https://github.com/gpakosz/.tmux.git "$HOME/.config/.oh-my-tmux"
}

install_alacritty_theme() {
    clone_or_update https://github.com/alacritty/alacritty-theme "$HOME/.config/alacritty/themes"
}

# cargo/rustup не может собирать пакеты без компилятора и линковщика (cc) —
# на минимальных установках (Parrot OS, серверные образы и т.п.) их обычно нет.
BUILD_TOOLCHAIN_READY=0
ensure_build_toolchain() {
    [[ "$BUILD_TOOLCHAIN_READY" == "1" ]] && return 0
    [[ "$OS" == "macos" ]] && { BUILD_TOOLCHAIN_READY=1; return 0; }
    command -v cc >/dev/null 2>&1 && command -v pkg-config >/dev/null 2>&1 && { BUILD_TOOLCHAIN_READY=1; return 0; }

    info "Ставлю инструменты сборки (компилятор, pkg-config, заголовки openssl)..."
    case "$PKG_MANAGER" in
        apt)    $SUDO apt-get install -y build-essential pkg-config libssl-dev ;;
        dnf)    $SUDO dnf groupinstall -y "Development Tools"; $SUDO dnf install -y pkg-config openssl-devel ;;
        pacman) $SUDO pacman -S --noconfirm --needed base-devel openssl ;;
        zypper) $SUDO zypper --non-interactive install -t pattern devel_basis; $SUDO zypper --non-interactive install pkg-config libopenssl-devel ;;
        apk)    $SUDO apk add build-base pkgconfig openssl-dev ;;
    esac
    BUILD_TOOLCHAIN_READY=1
}

install_rust() {
    if command -v rustc >/dev/null 2>&1; then
        ok "rust уже установлен"
        return 0
    fi
    info "Устанавливаю rust (rustup)..."
    ensure_build_toolchain
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile default
    [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
    command -v rustc >/dev/null 2>&1 && ok "rust установлен" || MANUAL_TODO+=("rust -> https://rustup.rs")
}

install_uv() {
    if command -v uv >/dev/null 2>&1; then
        ok "uv уже установлен"
        return 0
    fi
    info "Устанавливаю uv..."
    if [[ "$OS" == "macos" ]]; then
        brew install uv
    else
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="$HOME/.local/bin:$PATH"
    fi
    command -v uv >/dev/null 2>&1 && ok "uv установлен" || MANUAL_TODO+=("uv -> https://docs.astral.sh/uv/getting-started/installation/")
}

install_omp_manager() {
    if command -v omp-manager >/dev/null 2>&1; then
        ok "omp-manager уже установлен"
        return 0
    fi
    if ! command -v cargo >/dev/null 2>&1; then
        warn "cargo не найден, пропускаю omp-manager"
        MANUAL_TODO+=("omp-manager -> https://github.com/psmux/omp-manager (нужен rust/cargo)")
        return 1
    fi
    info "Устанавливаю omp-manager (TUI-мастер настройки Oh My Posh: темы, шрифты, шеллы)..."
    warn_if_low_disk_space /tmp
    if retry 3 cargo_install_clean omp-manager; then
        ok "omp-manager установлен"
    else
        warn "cargo install omp-manager не удался"
        MANUAL_TODO+=("omp-manager -> https://github.com/psmux/omp-manager")
        return 1
    fi
}
