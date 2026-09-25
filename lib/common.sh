#!/usr/bin/env bash
# Общие хелперы: логирование, определение ОС/пакетного менеджера, симлинки.

C_RESET=$'\033[0m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_BLUE=$'\033[34m'; C_MAGENTA=$'\033[35m'

info()  { printf '%s[*]%s %s\n' "$C_BLUE"   "$C_RESET" "$*"; }
ok()    { printf '%s[+]%s %s\n' "$C_GREEN"  "$C_RESET" "$*"; }
warn()  { printf '%s[!]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
err()   { printf '%s[x]%s %s\n' "$C_RED"    "$C_RESET" "$*" >&2; }

MANUAL_TODO=()
FAILED_STEPS=()

# retry <попыток> <команда...>
# Повторяет команду при неудаче с паузой между попытками (3с, 6с, 9с...).
# Нужно для шагов, которые тянут что-то по сети (git clone, curl-установщики) —
# на свежей машине (только что поднятый VM/контейнер) сеть иногда не готова
# ещё пару секунд, DNS не разрешается с первого раза и т.п. — временный сбой,
# не ошибка конфигурации.
retry() {
    local attempts="$1"; shift
    local i=1
    while true; do
        if "$@"; then return 0; fi
        if [[ "$i" -ge "$attempts" ]]; then return 1; fi
        warn "Попытка $i/$attempts не удалась, повтор через $((i * 3))с..."
        sleep "$((i * 3))"
        i=$((i + 1))
    done
}

# Префикс для привилегированных команд. Если мы уже root (частый случай в
# минимальных Docker-образах, где sudo вообще не установлен) или sudo нет
# в PATH — выполняем команды напрямую, без него.
if [[ "$(id -u)" -eq 0 ]]; then
    SUDO=""
elif command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
else
    warn "sudo не найден и вы не root — привилегированные шаги ниже могут не сработать"
    SUDO=""
fi

# В некоторых окружениях (минимальные Docker-образы, su без -l) переменная
# $USER не экспортирована, хотя мы прекрасно знаем, кто мы — id -un.
USER="${USER:-$(id -un)}"

# Запускает один шаг установки так, чтобы его провал (недостающий пакет,
# скрипт-установщик отказался ставиться и т.п.) не обрывал set -e весь
# остальной setup.sh — сообщаем и идём дальше.
step() {
    local name="$1"; shift
    if ! "$@"; then
        warn "Шаг '$name' завершился с ошибкой, продолжаю дальше"
        FAILED_STEPS+=("$name")
    fi
}

detect_os() {
    case "$(uname -s)" in
        Darwin) OS="macos" ;;
        Linux)  OS="linux" ;;
        *) err "Неподдерживаемая ОС: $(uname -s). Скрипт рассчитан на macOS и Linux."; exit 1 ;;
    esac

    PKG_MANAGER=""
    if [[ "$OS" == "linux" ]]; then
        if   command -v apt-get >/dev/null 2>&1; then PKG_MANAGER="apt"
        elif command -v dnf     >/dev/null 2>&1; then PKG_MANAGER="dnf"
        elif command -v pacman  >/dev/null 2>&1; then PKG_MANAGER="pacman"
        elif command -v zypper  >/dev/null 2>&1; then PKG_MANAGER="zypper"
        elif command -v apk     >/dev/null 2>&1; then PKG_MANAGER="apk"
        else err "Не удалось определить пакетный менеджер Linux."; exit 1
        fi
    fi
    info "Обнаружена система: $OS${PKG_MANAGER:+ ($PKG_MANAGER)}"
}

# clone_or_update <repo-url> <целевая директория>
clone_or_update() {
    local repo="$1" dir="$2"
    if [[ -d "$dir/.git" ]]; then
        info "Обновляю $dir"
        git -C "$dir" pull --ff-only --quiet || warn "Не удалось обновить $dir, оставляю как есть"
    else
        info "Клонирую $repo -> $dir"
        # На неудачной попытке git обычно сам подчищает частично склонированный
        # каталог, но не гарантированно (прервали процесс, кончилось место) —
        # перед повтором подчищаем сами, иначе git откажется клонировать в
        # непустой каталог.
        retry 3 bash -c '[[ -d "$1" && ! -d "$1/.git" ]] && rm -rf "$1"; git clone --quiet --depth 1 "$2" "$1"' _ "$dir" "$repo"
    fi
}

# ensure_cargo_in_path — подхватывает cargo, если rust уже стоит, но PATH
# этого конкретного bash-процесса про него ещё не знает. Основной сценарий:
# в TUI-диалоге setup.sh сняли галочку с install_rust (rust уже был
# установлен раньше), поэтому в этом прогоне cargo/env никто не source'ил —
# rustc/cargo лежат в ~/.cargo/bin, но в PATH текущего процесса их нет, хотя
# в интерактивном шелле пользователя (через .zshenv/.profile от установщика
# rustup) они обычно есть. Без этого шаги вроде install_omp_manager/
# pkg_or_cargo молча ругаются "cargo не найден" на машине, где rust на самом
# деле стоит.
ensure_cargo_in_path() {
    command -v cargo >/dev/null 2>&1 && return 0
    [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
    command -v cargo >/dev/null 2>&1
}

# cargo_install_clean <крейт...>
# `cargo install`, но подчищает временные каталоги сборки в /tmp — при
# неудаче cargo оставляет /tmp/cargo-install<случайное> навсегда (новое
# случайное имя при каждом вызове, ничего не переиспользуется), и на
# небольшом диске/VM несколько подряд неудачных cargo-сборок (yazi, termscp
# c aws-lc-sys, termusic и т.п. — тяжёлые крейты) быстро приводят к
# "No space left on device", из-за чего валятся уже вообще все следующие
# установки, а не только реально проблемная. Подчищаем и до, и после.
cargo_install_clean() {
    rm -rf /tmp/cargo-install* 2>/dev/null || true
    cargo install "$@"
    local rc=$?
    rm -rf /tmp/cargo-install* 2>/dev/null || true
    return "$rc"
}

# warn_if_low_disk_space [путь] [минимум-в-МБ]
# Rust-сборки тяжёлых крейтов (yazi, termscp, termusic, gpg-tui) требуют
# заметно места во временном каталоге — предупреждаем заранее понятным
# текстом вместо того, чтобы пользователь потом разбирал десятки строк
# "No space left on device" вперемешку с сообщениями компилятора.
warn_if_low_disk_space() {
    local path="${1:-/tmp}" min_mb="${2:-2048}" avail_kb avail_mb
    avail_kb="$(df -Pk "$path" 2>/dev/null | awk 'NR==2{print $4}')"
    [[ -n "$avail_kb" ]] || return 0
    avail_mb=$((avail_kb / 1024))
    if [[ "$avail_mb" -lt "$min_mb" ]]; then
        warn "Мало места на $path: ${avail_mb}МБ свободно (сборка тяжёлых Rust-пакетов может не уложиться) — освободите место или ставьте инструменты по одному"
    fi
}
