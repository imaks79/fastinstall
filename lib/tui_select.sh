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

TUI_BACKEND=""
TUI_UTF8_LOCALE=""

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

# tui_ensure_dialog — гарантирует, что `dialog` доступен, ставит при
# необходимости. Возвращает 0, если dialog можно использовать, 1 — если нет
# (используем упрощённый список-фолбэк).
tui_ensure_dialog() {
    case "$TUI_BACKEND" in
        dialog) return 0 ;;
        none)   return 1 ;;
    esac

    if [[ -z "${TERM:-}" ]]; then
        TUI_BACKEND="none"
        return 1
    fi

    if command -v dialog >/dev/null 2>&1; then
        TUI_BACKEND="dialog"
        return 0
    fi

    info "Ставлю dialog (нужен для TUI-диалога выбора пакетов)..."
    if pkg_native dialog dialog dialog dialog dialog dialog >/dev/null 2>&1 && command -v dialog >/dev/null 2>&1; then
        ok "dialog установлен"
        TUI_BACKEND="dialog"
        return 0
    fi

    warn "dialog поставить не удалось — использую упрощённый список выбора (без стрелок/пробела)"
    TUI_BACKEND="none"
    return 1
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
    local tmpfile; tmpfile="$(mktemp)"
    local exit_status
    if LC_ALL="$utf8_locale" LANG="$utf8_locale" dialog --backtitle "fastinstall" \
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
