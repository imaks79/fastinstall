#!/usr/bin/env bash
# Чекбокс-список для выбора пакетов/инструментов перед установкой — тот же
# классический синий TUI-диалог (ncurses `dialog`), что в debconf/
# dpkg-reconfigure, Clonezilla live или установщике Ubuntu Server: стрелки —
# перемещение, Пробел — отметить/снять пункт, Enter — подтвердить, Esc/Cancel
# — отмена. Пользователь ничего не печатает и не подбирает номера руками.
#
# `dialog` ставится этим же файлом при первом обращении (через pkg_native из
# lib/packages.sh, доступен в apt/dnf/pacman/zypper/apk и в Homebrew). Если
# поставить не удалось (нет сети/прав, нет TERM) — тихо откатываемся на
# простой пронумерованный список (без ncurses), чтобы выбор пакетов работал
# в любом окружении, а не превращался в жёсткую зависимость.
#
# macOS-нюанс: формула Homebrew собирает dialog флагом `./configure
# --with-ncurses` (без 'w') и `uses_from_macos "ncurses"` — то есть линкует
# его с однобайтовой системной /usr/lib/libncurses.5.4.dylib (наследие ещё
# Tiger), а не с широкой Homebrew-ncursesw. Однобайтовый dialog не понимает
# многобайтовый UTF-8 и вместо кириллицы в описаниях пунктов рисует мусор
# вроде "~R~Кбе~ди~Ве" (каждый байт UTF-8-последовательности пропускается
# через таблицу псевдографики). На Linux дистрибутивный dialog обычно уже
# линкован с ncursesw, поэтому там этой проблемы нет. См.
# tui_build_dialog_widec_macos() ниже — она на лету собирает свою
# UTF-8-совместимую сборку dialog против уже стоящей Homebrew-ncurses, не
# трогая сам пакет dialog.

TUI_BACKEND=""
TUI_UTF8_LOCALE=""
TUI_DIALOG_BIN=""
TUI_DIALOG_WIDEC_PREFIX="$HOME/.cache/fastinstall/dialog-widec"

# tui_utf8_locale — печатает имя UTF-8-локали для запуска dialog. Без неё
# ncurses не знает, что описания пунктов (кириллица) — многобайтовый UTF-8,
# и вместо букв рисует мусор вроде "~X" (побайтовый разбор — обычная
# ситуация в минимальных Docker-образах и подобных окружениях, где LANG не
# задан вообще или задан как POSIX/C). Обычный echo/printf эту локаль не
# спрашивает и поэтому не ломается — страдает только ncurses-диалог.
tui_utf8_locale() {
    if [[ -n "$TUI_UTF8_LOCALE" ]]; then
        printf '%s' "$TUI_UTF8_LOCALE"
        return
    fi

    local candidate
    for candidate in "${LC_ALL:-}" "${LC_CTYPE:-}" "${LANG:-}"; do
        if [[ "$candidate" == *[Uu][Tt][Ff]-8* || "$candidate" == *[Uu][Tt][Ff]8* ]]; then
            TUI_UTF8_LOCALE="$candidate"
            printf '%s' "$TUI_UTF8_LOCALE"
            return
        fi
    done

    if command -v locale >/dev/null 2>&1; then
        candidate="$(locale -a 2>/dev/null | grep -i -m1 -E 'utf-?8$')"
        if [[ -n "$candidate" ]]; then
            TUI_UTF8_LOCALE="$candidate"
            printf '%s' "$TUI_UTF8_LOCALE"
            return
        fi
    fi

    # locale -a ничего не нашла (нет утилиты, локали не сгенерены и т.п.) —
    # C.UTF-8 в современном glibc работает "из коробки" без locale-gen,
    # пробуем её как последний шанс, хуже не будет.
    TUI_UTF8_LOCALE="C.UTF-8"
    printf '%s' "$TUI_UTF8_LOCALE"
}

# tui_dialog_is_widec <путь-к-бинарю> — проверяет, что dialog линкован с
# многобайтовой (wide) ncurses, а не с однобайтовой. На Linux не проверяем
# (там это почти никогда не проблема) — считаем любой найденный dialog годным.
tui_dialog_is_widec() {
    local bin="$1"
    [[ -x "$bin" ]] || return 1
    [[ "$OS" == "macos" ]] || return 0
    command -v otool >/dev/null 2>&1 || return 0
    otool -L "$bin" 2>/dev/null | grep -qi 'libncursesw'
}

# tui_build_dialog_widec_macos — собирает dialog из тех же исходников, что и
# Homebrew-формула (та же версия, invisible-mirror.net), но с флагом
# --with-ncursesw против уже установленной keg-only Homebrew-ncurses (там
# есть широкая libncursesw, в отличие от системной macOS-ncurses). Кладёт
# результат в TUI_DIALOG_WIDEC_PREFIX, сам пакет dialog не трогает. При
# успехе печатает путь к рабочему бинарю и возвращает 0.
tui_build_dialog_widec_macos() {
    local target="$TUI_DIALOG_WIDEC_PREFIX/bin/dialog"
    if tui_dialog_is_widec "$target"; then
        printf '%s' "$target"
        return 0
    fi

    command -v brew >/dev/null 2>&1 || return 1
    command -v cc >/dev/null 2>&1 || return 1

    local ncurses_prefix
    ncurses_prefix="$(brew --prefix ncurses 2>/dev/null)"
    if [[ -z "$ncurses_prefix" || ! -d "$ncurses_prefix/lib/pkgconfig" ]]; then
        brew install ncurses >/dev/null 2>&1
        ncurses_prefix="$(brew --prefix ncurses 2>/dev/null)"
    fi
    [[ -n "$ncurses_prefix" && -d "$ncurses_prefix/lib/pkgconfig" ]] || return 1

    local ver
    ver="$(brew list --versions dialog 2>/dev/null | awk '{print $2}')"
    [[ -n "$ver" ]] || ver="1.3-20260721"

    # info/warn/ok здесь и ниже — все с явным >&2: результат этой функции
    # возвращается через "печатает путь в stdout" (см. вызывающий код,
    # widec_bin="$(tui_build_dialog_widec_macos)"), и без >&2 текст этих
    # сообщений попал бы в тот же stdout, испортив возвращаемый путь.
    info "Homebrew-сборка dialog не понимает UTF-8 (кириллица в чеклисте будет мусором) — собираю свою UTF-8-совместимую сборку dialog $ver поверх Homebrew-ncursesw..." >&2
    local tmp; tmp="$(mktemp -d)"
    if ! curl -fsSL -o "$tmp/dialog.tgz" "https://invisible-mirror.net/archives/dialog/dialog-${ver}.tgz"; then
        warn "Не удалось скачать исходники dialog $ver" >&2
        rm -rf "$tmp"
        return 1
    fi
    tar -xzf "$tmp/dialog.tgz" -C "$tmp"
    local srcdir="$tmp/dialog-${ver}"
    [[ -d "$srcdir" ]] || srcdir="$(find "$tmp" -maxdepth 1 -type d -name 'dialog-*' | head -1)"
    if [[ -z "$srcdir" || ! -d "$srcdir" ]]; then
        warn "Не нашёл распакованные исходники dialog" >&2
        rm -rf "$tmp"
        return 1
    fi

    rm -rf "$TUI_DIALOG_WIDEC_PREFIX"
    if ! (
        cd "$srcdir" &&
        PKG_CONFIG_PATH="$ncurses_prefix/lib/pkgconfig" \
        CPPFLAGS="-I$ncurses_prefix/include" \
        LDFLAGS="-L$ncurses_prefix/lib" \
        ./configure --prefix="$TUI_DIALOG_WIDEC_PREFIX" --with-ncursesw >/dev/null 2>&1 &&
        make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 2)" install-full >/dev/null 2>&1
    ); then
        warn "Сборка UTF-8-совместимого dialog не удалась" >&2
        rm -rf "$tmp"
        return 1
    fi
    rm -rf "$tmp"

    if tui_dialog_is_widec "$target"; then
        ok "Собран UTF-8-совместимый dialog: $target" >&2
        printf '%s' "$target"
        return 0
    fi
    warn "Собранный dialog всё равно не линкуется с ncursesw" >&2
    return 1
}

# tui_ensure_dialog — гарантирует, что рабочий (понимающий UTF-8) dialog
# доступен, ставит/собирает при необходимости. Возвращает 0 и заполняет
# TUI_DIALOG_BIN путём к бинарю, если dialog можно использовать, 1 — если
# нет (используем упрощённый список-фолбэк).
tui_ensure_dialog() {
    case "$TUI_BACKEND" in
        dialog) return 0 ;;
        none)   return 1 ;;
    esac

    if [[ -z "${TERM:-}" ]]; then
        TUI_BACKEND="none"
        return 1
    fi

    if ! command -v dialog >/dev/null 2>&1; then
        info "Ставлю dialog (нужен для TUI-диалога выбора пакетов)..."
        if pkg_native dialog dialog dialog dialog dialog dialog >/dev/null 2>&1 && command -v dialog >/dev/null 2>&1; then
            ok "dialog установлен"
        else
            warn "dialog поставить не удалось — использую упрощённый список выбора (без стрелок/пробела)"
            TUI_BACKEND="none"
            return 1
        fi
    fi

    TUI_DIALOG_BIN="$(command -v dialog)"

    if [[ "$OS" == "macos" ]] && ! tui_dialog_is_widec "$TUI_DIALOG_BIN"; then
        local widec_bin
        if widec_bin="$(tui_build_dialog_widec_macos)"; then
            TUI_DIALOG_BIN="$widec_bin"
        else
            warn "Homebrew-версия dialog не понимает UTF-8, а свою UTF-8-сборку сделать не удалось (нет сети или инструментов сборки) — использую упрощённый список выбора"
            TUI_BACKEND="none"
            return 1
        fi
    fi

    TUI_BACKEND="dialog"
    return 0
}

# tui_checklist <заголовок> <имя1> <описание1> [имя2 описание2 ...]
# По умолчанию все пункты отмечены. При подтверждении заполняет глобальный
# массив TUI_SELECTED именами отмеченных пунктов (в исходном порядке) и
# возвращает 0. При отмене возвращает 1, TUI_SELECTED очищается.
tui_checklist() {
    local title="$1"; shift
    if tui_ensure_dialog; then
        tui_checklist_dialog "$title" "$@"
    else
        tui_checklist_plain "$title" "$@"
    fi
}

# Настоящий ncurses-диалог: стрелки/Tab — навигация, Пробел — отметить/снять,
# Enter — OK, Esc или кнопка Cancel — отмена.
tui_checklist_dialog() {
    local title="$1"; shift
    local dialog_items=()
    while [[ $# -gt 0 ]]; do
        dialog_items+=("$1" "$2" "on")
        shift 2
    done

    local utf8_locale; utf8_locale="$(tui_utf8_locale)"
    local dialog_bin="${TUI_DIALOG_BIN:-dialog}"
    local tmpfile; tmpfile="$(mktemp)"
    local exit_status
    if LC_ALL="$utf8_locale" LANG="$utf8_locale" "$dialog_bin" --backtitle "fastinstall" \
               --title "$title" \
               --checklist "Пробел — отметить/снять пункт, Enter — установить отмеченное, Esc/Cancel — отмена" \
               0 0 0 \
               "${dialog_items[@]}" \
               2>"$tmpfile"; then
        exit_status=0
    else
        exit_status=$?
    fi
    clear 2>/dev/null || true

    if [[ "$exit_status" -ne 0 ]]; then
        rm -f "$tmpfile"
        TUI_SELECTED=()
        return 1
    fi

    local raw
    raw="$(<"$tmpfile")"
    rm -f "$tmpfile"
    raw="${raw//\"/}"
    TUI_SELECTED=()
    [[ -n "$raw" ]] && read -r -a TUI_SELECTED <<< "$raw"
    return 0
}

# Фолбэк без ncurses (нет dialog и не удалось поставить, либо нет TERM) —
# номера через пробел/запятую переключают отметку. Массивы индексные, не
# ассоциативные — bash 3.2 (системный /bin/bash на macOS) declare -A не
# поддерживает.
tui_checklist_plain() {
    local title="$1"; shift
    local names=() descs=() checked=()
    while [[ $# -gt 0 ]]; do
        names+=("$1"); descs+=("$2"); checked+=(1)
        shift 2
    done
    local n=${#names[@]} i choice tok

    while true; do
        clear 2>/dev/null || true
        printf '%s\n\n' "$title"
        for ((i = 0; i < n; i++)); do
            if [[ "${checked[i]}" == "1" ]]; then
                printf '  %s[x]%s %2d) %-24s %s\n' "$C_GREEN" "$C_RESET" "$((i + 1))" "${names[i]}" "${descs[i]}"
            else
                printf '  [ ] %2d) %-24s %s\n' "$((i + 1))" "${names[i]}" "${descs[i]}"
            fi
        done
        echo
        echo "Номера через пробел/запятую — переключить отметку."
        echo "a — отметить всё, n — снять все отметки, Enter — установить отмеченное, q — отмена."
        if ! read -r -p "> " choice; then
            echo
            TUI_SELECTED=()
            return 1
        fi

        case "$choice" in
            "") break ;;
            q|Q) TUI_SELECTED=(); return 1 ;;
            a|A) for ((i = 0; i < n; i++)); do checked[i]=1; done ;;
            n|N) for ((i = 0; i < n; i++)); do checked[i]=0; done ;;
            *)
                for tok in ${choice//,/ }; do
                    if [[ "$tok" =~ ^[0-9]+$ ]] && (( tok >= 1 && tok <= n )); then
                        i=$((tok - 1))
                        if [[ "${checked[i]}" == "1" ]]; then checked[i]=0; else checked[i]=1; fi
                    else
                        warn "Не понял '$tok', пропускаю"
                    fi
                done
                ;;
        esac
    done

    TUI_SELECTED=()
    for ((i = 0; i < n; i++)); do
        [[ "${checked[i]}" == "1" ]] && TUI_SELECTED+=("${names[i]}")
    done
    return 0
}
