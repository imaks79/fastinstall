#!/usr/bin/env bash
# Установка "дополнительных" TUI/CLI-инструментов (tools-extra.sh) — список
# специально сделан таблицей одной функции (install_tool) + case в tool_desc,
# чтобы дописать новый инструмент было одной строкой в каждой из них, без
# ассоциативных массивов (их нет в bash 3.2 — системном /bin/bash на macOS).

# pkg_or_cargo <cli-бинарь> <cargo-крейт> <brew> <apt> <dnf> <pacman> <zypper> <apk>
# Сначала пробует нативный пакетный менеджер (pkg_native), при неудаче —
# `cargo install <крейт>` (rust уже стоит после setup.sh, см. install_rust()).
# Пустой crate = фолбэка нет, промах пакетного менеджера идёт в MANUAL_TODO.
pkg_or_cargo() {
    local bin="$1" crate="$2" brew_name="$3" apt_name="$4" dnf_name="$5" pacman_name="$6" zypper_name="$7" apk_name="$8"
    if command -v "$bin" >/dev/null 2>&1; then
        ok "$bin уже установлен"
        return 0
    fi
    if pkg_native "$brew_name" "$apt_name" "$dnf_name" "$pacman_name" "$zypper_name" "$apk_name"; then
        ok "$bin: пакет поставлен через пакетный менеджер"
        return 0
    fi
    if [[ -z "$crate" ]]; then
        warn "$bin недоступен через пакетный менеджер на этой системе"
        MANUAL_TODO+=("$bin -> нет пакета в этом пакетном менеджере, ставьте вручную")
        return 1
    fi
    if ! ensure_cargo_in_path; then
        warn "$bin недоступен через пакетный менеджер, а cargo не найден"
        MANUAL_TODO+=("$bin -> нет пакета в этом пакетном менеджере; поставьте rust (cargo install $crate)")
        return 1
    fi
    info "$bin недоступен через пакетный менеджер, ставлю: cargo install $crate"
    ensure_build_toolchain
    warn_if_low_disk_space /tmp
    # shellcheck disable=SC2086 # $crate иногда содержит несколько имён крейтов (yazi-fm yazi-cli)
    if cargo_install_clean $crate; then
        ok "$bin установлен через cargo"
    else
        warn "cargo install $crate не удался"
        MANUAL_TODO+=("$bin -> cargo install $crate")
        return 1
    fi
}

# install_gh_release_bin <owner/repo> <бинарь> <имя-архива-без-расширения> <ext>
# Общий загрузчик для проектов на Go/C без покрытия во всех пакетных
# менеджерах: качает .tar.gz (или .deb) с GitHub Releases, по возможности
# проверяет sha256 по файлу контрольных сумм на той же странице релиза.
# checksums_name пустой = проверка пропускается (не у всех проектов есть файл).
install_gh_release_tar() {
    local repo="$1" bin="$2" asset="$3" checksums_name="$4" bin_path_in_tar="${5:-}"
    [[ -n "$bin_path_in_tar" ]] || bin_path_in_tar="$bin"
    if command -v "$bin" >/dev/null 2>&1; then
        ok "$bin уже установлен"
        return 0
    fi
    info "$bin недоступен через пакетный менеджер, ставлю бинарь с GitHub Releases ($repo)"
    local tag
    tag="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
    if [[ -z "$tag" ]]; then
        warn "$bin: не удалось узнать версию последнего релиза"
        MANUAL_TODO+=("$bin -> https://github.com/$repo/releases")
        return 1
    fi
    local base_url="https://github.com/$repo/releases/download/$tag"
    local tmp; tmp="$(mktemp -d)"

    if ! curl -fsSL -o "$tmp/$asset" "$base_url/$asset"; then
        warn "$bin: не удалось скачать $asset (версия $tag)"
        rm -rf "$tmp"; MANUAL_TODO+=("$bin -> $base_url"); return 1
    fi
    if [[ -n "$checksums_name" ]]; then
        if curl -fsSL -o "$tmp/$checksums_name" "$base_url/$checksums_name" 2>/dev/null; then
            if ! (cd "$tmp" && awk -v f="$asset" '$2 == f' "$checksums_name" | sha256sum -c - >/dev/null 2>&1); then
                warn "$bin: контрольная сумма не совпала, НЕ устанавливаю"
                rm -rf "$tmp"; MANUAL_TODO+=("$bin: проверьте вручную -> $base_url"); return 1
            fi
        else
            warn "$bin: файл контрольных сумм не скачался, ставлю без проверки"
        fi
    fi

    tar -xzf "$tmp/$asset" -C "$tmp" "$bin_path_in_tar" 2>/dev/null || tar -xzf "$tmp/$asset" -C "$tmp"
    $SUDO install -m0755 "$tmp/$bin_path_in_tar" "/usr/local/bin/$bin"
    rm -rf "$tmp"

    if command -v "$bin" >/dev/null 2>&1; then
        ok "$bin установлен ($tag)"
    else
        MANUAL_TODO+=("$bin -> $base_url")
        return 1
    fi
}

# install_gh_release_bin <owner/repo> <бинарь> <имя-ассета> <имя-sha256-файла>
# Для проектов, публикующих голый бинарь (без tar.gz) прямо в релизе.
# sha256-файл может содержать чужой путь во втором поле (не имя ассета) —
# поэтому сверяем сумму сами, а не через `sha256sum -c`, как в install_gh_release_tar.
# checksums_name пустой = проверка пропускается.
install_gh_release_bin() {
    local repo="$1" bin="$2" asset="$3" sha_asset="$4"
    if command -v "$bin" >/dev/null 2>&1; then
        ok "$bin уже установлен"
        return 0
    fi
    info "$bin недоступен через пакетный менеджер, ставлю бинарь с GitHub Releases ($repo)"
    local tag
    tag="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
    if [[ -z "$tag" ]]; then
        warn "$bin: не удалось узнать версию последнего релиза"
        MANUAL_TODO+=("$bin -> https://github.com/$repo/releases")
        return 1
    fi
    local base_url="https://github.com/$repo/releases/download/$tag"
    local tmp; tmp="$(mktemp -d)"

    if ! curl -fsSL -o "$tmp/$asset" "$base_url/$asset"; then
        warn "$bin: не удалось скачать $asset (версия $tag)"
        rm -rf "$tmp"; MANUAL_TODO+=("$bin -> $base_url"); return 1
    fi
    if [[ -n "$sha_asset" ]]; then
        if curl -fsSL -o "$tmp/$sha_asset" "$base_url/$sha_asset" 2>/dev/null; then
            local expected actual
            expected="$(awk '{print $1}' "$tmp/$sha_asset")"
            actual="$(sha256sum "$tmp/$asset" | awk '{print $1}')"
            if [[ -z "$expected" || "$expected" != "$actual" ]]; then
                warn "$bin: контрольная сумма не совпала, НЕ устанавливаю"
                rm -rf "$tmp"; MANUAL_TODO+=("$bin: проверьте вручную -> $base_url"); return 1
            fi
        else
            warn "$bin: файл контрольных сумм не скачался, ставлю без проверки"
        fi
    fi

    chmod +x "$tmp/$asset"
    $SUDO install -m0755 "$tmp/$asset" "/usr/local/bin/$bin"
    rm -rf "$tmp"

    if command -v "$bin" >/dev/null 2>&1; then
        ok "$bin установлен ($tag)"
    else
        MANUAL_TODO+=("$bin -> $base_url")
        return 1
    fi
}

# install_gh_release_deb <owner/repo> <бинарь> <имя-.deb>
# Для проектов, публикующих .deb прямо в релизе — ставим через dpkg, чтобы
# попасть в базу пакетов apt, а не просто разложить файл в /usr/local/bin.
install_gh_release_deb() {
    local repo="$1" bin="$2" asset="$3"
    if command -v "$bin" >/dev/null 2>&1; then
        ok "$bin уже установлен"
        return 0
    fi
    info "$bin недоступен через apt, ставлю .deb с GitHub Releases ($repo)"
    local tag
    tag="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
    if [[ -z "$tag" ]]; then
        warn "$bin: не удалось узнать версию последнего релиза"
        MANUAL_TODO+=("$bin -> https://github.com/$repo/releases")
        return 1
    fi
    local url="https://github.com/$repo/releases/download/$tag/$asset"
    local tmp; tmp="$(mktemp -d)"
    if ! curl -fsSL -o "$tmp/$asset" "$url"; then
        warn "$bin: не удалось скачать $asset"
        rm -rf "$tmp"; MANUAL_TODO+=("$bin -> $url"); return 1
    fi
    $SUDO dpkg -i "$tmp/$asset" >/dev/null 2>&1 || $SUDO apt-get install -y -qq "$tmp/$asset" >/dev/null 2>&1
    rm -rf "$tmp"
    if command -v "$bin" >/dev/null 2>&1; then
        ok "$bin установлен ($tag)"
    else
        MANUAL_TODO+=("$bin -> $url")
        return 1
    fi
}

# alacritty — GPU-терминал; переехал сюда из setup.sh, т.к. не всем нужен
# именно alacritty. Тема alacritty-theme сюда не входит — она осталась в
# setup.sh (install_alacritty_theme() в lib/packages.sh), отдельным шагом.
install_alacritty() {
    if command -v alacritty >/dev/null 2>&1; then
        ok "alacritty уже установлен"
    elif [[ "$OS" == "macos" ]]; then
        pkg_cask alacritty ""
    else
        pkg_native "" alacritty alacritty alacritty alacritty alacritty || pkg_cask "" org.alacritty.Alacritty
    fi
}

# omp-manager — TUI-мастер настройки Oh My Posh (темы, шрифты, шеллы);
# переехал сюда из setup.sh — сам Oh My Posh (движок темы шелла) ставится
# там (install_oh_my_posh() в lib/packages.sh, по ohmyposh.dev), а этот
# мастер уже не всем нужен, конфигурировать можно и руками. Только cargo
# install — на crates.io, в системных пакетных менеджерах пакета нет.
install_omp_manager() {
    if command -v omp-manager >/dev/null 2>&1; then
        ok "omp-manager уже установлен"
        return 0
    fi
    if ! ensure_cargo_in_path; then
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

install_lazygit() {
    command -v lazygit >/dev/null 2>&1 && { ok "lazygit уже установлен"; return 0; }
    if pkg_native lazygit "" "" lazygit lazygit lazygit && command -v lazygit >/dev/null 2>&1; then
        ok "lazygit установлен"; return 0
    fi
    [[ "$OS" == "linux" ]] || { MANUAL_TODO+=("lazygit -> https://github.com/jesseduffield/lazygit#installation"); return 1; }
    local arch; case "$(uname -m)" in
        x86_64|amd64) arch=x86_64 ;;
        aarch64|arm64) arch=arm64 ;;
        *) MANUAL_TODO+=("lazygit -> https://github.com/jesseduffield/lazygit/releases"); return 1 ;;
    esac
    local tag; tag="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest 2>/dev/null | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -1)"
    [[ -n "$tag" ]] || { MANUAL_TODO+=("lazygit -> https://github.com/jesseduffield/lazygit/releases"); return 1; }
    install_gh_release_tar "jesseduffield/lazygit" "lazygit" "lazygit_${tag}_linux_${arch}.tar.gz" "checksums.txt"
}

install_gonzo() {
    command -v gonzo >/dev/null 2>&1 && { ok "gonzo уже установлен"; return 0; }
    if pkg_native gonzo "" "" "" "" "" && command -v gonzo >/dev/null 2>&1; then
        ok "gonzo установлен"; return 0
    fi
    [[ "$OS" == "linux" ]] || { MANUAL_TODO+=("gonzo -> https://github.com/control-theory/gonzo#installation"); return 1; }
    local arch; case "$(uname -m)" in
        x86_64|amd64) arch=amd64 ;;
        aarch64|arm64) arch=arm64 ;;
        *) MANUAL_TODO+=("gonzo -> https://github.com/control-theory/gonzo/releases"); return 1 ;;
    esac
    local tag; tag="$(curl -fsSL https://api.github.com/repos/control-theory/gonzo/releases/latest 2>/dev/null | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -1)"
    [[ -n "$tag" ]] || { MANUAL_TODO+=("gonzo -> https://github.com/control-theory/gonzo/releases"); return 1; }
    install_gh_release_tar "control-theory/gonzo" "gonzo" "gonzo-${tag}-linux-${arch}.tar.gz" "checksums.txt"
}

install_lazydocker() {
    command -v lazydocker >/dev/null 2>&1 && { ok "lazydocker уже установлен"; return 0; }
    if pkg_native lazydocker "" "" lazydocker "" lazydocker && command -v lazydocker >/dev/null 2>&1; then
        ok "lazydocker установлен"; return 0
    fi
    [[ "$OS" == "linux" ]] || { MANUAL_TODO+=("lazydocker -> https://github.com/jesseduffield/lazydocker#installation"); return 1; }
    info "lazydocker недоступен через пакетный менеджер, ставлю официальным install-скриптом"
    if DIR=/usr/local/bin $SUDO bash -c "$(curl -fsSL https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh)"; then
        command -v lazydocker >/dev/null 2>&1 && ok "lazydocker установлен" || MANUAL_TODO+=("lazydocker -> https://github.com/jesseduffield/lazydocker#installation")
    else
        MANUAL_TODO+=("lazydocker -> https://github.com/jesseduffield/lazydocker#installation")
        return 1
    fi
}

install_k9s() {
    command -v k9s >/dev/null 2>&1 && { ok "k9s уже установлен"; return 0; }
    if pkg_native k9s "" k9s k9s k9s k9s && command -v k9s >/dev/null 2>&1; then
        ok "k9s установлен"; return 0
    fi
    [[ "$OS" == "linux" && "$PKG_MANAGER" == "apt" ]] || { MANUAL_TODO+=("k9s -> https://github.com/derailed/k9s#installation"); return 1; }
    local arch; case "$(uname -m)" in
        x86_64|amd64) arch=amd64 ;;
        aarch64|arm64) arch=arm64 ;;
        *) MANUAL_TODO+=("k9s -> https://github.com/derailed/k9s/releases"); return 1 ;;
    esac
    install_gh_release_deb "derailed/k9s" "k9s" "k9s_linux_${arch}.deb"
}

# 7-Zip нужен не отдельным пунктом меню, а как зависимость yazi (превью и
# распаковка архивов) — brew-имя специально "sevenzip", НЕ "7zip" (то —
# standalone-версия, yazi по официальной доке требует non-standalone), см.
# install_yazi_deps().
install_7zip() {
    if command -v 7z >/dev/null 2>&1 || command -v 7zz >/dev/null 2>&1; then
        ok "7-zip уже установлен"
        return 0
    fi
    pkg_native sevenzip p7zip-full 7zip 7zip 7zip p7zip
    if command -v 7z >/dev/null 2>&1 || command -v 7zz >/dev/null 2>&1; then
        ok "7-zip установлен"
    else
        warn "7-zip не установился через пакетный менеджер"
        MANUAL_TODO+=("7zip -> https://7-zip.org (или p7zip для вашего дистрибутива)")
        return 1
    fi
}

# install_yazi_deps — опциональные зависимости yazi по официальной доке
# (https://yazi-rs.github.io/docs/installation/, раздел Optional dependencies):
# каждая по отдельности необязательна (yazi запустится и без них), но без
# неё отваливается конкретное превью/фича. Отдельных пунктов меню для них
# нет — ставятся как часть install_tool(yazi), падение одной зависимости не
# должно останавливать установку остальных (поэтому не step(), а просто
# лучшее усилие: предупреждение + MANUAL_TODO уходит из каждой pkg_*-обёртки
# самостоятельно, install_yazi_deps() дальше не проверяет коды возврата).
install_yazi_deps() {
    info "Зависимости yazi: ffmpeg, 7-zip, jq, poppler, fd, ripgrep, fzf, zoxide, resvg, imagemagick$( [[ "$OS" == "linux" ]] && echo ', xclip/wl-clipboard' )"
    pkg_native ffmpeg      ffmpeg          ffmpeg      ffmpeg  ffmpeg   ffmpeg
    install_7zip
    pkg_native jq          jq              jq          jq      jq       jq
    pkg_native poppler     poppler-utils   poppler-utils poppler poppler-tools poppler-utils
    pkg_native fd          fd-find         fd-find     fd      fd       fd
    pkg_native ripgrep     ripgrep         ripgrep     ripgrep ripgrep  ripgrep
    pkg_native fzf         fzf             fzf         fzf     fzf      fzf
    pkg_native zoxide      zoxide          zoxide      zoxide  zoxide   zoxide
    pkg_or_cargo resvg resvg resvg "" "" "" "" ""
    pkg_native imagemagick imagemagick     ImageMagick imagemagick ImageMagick imagemagick
    if [[ "$OS" == "linux" ]]; then
        pkg_native "" xclip xclip xclip xclip xclip
        pkg_native "" wl-clipboard wl-clipboard wl-clipboard wl-clipboard wl-clipboard
    fi
}

# yazi — официальная установка по https://yazi-rs.github.io/docs/installation/:
# на macOS и там, где есть нативный пакет (pacman/zypper/apk — под именем
# "yazi"), ставим им; на Debian/Ubuntu (apt) официального пакета в самих
# репозиториях нет — доки предлагают собственный apt-репозиторий
# yazi-rs.github.io/builds (stable), подключаем его так же, как доки; на
# Fedora/dnf — через copr lihaohong/yazi (тоже по доке). Если ничего из
# этого не сработало (или пакетного менеджера с готовым путём нет вообще) —
# фолбэк тот же, что рекомендует официальная дока для cargo: `cargo install
# --force yazi-build` (единый мета-крейт, а не yazi-fm+yazi-cli по отдельности).
install_yazi() {
    if command -v yazi >/dev/null 2>&1; then
        ok "yazi уже установлен"
    elif [[ "$OS" == "macos" ]]; then
        pkg_native yazi "" "" "" "" ""
    elif [[ "$PKG_MANAGER" == "apt" ]]; then
        info "yazi недоступен в стандартных репозиториях apt, подключаю официальный репозиторий yazi-rs.github.io/builds"
        curl -fsSL https://yazi-rs.github.io/builds/yazi-keyring.gpg | $SUDO tee /usr/share/keyrings/yazi-keyring.gpg >/dev/null
        echo 'deb [signed-by=/usr/share/keyrings/yazi-keyring.gpg] https://yazi-rs.github.io/builds/ stable main' | $SUDO tee /etc/apt/sources.list.d/yazi.list >/dev/null
        $SUDO apt-get update -y && $SUDO apt-get install -y yazi
    elif [[ "$PKG_MANAGER" == "dnf" ]]; then
        info "yazi недоступен напрямую в dnf, подключаю copr lihaohong/yazi (по официальной доке)"
        $SUDO dnf copr enable -y lihaohong/yazi
        $SUDO dnf install -y yazi
    else
        pkg_native "" "" "" yazi yazi yazi
    fi

    if ! command -v yazi >/dev/null 2>&1; then
        if ensure_cargo_in_path; then
            info "yazi недоступен через пакетный менеджер, ставлю: cargo install --force yazi-build"
            ensure_build_toolchain
            warn_if_low_disk_space /tmp
            if ! cargo_install_clean --force yazi-build; then
                warn "cargo install --force yazi-build не удался"
                MANUAL_TODO+=("yazi -> https://yazi-rs.github.io/docs/installation/")
            fi
        else
            warn "yazi недоступен через пакетный менеджер, а cargo не найден"
            MANUAL_TODO+=("yazi -> https://yazi-rs.github.io/docs/installation/ (нужен rust/cargo, если нет нативного пакета)")
        fi
    fi

    if command -v yazi >/dev/null 2>&1; then
        ok "yazi установлен"
    fi

    install_yazi_deps
}

install_fastfetch() {
    command -v fastfetch >/dev/null 2>&1 && { ok "fastfetch уже установлен"; return 0; }
    if pkg_native fastfetch "" fastfetch fastfetch fastfetch fastfetch && command -v fastfetch >/dev/null 2>&1; then
        ok "fastfetch установлен"; return 0
    fi
    [[ "$OS" == "linux" && "$PKG_MANAGER" == "apt" ]] || { MANUAL_TODO+=("fastfetch -> https://github.com/fastfetch-cli/fastfetch#installation"); return 1; }
    local arch; case "$(uname -m)" in
        x86_64|amd64) arch=amd64 ;;
        aarch64|arm64) arch=aarch64 ;;
        *) MANUAL_TODO+=("fastfetch -> https://github.com/fastfetch-cli/fastfetch/releases"); return 1 ;;
    esac
    install_gh_release_deb "fastfetch-cli/fastfetch" "fastfetch" "fastfetch-linux-${arch}.deb"
}

# install_ide — диалог выбора Neovim IDE-дистрибутива. AstroNvim и NvChad
# официально ставятся ОДНИМ и тем же способом — git clone прямо в
# ~/.config/nvim (docs.astronvim.com, nvchad.com/docs/quickstart/install),
# поэтому одновременно там может быть только один из двух, и по факту
# наличия каталога не отличить, какой именно — ide_nvim_marker_file() ниже хранит,
# что туда поставил этот диалог. LunarVim официально ставится отдельно, в
# ~/.config/lvim (свой NVIM_APPNAME=lvim), в этот маркер не входит. Выбор
# уже стоящего варианта не обновляет его на месте, а сносит конфиг/данные/
# state/кэш (без бэкапа) и ставит заново с нуля — как рекомендуют доки
# каждого проекта для чистой переустановки.
install_ide() {
    echo
    info "Выберите Neovim IDE-дистрибутив:"
    echo "  1) AstroNvim         — https://docs.astronvim.com/"
    echo "  2) NvChad            — https://nvchad.com/docs/quickstart/install"
    echo "  3) LunarVim          — https://www.lunarvim.org/docs/installation"
    echo "  4) Очистить редактор — снести конфиг/данные/кэш всех трёх, чтобы попробовать с нуля"
    local choice
    read -r -p "Номер варианта [1-4]: " choice
    case "$choice" in
        1) install_astronvim_ide ;;
        2) install_nvchad ;;
        3) install_lunarvim ;;
        4) clean_nvim_configs ;;
        *) warn "Не понял выбор ($choice), ничего не ставлю"; return 1 ;;
    esac
}

# Маркер того, что сейчас лежит в ~/.config/nvim — astronvim/nvchad; по
# одному наличию каталога это не различить, оба официально ставятся туда же.
# Путь считаем функцией, а не глобальной переменной — $HOME должен браться
# на момент вызова, а не на момент подключения этого файла. Отсутствие
# файла не значит "пусто" — например, ~/.config/nvim может быть симлинком,
# разложенным отдельным репозиторием с dotfiles; current_nvim_marker()
# описывает и этот случай.
ide_nvim_marker_file() { echo "$HOME/.cache/dotfiles-ide-marker"; }

current_nvim_marker() {
    if [[ -f "$(ide_nvim_marker_file)" ]]; then
        cat "$(ide_nvim_marker_file)"
    else
        echo "не через этот диалог"
    fi
}

# Сносит общий "отпечаток" в ~/.config/nvim: ~/.config/nvim,
# ~/.local/share/nvim, ~/.local/state/nvim, ~/.cache/nvim — один и тот же
# набор путей что у AstroNvim (docs.astronvim.com), что у NvChad
# (nvchad.com/docs/quickstart/install, раздел Uninstall), плюс Flatpak-путь
# io.neovim.nvim на Linux. rm -rf на симлинк убирает только сам симлинк, не
# трогая то, на что он указывает — так что сносить безопасно, даже не зная
# заранее, что там стояло.
wipe_nvim_namespace() {
    rm -rf "$HOME/.config/nvim" "$HOME/.local/share/nvim" "$HOME/.local/state/nvim" "$HOME/.cache/nvim"
    if [[ "$OS" == "linux" ]]; then
        rm -rf "$HOME/.var/app/io.neovim.nvim/config/nvim" \
               "$HOME/.var/app/io.neovim.nvim/data/nvim" \
               "$HOME/.var/app/io.neovim.nvim/.local/state/nvim"
    fi
    rm -f "$(ide_nvim_marker_file)"
}

# Официальный AstroNvim/template (docs.astronvim.com): git clone шаблона
# прямо в ~/.config/nvim, .git из клона убираем — как в доке, иначе конфиг
# остаётся форком AstroNvim/template, а не самостоятельным репозиторием.
install_astronvim_ide() {
    if [[ -f "$(ide_nvim_marker_file)" || -e "$HOME/.config/nvim" || -L "$HOME/.config/nvim" ]]; then
        info "В ~/.config/nvim уже стоит ($(current_nvim_marker)), зачищаю и ставлю AstroNvim заново с нуля"
        wipe_nvim_namespace
    fi
    info "Ставлю AstroNvim: git clone --depth 1 https://github.com/AstroNvim/template ~/.config/nvim"
    if retry 3 bash -c '[[ -d "$1" && ! -d "$1/.git" ]] && rm -rf "$1"; git clone --quiet --depth 1 "$2" "$1"' \
        _ "$HOME/.config/nvim" https://github.com/AstroNvim/template; then
        rm -rf "$HOME/.config/nvim/.git"
        echo astronvim > "$(ide_nvim_marker_file)"
        ok "AstroNvim установлен в ~/.config/nvim — запускайте: nvim"
    else
        warn "git clone AstroNvim/template не удался"
        MANUAL_TODO+=("AstroNvim -> https://docs.astronvim.com/")
        return 1
    fi
}

# Официальный NvChad (nvchad.com/docs/quickstart/install): git clone
# стартового конфига прямо в ~/.config/nvim. .git специально оставляем —
# так в официальной команде (git clone .../starter ~/.config/nvim && nvim).
install_nvchad() {
    if [[ -f "$(ide_nvim_marker_file)" || -e "$HOME/.config/nvim" || -L "$HOME/.config/nvim" ]]; then
        info "В ~/.config/nvim уже стоит ($(current_nvim_marker)), зачищаю и ставлю NvChad заново с нуля"
        wipe_nvim_namespace
    fi
    info "Ставлю NvChad: git clone https://github.com/NvChad/starter ~/.config/nvim"
    if retry 3 bash -c '[[ -d "$1" && ! -d "$1/.git" ]] && rm -rf "$1"; git clone --quiet "$2" "$1"' \
        _ "$HOME/.config/nvim" https://github.com/NvChad/starter; then
        echo nvchad > "$(ide_nvim_marker_file)"
        ok "NvChad установлен в ~/.config/nvim — запускайте: nvim"
    else
        warn "git clone NvChad/starter не удался"
        MANUAL_TODO+=("NvChad -> https://nvchad.com/docs/quickstart/install")
        return 1
    fi
}

# Официальный установщик LunarVim (lunarvim.org/docs/installation, ветка
# master — как в доке): свой NVIM_APPNAME=lvim — ~/.config/lvim,
# ~/.local/share/lunarvim, ~/.cache/lvim, бинарь lvim — с ~/.config/nvim не
# пересекается, в маркер выше не входит. Переустановка — через бандловый
# utils/installer/uninstall.sh самого LunarVim (локальная копия в приоритете,
# чтобы не тянуть сеть повторно): --remove-config, иначе он оставляет
# LUNARVIM_CONFIG_DIR нетронутым, а --remove-backups подчищает .bak/.old.
install_lunarvim() {
    if command -v lvim >/dev/null 2>&1; then
        info "LunarVim уже установлен, зачищаю официальным uninstall.sh и ставлю заново с нуля"
        if [[ -f "$HOME/.local/share/lunarvim/lvim/utils/installer/uninstall.sh" ]]; then
            bash "$HOME/.local/share/lunarvim/lvim/utils/installer/uninstall.sh" --remove-config --remove-backups
        else
            bash -c "$(curl -fsSL https://raw.githubusercontent.com/lunarvim/lunarvim/master/utils/installer/uninstall.sh)" _ --remove-config --remove-backups
        fi
        # На случай, если сам uninstall.sh (например, старой версии) что-то не подчистил.
        rm -rf "$HOME/.config/lvim" "$HOME/.local/share/lunarvim" "$HOME/.cache/lvim"
    fi
    info "Ставлю LunarVim официальным установщиком (ветка master)"
    if bash -c "$(curl -fsSL https://raw.githubusercontent.com/lunarvim/lunarvim/master/utils/installer/install.sh)" _ -y --overwrite; then
        ok "LunarVim установлен — запускайте: lvim"
    elif command -v lvim >/dev/null 2>&1; then
        # install.sh может выйти с ошибкой уже после того, как бинарь lvim
        # готов — например, если проверка версий плагинов по лок-файлу не
        # сошлась (несовпадение git-коммита у какого-то плагина). Сам
        # установщик в этом случае прямо пишет, что делать: :Lazy sync
        # при первом запуске lvim — это не переустановка с нуля.
        warn "Установщик LunarVim сообщил об ошибке, но бинарь lvim уже стоит — похоже, разошлись версии плагинов по лок-файлу (несовпадение git-коммита)"
        MANUAL_TODO+=("LunarVim -> запустите lvim и выполните :Lazy sync (несовпадение версий плагинов при первой установке); либо повторите ./tools-extra.sh ide и выберите LunarVim ещё раз для чистой переустановки")
        return 1
    else
        warn "Установщик LunarVim завершился с ошибкой"
        MANUAL_TODO+=("LunarVim -> https://www.lunarvim.org/docs/installation")
        return 1
    fi
}

# «Очистить редактор» — сносит все три варианта из install_ide разом, без
# бэкапа, чтобы затем поставить любую сборку с нуля:
#   AstroNvim/NvChad — общий ~/.config/nvim + ~/.local/share/nvim +
#     ~/.local/state/nvim + ~/.cache/nvim (+ Flatpak io.neovim.nvim на Linux),
#     см. wipe_nvim_namespace.
#   LunarVim — официальный uninstall.sh (--remove-config --remove-backups),
#     как в lunarvim.org/docs/installation, плюс rm -rf следом на всякий случай.
# Windows-пути из тех же доков (AppData\Local\nvim...) не относятся к этому
# bash-скрипту — репозиторий вообще не поддерживает Windows нигде ещё.
clean_nvim_configs() {
    local nvim_dirs=("$HOME/.config/nvim" "$HOME/.local/share/nvim" "$HOME/.local/state/nvim" "$HOME/.cache/nvim")
    if [[ "$OS" == "linux" ]]; then
        nvim_dirs+=(
            "$HOME/.var/app/io.neovim.nvim/config/nvim"
            "$HOME/.var/app/io.neovim.nvim/data/nvim"
            "$HOME/.var/app/io.neovim.nvim/.local/state/nvim"
        )
    fi
    local lvim_dirs=("$HOME/.config/lvim" "$HOME/.local/share/lunarvim" "$HOME/.cache/lvim")
    local lvim_bin=""
    command -v lvim >/dev/null 2>&1 && lvim_bin="$(command -v lvim)"

    echo
    warn "Будут безвозвратно удалены (без бэкапа):"
    local d found=0
    for d in "${nvim_dirs[@]}" "${lvim_dirs[@]}"; do
        if [[ -e "$d" || -L "$d" ]]; then
            printf '    - %s\n' "$d"
            found=1
        fi
    done
    [[ -n "$lvim_bin" ]] && { printf '    - %s (бинарь lvim)\n' "$lvim_bin"; found=1; }
    if [[ -f "$(ide_nvim_marker_file)" ]]; then
        printf '    (в ~/.config/nvim сейчас стоял: %s)\n' "$(current_nvim_marker)"
    fi
    if [[ "$found" -eq 0 ]]; then
        ok "Нечего чистить — конфигов/данных Neovim не найдено"
        return 0
    fi

    local reply
    read -r -p "Точно удалить всё это без бэкапа? [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] || { info "Отменено, ничего не удалено"; return 0; }

    wipe_nvim_namespace

    if [[ -n "$lvim_bin" ]]; then
        if [[ -f "$HOME/.local/share/lunarvim/lvim/utils/installer/uninstall.sh" ]]; then
            bash "$HOME/.local/share/lunarvim/lvim/utils/installer/uninstall.sh" --remove-config --remove-backups
        else
            bash -c "$(curl -fsSL https://raw.githubusercontent.com/lunarvim/lunarvim/master/utils/installer/uninstall.sh)" _ --remove-config --remove-backups
        fi
    fi
    rm -rf "${lvim_dirs[@]}"
    [[ -n "$lvim_bin" ]] && rm -f "$lvim_bin"

    ok "Neovim IDE очищен — ставьте заново: ./tools-extra.sh ide"
}

install_keyward() {
    command -v keyward >/dev/null 2>&1 && { ok "keyward уже установлен"; return 0; }
    if pkg_native "gateway-of-last-resort/tap/keyward" "" "" "" "" "" && command -v keyward >/dev/null 2>&1; then
        ok "keyward установлен"; return 0
    fi
    [[ "$OS" == "linux" ]] || { MANUAL_TODO+=("keyward -> https://github.com/gateway-of-last-resort/keyward#installation"); return 1; }
    local arch; case "$(uname -m)" in
        x86_64|amd64) arch=amd64 ;;
        aarch64|arm64) arch=arm64 ;;
        *) MANUAL_TODO+=("keyward -> https://github.com/gateway-of-last-resort/keyward/releases"); return 1 ;;
    esac
    local tag; tag="$(curl -fsSL https://api.github.com/repos/gateway-of-last-resort/keyward/releases/latest 2>/dev/null | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -1)"
    [[ -n "$tag" ]] || { MANUAL_TODO+=("keyward -> https://github.com/gateway-of-last-resort/keyward/releases"); return 1; }
    install_gh_release_tar "gateway-of-last-resort/keyward" "keyward" "keyward_${tag}_linux_${arch}.tar.gz" "checksums.txt"
}

# isd — Python/Textual TUI для systemd-юнитов, единственный официальный
# способ установки — `uv tool install` (uv уже ставит основной setup.sh,
# см. install_uv() в lib/packages.sh). Пакетов в brew/apt/dnf/pacman/zypper/
# apk нет, поэтому обычный pkg_or_cargo тут не подходит. systemd есть только
# на Linux — на macOS инструмент бесполезен, пропускаем как wlctl.
install_isd() {
    if [[ "$OS" != "linux" ]]; then
        info "isd управляет systemd-юнитами, есть только на Linux — пропускаю на macOS"
        return 0
    fi
    command -v isd >/dev/null 2>&1 && { ok "isd уже установлен"; return 0; }
    if ! command -v uv >/dev/null 2>&1; then
        warn "isd ставится через uv, а uv не найден"
        MANUAL_TODO+=("isd -> поставьте uv (install_uv() в setup.sh), затем: uv tool install --python=3.11 isd-tui")
        return 1
    fi
    info "Ставлю isd: uv tool install --python=3.11 isd-tui"
    if uv tool install --python=3.11 isd-tui; then
        ok "isd установлен"
    else
        warn "uv tool install isd-tui не удался"
        MANUAL_TODO+=("isd -> uv tool install --python=3.11 isd-tui")
        return 1
    fi
}

# lazyssh — Go-проект, публикует tar.gz с GitHub Releases (goreleaser) и tap
# Adembc/homebrew-tap для brew. go.mod содержит `replace` на форкнутый модуль
# (kevinburke/ssh_config -> adembc/ssh_config) — `go install` его игнорирует
# вне основного модуля, поэтому такого фолбэка в официальной доке нет и здесь
# он не используется, только brew/бинарь с релизов.
#
# Путь ~/.lazyssh (лог + metadata.json) захардкожен в самом бинарнике
# (internal/logger/logger.go: filepath.Join(home, ".lazyssh")), флага или
# переменной окружения для его переопределения нет. Поэтому вместо
# ~/.lazyssh здесь используется симлинк на ~/.config/lazyssh: бинарь
# как писал в "~/.lazyssh", так и продолжает, а реальные файлы лежат
# в ~/.config/lazyssh (единообразно с остальными XDG-инструментами).
relocate_lazyssh_home() {
    local real="$HOME/.config/lazyssh" link="$HOME/.lazyssh"
    if [[ -L "$link" ]]; then
        return 0
    fi
    mkdir -p "$real"
    if [[ -d "$link" ]]; then
        # переносим то, что уже успел создать бинарь при предыдущих запусках
        find "$link" -mindepth 1 -maxdepth 1 -exec mv -n {} "$real"/ \;
        rmdir "$link" 2>/dev/null || rm -rf "$link"
    fi
    ln -s "$real" "$link"
}

install_lazyssh() {
    if command -v lazyssh >/dev/null 2>&1; then
        relocate_lazyssh_home
        ok "lazyssh уже установлен"; return 0
    fi
    if pkg_native "Adembc/homebrew-tap/lazyssh" "" "" "" "" "" && command -v lazyssh >/dev/null 2>&1; then
        relocate_lazyssh_home
        ok "lazyssh установлен"; return 0
    fi
    [[ "$OS" == "linux" ]] || { MANUAL_TODO+=("lazyssh -> https://github.com/Adembc/lazyssh#-installation"); return 1; }
    local arch; case "$(uname -m)" in
        x86_64|amd64) arch=x86_64 ;;
        aarch64|arm64) arch=arm64 ;;
        *) MANUAL_TODO+=("lazyssh -> https://github.com/Adembc/lazyssh/releases"); return 1 ;;
    esac
    install_gh_release_tar "Adembc/lazyssh" "lazyssh" "lazyssh_Linux_${arch}.tar.gz" "checksums.txt" \
        && relocate_lazyssh_home
}

# herdr (herdr.dev) — агенто-осведомлённый мультиплексор терминала для
# коалиций coding-агентов, живёт в homebrew/core под своим именем, поэтому
# на macOS ставится нативно. Одноимённый крейт на crates.io
# (ogulcancelik/herdr, "workspace manager for AI agents") — другой,
# несвязанный проект, поэтому `cargo install herdr` тут НЕ используется как
# фолбэк (поставил бы не тот бинарь). На Linux нативных пакетов нет — голый
# бинарь с GitHub Releases; отдельного файла контрольных сумм релиз не
# публикует, поэтому проверка sha256 здесь пропускается.
install_herdr() {
    command -v herdr >/dev/null 2>&1 && { ok "herdr уже установлен"; return 0; }
    if pkg_native herdr "" "" "" "" "" && command -v herdr >/dev/null 2>&1; then
        ok "herdr установлен"; return 0
    fi
    [[ "$OS" == "linux" ]] || { MANUAL_TODO+=("herdr -> https://herdr.dev/docs/install/"); return 1; }
    local arch; case "$(uname -m)" in
        x86_64|amd64) arch=x86_64 ;;
        aarch64|arm64) arch=aarch64 ;;
        *) MANUAL_TODO+=("herdr -> https://github.com/herdrdev/herdr/releases"); return 1 ;;
    esac
    install_gh_release_bin "herdrdev/herdr" "herdr" "herdr-linux-${arch}" ""
}

TOOLS_EXTRA_NAMES=(alacritty omp-manager tldr duf gpg-tui termusic vortix wlctl lazygit lazydocker k9s termscp lnav dust yazi fastfetch bottom gping trippy bandwhich bat slumber mangofetch gonzo keyward lazyssh herdr ide isd)

tool_desc() {
    case "$1" in
        alacritty) echo "GPU-терминал (тема alacritty-theme ставится отдельно, в setup.sh)" ;;
        omp-manager) echo "TUI-мастер настройки Oh My Posh: темы, шрифты, шеллы (сам Oh My Posh — в setup.sh)" ;;
        tldr)     echo "Короткие практические примеры для команд вместо полного man" ;;
        duf)      echo "Диски и точки монтирования — наглядная замена df" ;;
        gpg-tui)  echo "Управление ключами GnuPG" ;;
        termusic) echo "Терминальный музыкальный плеер" ;;
        vortix)   echo "TUI для WireGuard/OpenVPN: телеметрия, kill switch, утечки DNS/IPv6" ;;
        wlctl)    echo "TUI для wifi/ethernet/vpn через NetworkManager (только Linux)" ;;
        lazygit)  echo "TUI для git" ;;
        lazydocker) echo "TUI для docker и docker-compose" ;;
        k9s)      echo "TUI для Kubernetes-кластера" ;;
        termscp)  echo "Терминальный SCP/SFTP/FTP/S3-клиент" ;;
        lnav)     echo "Просмотр и анализ логов с подсветкой и SQL-запросами" ;;
        dust)     echo "Наглядная замена du — что занимает место на диске" ;;
        yazi)     echo "Быстрый терминальный файловый менеджер" ;;
        fastfetch) echo "Информация о системе при старте терминала (замена neofetch)" ;;
        bottom)   echo "Монитор процессов/ресурсов (замена top/htop), бинарь btm" ;;
        gping)    echo "ping с графиком задержки в реальном времени" ;;
        trippy)   echo "traceroute + ping в одном TUI, бинарь trip" ;;
        bandwhich) echo "Кто из процессов сколько сетевого трафика потребляет" ;;
        bat)      echo "cat с подсветкой синтаксиса и git-диффом (на Debian/Ubuntu бинарь batcat)" ;;
        slumber)  echo "Терминальный REST/gRPC-клиент (замена Postman/Insomnia в TUI)" ;;
        mangofetch) echo "TUI-загрузчик медиа (YouTube, torrent, SoundCloud, Instagram) поверх yt-dlp/ffmpeg" ;;
        gonzo)    echo "TUI для анализа логов в реальном времени (k9s-стиль), нативная поддержка Kubernetes и OTLP" ;;
        keyward)  echo "TUI для управления SSH-ключами, ~/.ssh/config, аудита безопасности и шифрованных бэкапов" ;;
        lazyssh)  echo "TUI для SSH-подключений в стиле lazydocker/k9s" ;;
        herdr)    echo "Агенто-осведомлённый мультиплексор терминала для coding-агентов (herdr.dev)" ;;
        ide)      echo "Neovim IDE — диалог выбора: AstroNvim / NvChad / LunarVim / очистить редактор" ;;
        isd)      echo "TUI для systemd-юнитов: fuzzy-поиск, автообновляемый предпросмотр, умный sudo (только Linux)" ;;
        *) return 1 ;;
    esac
}

# tool_url <имя> — первоисточник: git-репозиторий, а если его нет — сайт
# разработчика. Используется в `./tools-extra.sh --list`.
tool_url() {
    case "$1" in
        alacritty) echo "https://github.com/alacritty/alacritty" ;;
        omp-manager) echo "https://github.com/psmux/omp-manager" ;;
        tldr)      echo "https://github.com/tealdeer-rs/tealdeer" ;;
        duf)       echo "https://github.com/muesli/duf" ;;
        gpg-tui)   echo "https://github.com/orhun/gpg-tui" ;;
        termusic)  echo "https://github.com/tramhao/termusic" ;;
        vortix)    echo "https://github.com/Harry-kp/vortix" ;;
        wlctl)     echo "https://github.com/aashish-thapa/wlctl" ;;
        lazygit)   echo "https://github.com/jesseduffield/lazygit" ;;
        lazydocker) echo "https://github.com/jesseduffield/lazydocker" ;;
        k9s)       echo "https://github.com/derailed/k9s" ;;
        termscp)   echo "https://github.com/veeso/termscp" ;;
        lnav)      echo "https://github.com/tstack/lnav" ;;
        dust)      echo "https://github.com/bootandy/dust" ;;
        yazi)      echo "https://github.com/sxyazi/yazi" ;;
        fastfetch) echo "https://github.com/fastfetch-cli/fastfetch" ;;
        bottom)    echo "https://github.com/ClementTsang/bottom" ;;
        gping)     echo "https://github.com/orf/gping" ;;
        trippy)    echo "https://github.com/fujiapple852/trippy" ;;
        bandwhich) echo "https://github.com/imsnif/bandwhich" ;;
        bat)       echo "https://github.com/sharkdp/bat" ;;
        slumber)   echo "https://github.com/LucasPickering/slumber" ;;
        mangofetch) echo "https://github.com/julesklord/mangofetch" ;;
        gonzo)     echo "https://github.com/control-theory/gonzo" ;;
        keyward)   echo "https://github.com/gateway-of-last-resort/keyward" ;;
        lazyssh)   echo "https://github.com/Adembc/lazyssh" ;;
        herdr)     echo "https://herdr.dev" ;;
        ide)       echo "https://docs.astronvim.com/ | https://nvchad.com/docs/quickstart/install | https://www.lunarvim.org/docs/installation" ;;
        isd)       echo "https://github.com/kainctl/isd" ;;
        *) return 1 ;;
    esac
}

# tool_lang <имя> — основной язык реализации. "ide" — не программа, а
# диалог выбора между тремя (у каждой свой язык, см. tool_url), поэтому
# честного одного ответа для него нет.
tool_lang() {
    case "$1" in
        alacritty) echo "Rust" ;;
        omp-manager) echo "Rust" ;;
        tldr)      echo "Rust (tealdeer)" ;;
        duf)       echo "Go" ;;
        gpg-tui)   echo "Rust" ;;
        termusic)  echo "Rust" ;;
        vortix)    echo "Rust" ;;
        wlctl)     echo "Rust" ;;
        lazygit)   echo "Go" ;;
        lazydocker) echo "Go" ;;
        k9s)       echo "Go" ;;
        termscp)   echo "Rust" ;;
        lnav)      echo "C++" ;;
        dust)      echo "Rust" ;;
        yazi)      echo "Rust" ;;
        fastfetch) echo "C" ;;
        bottom)    echo "Rust" ;;
        gping)     echo "Rust" ;;
        trippy)    echo "Rust" ;;
        bandwhich) echo "Rust" ;;
        bat)       echo "Rust" ;;
        slumber)   echo "Rust" ;;
        mangofetch) echo "Rust" ;;
        gonzo)     echo "Go" ;;
        keyward)   echo "Go" ;;
        lazyssh)   echo "Go" ;;
        herdr)     echo "Rust" ;;
        ide)       echo "разное (Lua-конфиги)" ;;
        isd)       echo "Python" ;;
        *) return 1 ;;
    esac
}

# tool_os <имя> — какие ОС поддерживает install_tool() для этого инструмента
# (не про сам проект вообще — bandwhich, например, кросс-платформенный сам
# по себе, но в install_tool() ставится только там, где у него есть
# пакет/бинарь через уже реализованные пути). Используется в
# `./tools-extra.sh --list`.
tool_os() {
    case "$1" in
        wlctl) echo "только Linux (нужен NetworkManager)" ;;
        isd)   echo "только Linux (нужен systemd)" ;;
        alacritty|omp-manager|tldr|duf|gpg-tui|termusic|vortix|lazygit|lazydocker|k9s|termscp|lnav|dust|yazi|fastfetch|bottom|gping|trippy|bandwhich|bat|slumber|mangofetch|gonzo|keyward|lazyssh|herdr|ide)
            echo "macOS + Linux" ;;
        *) return 1 ;;
    esac
}

# install_tool <имя> — диспетчер: часть инструментов ставится дженериком
# pkg_or_cargo, часть (lazygit/lazydocker/k9s/fastfetch) — через свою функцию
# из-за пробелов в apt/dnf у соответствующих проектов на конец 2026.
install_tool() {
    local name="$1"
    case "$name" in
        alacritty) install_alacritty ;;
        omp-manager) install_omp_manager ;;
        tldr)      pkg_or_cargo tldr     tealdeer  tldr   tldr tldr tldr tealdeer "" ;;
        duf)       pkg_or_cargo duf      ""        duf    duf  duf  duf  duf      "" ;;
        gpg-tui)   pkg_or_cargo gpg-tui  gpg-tui   gpg-tui "" "" gpg-tui gpg-tui gpg-tui ;;
        termusic)  pkg_or_cargo termusic termusic  termusic "" "" termusic "" "" ;;
        vortix)    pkg_or_cargo vortix vortix vortix "" "" vortix "" "" ;;
        wlctl)
            if [[ "$OS" == "linux" ]]; then
                pkg_or_cargo wlctl wlctl "" "" "" "" "" ""
            else
                info "wlctl использует NetworkManager, есть только на Linux — пропускаю на macOS"
            fi ;;
        lazygit)   install_lazygit ;;
        lazydocker) install_lazydocker ;;
        k9s)       install_k9s ;;
        termscp)   pkg_or_cargo termscp termscp termscp "" "" termscp termscp "" ;;
        lnav)      pkg_or_cargo lnav     ""      lnav   lnav lnav lnav lnav lnav ;;
        dust)      pkg_or_cargo dust     du-dust dust   ""   du-dust dust dust dust ;;
        yazi)      install_yazi ;;
        fastfetch) install_fastfetch ;;
        bottom)    pkg_or_cargo btm      bottom  bottom ""   ""   bottom bottom bottom ;;
        gping)     pkg_or_cargo gping    gping   gping  gping ""  gping gping gping ;;
        trippy)    pkg_or_cargo trip     trippy  trippy ""   ""   trippy trippy "" ;;
        bandwhich) pkg_or_cargo bandwhich bandwhich bandwhich "" "" bandwhich "" bandwhich ;;
        bat)       pkg_or_cargo bat      ""      bat    bat  bat  bat  bat  bat ;;
        slumber)   pkg_or_cargo slumber  slumber slumber "" "" slumber "" "" ;;
        mangofetch) pkg_or_cargo mangofetch mangofetch "" "" "" "" "" "" ;;
        gonzo)     install_gonzo ;;
        keyward)   install_keyward ;;
        lazyssh)   install_lazyssh ;;
        herdr)     install_herdr ;;
        ide)       install_ide ;;
        isd)       install_isd ;;
        *) err "Неизвестный инструмент: $name"; return 1 ;;
    esac
}
