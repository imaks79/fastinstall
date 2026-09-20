#!/usr/bin/env bash
# Быстро поднимает общую сетевую папку (SMB/Samba) для каталога — либо
# добавляет/убирает пользователя у уже существующей шары, либо удаляет
# шару целиком.
#
# Использование:
#   ./samba-share.sh [опции] [путь-к-папке]
#   ./samba-share.sh -d -n ИМЯ                 удалить шару ИМЯ целиком
#   ./samba-share.sh -x -n ИМЯ -u ЮЗЕР         убрать доступ ЮЗЕР к шаре ИМЯ
#
# Опции:
#   -n, --name ИМЯ        имя шары. Путь необязателен: если не указан и
#                         шары с таким именем ещё нет — каталог создаётся в
#                         /srv/samba/ИМЯ (macOS: /Users/Shared/ИМЯ); если
#                         шара уже существует — берётся её реальный путь.
#   -u, --user ЮЗЕР       кому дать доступ (по умолчанию — текущий пользователь;
#                        для -x/--remove-user умолчания нет, указывать обязательно)
#   -p, --password ПАРОЛЬ пароль Samba, ставится неинтерактивно (без TTY и без
#                        этой опции создание пароля пропускается, см. MANUAL_TODO)
#   -g, --guest           разрешить гостевой доступ без пароля
#   -r, --readonly        общий доступ только на чтение
#   -d, --delete          удалить шару -n ИМЯ целиком (только Linux, см. ниже)
#   -x, --remove-user     убрать доступ -u ЮЗЕР к шаре -n ИМЯ, не трогая
#                        саму шару и остальных её участников (только Linux)
#   -h, --help             эта справка
#
# Повторный запуск идемпотентен — "запустил и забыл": "./samba-share.sh -n
# ИМЯ" на уже существующей шаре ничего не пересоздаёт и не ломает, а
# "./samba-share.sh -n ИМЯ -u НОВЫЙ -p ПАРОЛЬ" добавляет ещё одного
# пользователя к той же шаре, не трогая остальных.
#
# -x/--remove-user убирает пользователя из группы шары (доступ пропадает
# сразу); если у него после этого SMB-only шелл (nologin/false) и не
# осталось доступа ни к одной другой шаре — учётка удаляется целиком
# (включая запись в базе Samba), как и при -d/--delete — см. ниже правила.
#
# Linux: ставит пакет samba, добавляет секцию в /etc/samba/smb.conf
# (с бэкапом), создаёт учётку в базе Samba (smbpasswd) и включает/
# перезапускает smbd, открывает порт в ufw/firewalld при их наличии.
#
# У КАЖДОЙ шары — своя unix-группа (smbshare-ИМЯ), доступ в конфиге прописан
# как "valid users = @smbshare-ИМЯ" — поэтому чтобы дать доступ ещё одному
# пользователю, smb.conf трогать не нужно: скрипт просто добавляет его в
# эту группу (создавая SMB-only учётку, если пользователя ещё нет).
#
# Владелец каталога шары — root (не конкретный пользователь): реальный
# доступ и так через группу, root просто нейтральный владелец, который не
# удаляется и не оставит "осиротевший" UID, если владевшего юзера потом
# снесут через -d. Для негостевых шар права каталога — 2770 (rwxrws---):
# доступ строго владельцу и группе, у остальных пользователей системы
# (даже с локальным шеллом на этой машине, не по SMB) — никакого доступа.
# Для гостевых шар (-g) так нельзя (гостевое подключение в Samba маппится
# на отдельную unix-учётку вроде nobody, не состоящую в группах шар) —
# там права каталога остаются 2775.
#
# Если пользователь из -u/--user не существует в системе — Linux-версия
# создаёт его сама, ТОЛЬКО для доступа по SMB (без входа в систему):
#   useradd -M -N -G smbshare-ИМЯ -s <nologin> ЮЗЕР
# -M (без домашнего каталога), -s <nologin> (вход по SSH/консоли запрещён,
# путь ищется среди /usr/sbin/nologin, /sbin/nologin, /usr/bin/nologin — по
# наличию на конкретном дистрибутиве). Если пользователь уже существует —
# он не трогается, только добавляется в группу этой шары.
#
# Удаление (-d -n ИМЯ): убирает секцию из smb.conf и unix-группу шары. Для
# каждого участника этой группы: членство в НЕЙ убирается всегда; если
# после этого у пользователя не осталось доступа ни к одной другой шаре
# (других групп smbshare-*) И его шелл — заглушка (nologin/false, то есть
# это SMB-only учётка, созданная этим скриптом) — пользователь удаляется
# целиком (userdel, плюс запись в базе Samba чистится через smbpasswd -x).
# Пользователь с обычным логин-шеллом НЕ удаляется никогда, у него только
# вычищается членство в группе именно этой шары — так же он не удаляется,
# если у него остался доступ к другим шарам. Файлы самой шары на диске не
# трогаются — путь к ним выводится в конце, удалять вручную, если больше
# не нужны.
#
# macOS: создаёт share point через штатную утилиту `sharing` (то же, что
# стоит за System Settings -> General -> Sharing -> File Sharing). Сам
# тумблер "File Sharing" и первичное подтверждение пароля пользователя для
# SMB Apple не даёт включить из терминала — это остаётся ручным шагом,
# скрипт выведет точную подсказку в конце. Пер-шаровые группы и удаление
# (-d) на macOS не реализованы — доступ по-прежнему через общую группу
# com.apple.access_smb, пользователь должен существовать заранее.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/packages.sh"

usage() {
    sed -n '2,82p' "$0" | sed 's/^# \{0,1\}//'
}

SHARE_NAME=""
SHARE_USER="${USER:-$(id -un)}"
SHARE_PASSWORD=""
GUEST_OK="no"
READ_ONLY="no"
SHARE_PATH=""
DELETE_SHARE="no"
REMOVE_USER="no"
SHARE_USER_SET="no"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--name)     SHARE_NAME="$2"; shift 2 ;;
        -u|--user)     SHARE_USER="$2"; SHARE_USER_SET="yes"; shift 2 ;;
        -p|--password) SHARE_PASSWORD="$2"; shift 2 ;;
        -g|--guest)    GUEST_OK="yes"; shift ;;
        -r|--readonly) READ_ONLY="yes"; shift ;;
        -d|--delete)   DELETE_SHARE="yes"; shift ;;
        -x|--remove-user) REMOVE_USER="yes"; shift ;;
        -h|--help)     usage; exit 0 ;;
        -*) err "Неизвестная опция: $1"; usage; exit 1 ;;
        *) SHARE_PATH="$1"; shift ;;
    esac
done

[[ -n "$SHARE_PASSWORD" ]] && warn "-p/--password: пароль будет виден в 'ps' и, возможно, в истории шелла на этой машине"

detect_os
case "$OS" in
    linux) SMB_ROOT="/srv/samba" ;;
    macos) SMB_ROOT="/Users/Shared" ;;
esac

SMB_CONF_LINUX="/etc/samba/smb.conf"
SMB_GROUP_PREFIX="smbshare-"

# Имя unix-группы для шары ИМЯ — детерминированно (одно и то же ИМЯ всегда
# даёт одну и ту же группу), используется и при создании, и при удалении.
# Санитизация: unix-группа допускает только [a-z0-9_-], лимит длины имени —
# 32 символа (историческое ограничение utmp, но useradd/groupadd на многих
# системах до сих пор его проверяют) — при переполнении явно отказываем, а
# не молча обрезаем (обрезка могла бы склеить две РАЗНЫЕ шары в одну группу).
share_group_name() {
    local raw="$1" n
    n="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '-' | sed -E 's/-+/-/g; s/^-|-$//g')"
    [[ -n "$n" ]] || n="share"
    if [[ ${#n} -gt $((32 - ${#SMB_GROUP_PREFIX})) ]]; then
        err "Имя шары '$raw' слишком длинное для имени unix-группы (лимит ${SMB_GROUP_PREFIX}+имя <= 32 символов) — укажите короче через -n"
        exit 1
    fi
    printf '%s%s' "$SMB_GROUP_PREFIX" "$n"
}

# Достаёт "path = ..." из уже существующей секции [ИМЯ] в smb.conf, если
# такая секция есть. Нужно, чтобы повторный запуск с тем же -n находил
# РЕАЛЬНЫЙ путь шары (в т.ч. кастомный, заданный явным путём при первом
# создании), а не создавал новый пустой каталог под $SMB_ROOT с тем же
# именем. Пусто на stdout = секция или путь не найдены.
smb_conf_extract_path() {
    local name="$1"
    [[ -f "$SMB_CONF_LINUX" ]] || return 0
    awk -v s="[$name]" '
        $0==s {infile=1; next}
        infile && /^\[/ {exit}
        infile && $1=="path" && $2=="=" {
            out=$3; for (i=4;i<=NF;i++) out=out" "$i
            print out; exit
        }
    ' "$SMB_CONF_LINUX"
}

# Достаёт "directory mask = ..." из секции [ИМЯ] — используется, чтобы
# понять, устарели ли маски у уже существующей шары (созданной раньше, с
# другими правами), и обновлять smb.conf, только когда значение реально
# отличается — не плодить бэкап и лишнюю запись на каждый запуск.
smb_conf_current_dir_mask() {
    local name="$1"
    [[ -f "$SMB_CONF_LINUX" ]] || return 0
    awk -v s="[$name]" '
        $0==s {infile=1; next}
        infile && /^\[/ {exit}
        infile && $1=="directory" && $2=="mask" && $3=="=" {print $4; exit}
    ' "$SMB_CONF_LINUX"
}

# Переписывает "create mask"/"directory mask" внутри уже существующей
# секции [ИМЯ] на новые значения, не трогая остальные строки секции и
# остальные секции файла.
smb_conf_update_masks() {
    local name="$1" create_mask="$2" dir_mask="$3" tmp
    tmp="$(mktemp)"
    awk -v s="[$name]" -v cm="$create_mask" -v dm="$dir_mask" '
        $0==s {print; infile=1; next}
        infile && /^\[/ {infile=0}
        infile && $1=="create" && $2=="mask" && $3=="=" {print "    create mask = " cm; next}
        infile && $1=="directory" && $2=="mask" && $3=="=" {print "    directory mask = " dm; next}
        {print}
    ' "$SMB_CONF_LINUX" > "$tmp"
    $SUDO cp "$tmp" "$SMB_CONF_LINUX"
    rm -f "$tmp"
}

# На Debian/Ubuntu у обычного (не root) пользователя /usr/sbin по умолчанию
# НЕ входит в PATH (в отличие от root и от secure_path sudo) — поэтому
# `command -v smbd` из-под непривилегированного пользователя не находит уже
# установленный бинарь. Проверяем PATH и типичные sbin-каталоги напрямую.
find_sbin() {
    local name="$1" p
    command -v "$name" 2>/dev/null && return 0
    for p in "/usr/sbin/$name" "/sbin/$name" "/usr/local/sbin/$name"; do
        [[ -x "$p" ]] && { echo "$p"; return 0; }
    done
    return 1
}

# Путь к shell'у-заглушке, запрещающему интерактивный вход, отличается по
# дистрибутивам (Debian/Arch — /usr/sbin/nologin, RHEL/CentOS часто —
# /sbin/nologin) — перебираем известные варианты, /bin/false в конце как
# гарантированно существующий, хоть и с менее внятным сообщением при попытке войти.
find_nologin_shell() {
    local p
    for p in /usr/sbin/nologin /sbin/nologin /usr/bin/nologin /bin/false; do
        [[ -x "$p" ]] && { echo "$p"; return 0; }
    done
    echo "/bin/false"
}

ensure_share_group_linux() {
    local group="$1"
    getent group "$group" >/dev/null 2>&1 && return 0
    info "Создаю группу $group для шары $SHARE_NAME"
    $SUDO groupadd "$group"
}

# Готовит доступ $SHARE_USER к шаре: создаёт unix-группу шары (если нужно),
# и либо создаёт нового SMB-only пользователя сразу в этой группе, либо, если
# пользователь уже существует (свой или чужой, ранее созданный), просто
# добавляет его в группу (usermod -aG), ничего больше не трогая. Именно
# через этот путь работает "добавить пользователя к существующей шаре" —
# smb.conf при этом не меняется, т.к. доступ там прописан как @группа.
ensure_smb_user_linux() {
    local group="$1"
    ensure_share_group_linux "$group"

    if id "$SHARE_USER" >/dev/null 2>&1; then
        if id -nG "$SHARE_USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$group"; then
            ok "Пользователь $SHARE_USER уже в группе $group"
        else
            info "Пользователь $SHARE_USER уже существует — добавляю в группу $group для доступа к шаре"
            $SUDO usermod -aG "$group" "$SHARE_USER"
            ok "$SHARE_USER добавлен в группу $group"
        fi
        return 0
    fi

    # На минимальном Alpine (без пакета shadow) useradd/groupadd может не
    # быть вовсе — там только busybox adduser/addgroup с другим набором
    # флагов. Явно проверяем, а не падаем на голом "command not found".
    if ! command -v useradd >/dev/null 2>&1 || ! command -v groupadd >/dev/null 2>&1; then
        err "useradd/groupadd не найдены — на Alpine поставьте пакет shadow (apk add shadow) или создайте $SHARE_USER вручную и добавьте в группу $group"
        MANUAL_TODO+=("создать SMB-only пользователя $SHARE_USER вручную (useradd/groupadd не найдены), добавить в группу $group")
        return 1
    fi
    local nologin_shell; nologin_shell="$(find_nologin_shell)"
    info "Пользователь $SHARE_USER не найден — создаю SMB-only учётку (без домашнего каталога и входа в систему): useradd -M -N -G $group -s $nologin_shell $SHARE_USER"
    $SUDO useradd -M -N -G "$group" -s "$nologin_shell" -c "SMB-only (samba-share.sh)" "$SHARE_USER"
    ok "Пользователь $SHARE_USER создан (только для SMB, вход в систему запрещён)"
}

# Samba требует execute-бит на КАЖДОМ родительском каталоге по пути до
# шары, а этот скрипт (намеренно) правит права только на самом $SHARE_PATH,
# не трогая чужие каталоги выше (например, чей-то $HOME) без явного
# разрешения. Частый случай — шара лежит внутри домашнего каталога другого
# пользователя (обычно drwx------): тогда SMB-пользователь успешно
# логинится, но получает ACCESS_DENIED на любом листинге — выглядит как
# баг SMB-клиента, а на деле не хватает прав на проход через родителя.
# Проверяем эту цепочку заранее и, если где-то упёрлись, подсказываем
# точную команду для точечной починки — вместо того чтобы молча оставить
# пользователя разбираться с непонятной ошибкой в SMB-клиенте. При шаре
# под $SMB_ROOT (стандартный случай, права там уже 755 от root) это почти
# всегда пройдёт молча.
check_smb_traverse_linux() {
    if ! command -v sudo >/dev/null 2>&1; then
        warn "sudo не найден — не могу заранее проверить права прохода до $SHARE_PATH для $SHARE_USER; при ACCESS_DENIED на листинге проверьте права родительских каталогов вручную (namei -l $SHARE_PATH)"
        return 0
    fi
    local dir="$SHARE_PATH" chain=() d
    while [[ "$dir" != "/" ]]; do
        dir="$(dirname "$dir")"
        chain=("$dir" "${chain[@]}")
    done
    for d in "${chain[@]}"; do
        if ! sudo -u "$SHARE_USER" test -x "$d" 2>/dev/null; then
            warn "$SHARE_USER не сможет зайти в $SHARE_PATH — нет права прохода (execute) через $d"
            if command -v setfacl >/dev/null 2>&1; then
                MANUAL_TODO+=("$SHARE_PATH недоступен из-за прав на $d -> sudo setfacl -m u:$SHARE_USER:--x '$d' (даёт только проход через каталог, без листинга его содержимого)")
            else
                MANUAL_TODO+=("$SHARE_PATH недоступен из-за прав на $d -> sudo chmod o+x '$d' (даёт проход через каталог всем локальным пользователям, без листинга его содержимого); либо поставьте пакет acl и используйте setfacl -m u:$SHARE_USER:--x '$d' для более точечного разрешения")
            fi
            return 1
        fi
    done
}

# В контейнерах (Docker/LXC без --privileged) systemctl может присутствовать
# как бинарь, но реально не работать: "System has not been booted with
# systemd as init system (PID 1)". systemctl тогда либо не отвечает вообще,
# либо тихо ничего не запускает — поэтому решаем не по наличию бинаря, а по
# /run/systemd/system (создаётся только настоящим systemd-инитом), и в таких
# средах поднимаем smbd/nmbd как обычные демоны напрямую.
restart_smbd_linux() {
    local conf="$1"
    if [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1; then
        $SUDO systemctl enable --now smbd 2>/dev/null || $SUDO systemctl enable --now smb 2>/dev/null || true
        if $SUDO systemctl restart smbd 2>/dev/null || $SUDO systemctl restart smb 2>/dev/null; then
            ok "smbd перезапущен (systemctl), $conf подхвачен"
            return 0
        fi
        warn "systemctl не смог перезапустить smbd/smb, пробую поднять демон напрямую"
    else
        warn "systemd недоступен как init (типично для контейнера) — поднимаю smbd напрямую, без systemctl"
    fi

    local smbd_bin nmbd_bin
    smbd_bin="$(find_sbin smbd)" || { err "Бинарь smbd не найден"; MANUAL_TODO+=("установить и запустить smbd вручную"); return 1; }
    $SUDO pkill -HUP smbd 2>/dev/null || true
    pgrep -x smbd >/dev/null 2>&1 || $SUDO "$smbd_bin" -D || true
    if nmbd_bin="$(find_sbin nmbd)" && ! pgrep -x nmbd >/dev/null 2>&1; then
        $SUDO "$nmbd_bin" -D || true
    fi

    if pgrep -x smbd >/dev/null 2>&1; then
        ok "smbd запущен напрямую (демон), $conf подхвачен"
    else
        err "Не удалось запустить smbd"
        MANUAL_TODO+=("запустить smbd вручную: sudo smbd -D (проверьте sudo journalctl / sudo smbd -i для диагностики)")
    fi
}

linux_setup() {
    local share_group; share_group="$(share_group_name "$SHARE_NAME")"

    ensure_smb_user_linux "$share_group"

    info "Устанавливаю Samba..."
    # apt/zypper без предварительного обновления индекса не найдут пакет
    # даже если он есть в репозитории (типичная причина "Unable to locate
    # package" на свежих системах/контейнерах, где apt-get update ещё не
    # выполнялся).
    case "$PKG_MANAGER" in
        apt)    $SUDO apt-get update -y ;;
        zypper) $SUDO zypper --non-interactive refresh ;;
    esac
    pkg_native "" samba samba samba samba samba || { err "Не удалось установить пакет samba"; return 1; }

    local conf="$SMB_CONF_LINUX"
    [[ -f "$conf" ]] || { err "Не найден $conf после установки samba"; return 1; }

    # Владелец — root, а не конкретный $SHARE_USER: реальный доступ и так
    # идёт через группу шары (valid users = @группа ниже), root тут просто
    # нейтральный владелец, который никогда не удаляется (в отличие от
    # SMB-only юзера, которого может снести -d/--delete) и не оставит
    # каталог с "осиротевшим" UID в ls -l.
    #
    # Для НЕгостевых шар — 2770 (rwxrws---): доступ строго владельцу и
    # группе, у "остальных" (other) вообще ничего — иначе с 2775 любой
    # локальный пользователь этой машины (не по SMB, а просто в шелле) мог
    # бы зайти и прочитать содержимое, даже не будучи в группе шары. Для
    # гостевых шар так нельзя: гостевое подключение в Samba маппится на
    # отдельную unix-учётку (обычно nobody), которая не состоит ни в одной
    # группе шар — 2770 просто заблокировал бы гостей полностью, поэтому
    # для них оставляем 2775, как раньше.
    local dir_mode create_mask dir_mask
    if [[ "$GUEST_OK" == "yes" ]]; then
        dir_mode=2775; create_mask=0664; dir_mask=2775
    else
        dir_mode=2770; create_mask=0660; dir_mask=2770
    fi

    # Применяем права на КАЖДОМ запуске (не только при первом создании) —
    # владелец/группа теперь детерминированы (root + smbshare-ИМЯ, а не
    # "последний добавленный юзер"), так что это идемпотентно и заодно
    # само подтягивает права шар, созданных старой версией скрипта.
    $SUDO chown root:"$share_group" "$SHARE_PATH"
    $SUDO chmod "$dir_mode" "$SHARE_PATH"
    check_smb_traverse_linux || true

    if grep -qx "\[$SHARE_NAME\]" "$conf" 2>/dev/null; then
        info "Шара [$SHARE_NAME] уже настроена в $conf — добавляю доступ для $SHARE_USER"
        # Шара могла быть создана до появления 2770/root-владельца (старой
        # версией скрипта) — тогда её create/directory mask в конфиге всё
        # ещё старые, и новые файлы внутри шары получали бы права шире,
        # чем сам каталог. Обновляем, только если значение реально другое.
        local current_dm; current_dm="$(smb_conf_current_dir_mask "$SHARE_NAME")"
        if [[ -n "$current_dm" && "$current_dm" != "$dir_mask" ]]; then
            local bak2="${conf}.bak-$(date +%Y%m%d%H%M%S)"
            $SUDO cp "$conf" "$bak2"
            smb_conf_update_masks "$SHARE_NAME" "$create_mask" "$dir_mask"
            ok "Обновил create/directory mask в $conf под текущие права (было $current_dm, бэкап -> $bak2)"
        fi
    else
        local bak="${conf}.bak-$(date +%Y%m%d%H%M%S)"
        $SUDO cp "$conf" "$bak"
        info "Бэкап $conf -> $bak"
        {
            echo
            echo "[$SHARE_NAME]"
            echo "    path = $SHARE_PATH"
            echo "    browseable = yes"
            echo "    read only = $( [[ "$READ_ONLY" == "yes" ]] && echo yes || echo no )"
            echo "    guest ok = $( [[ "$GUEST_OK" == "yes" ]] && echo yes || echo no )"
            if [[ "$GUEST_OK" != "yes" ]]; then
                echo "    valid users = @$share_group"
            fi
            echo "    force group = $share_group"
            echo "    create mask = $create_mask"
            echo "    directory mask = $dir_mask"
        } | $SUDO tee -a "$conf" >/dev/null
        ok "Секция [$SHARE_NAME] добавлена в $conf (доступ через группу $share_group, владелец каталога — root)"
    fi

    $SUDO testparm -s >/dev/null 2>&1 || warn "testparm сообщил о проблемах в конфиге — проверьте: sudo testparm"

    if [[ "$GUEST_OK" != "yes" ]]; then
        if ! $SUDO pdbedit -L 2>/dev/null | cut -d: -f1 | grep -qx "$SHARE_USER"; then
            if [[ -n "$SHARE_PASSWORD" ]]; then
                info "Задаю пароль Samba для $SHARE_USER неинтерактивно (-p/--password)"
                printf '%s\n%s\n' "$SHARE_PASSWORD" "$SHARE_PASSWORD" | $SUDO smbpasswd -s -a "$SHARE_USER"
            elif [[ -t 0 ]]; then
                info "Задайте пароль Samba для $SHARE_USER (независимый от системного логина):"
                $SUDO smbpasswd -a "$SHARE_USER"
            else
                warn "Нет TTY и не передан -p/--password — пропускаю создание пароля Samba для $SHARE_USER"
                MANUAL_TODO+=("задать пароль Samba: sudo smbpasswd -a $SHARE_USER")
            fi
        fi
        $SUDO smbpasswd -e "$SHARE_USER" >/dev/null 2>&1 || true
    fi

    restart_smbd_linux "$conf"

    if command -v ufw >/dev/null 2>&1; then
        if $SUDO ufw allow samba >/dev/null 2>&1; then
            ok "ufw: разрешён профиль Samba"
        else
            warn "ufw allow samba не сработал (профиль Samba недоступен или ufw неактивен)"
        fi
    elif command -v firewall-cmd >/dev/null 2>&1; then
        if $SUDO firewall-cmd --permanent --add-service=samba >/dev/null 2>&1 && $SUDO firewall-cmd --reload >/dev/null 2>&1; then
            ok "firewalld: разрешён сервис samba"
        else
            warn "firewall-cmd не сработал (firewalld не запущен?)"
        fi
    fi

    local host_ip
    host_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    ok "Готово: smb://${host_ip:-$(hostname)}/$SHARE_NAME"
}

# Убирает $1 из unix-группы $2 (если он там состоит), а затем, ТОЛЬКО если
# у него SMB-only шелл (nologin/false — маркер учётки, созданной
# ensure_smb_user_linux) И не осталось доступа ни к одной другой шаре
# (других групп smbshare-*) — удаляет учётку целиком, включая запись в базе
# Samba (smbpasswd -x). Пользователь с обычным логин-шеллом, или у кого
# остался доступ к другим шарам, НЕ удаляется никогда — только чистится
# членство в этой конкретной группе. Общая логика для удаления целой шары
# (cleanup_share_group_users_linux, по всем участникам группы) и для снятия
# доступа одного пользователя (remove_user_from_share_linux).
remove_user_from_group_linux() {
    local u="$1" group="$2" shell base other_count

    if id -nG "$u" 2>/dev/null | tr ' ' '\n' | grep -qx "$group"; then
        if $SUDO gpasswd -d "$u" "$group" >/dev/null 2>&1; then
            ok "$u убран из группы $group"
        else
            warn "$u: не смог убрать из группы $group (возможно, это его основная группа) -> проверьте вручную"
            return 1
        fi
    else
        ok "$u не состоит в группе $group — нечего убирать"
    fi

    shell="$(getent passwd "$u" | cut -d: -f7)"
    base="$(basename "$shell")"
    if [[ "$base" != "nologin" && "$base" != "false" ]]; then
        ok "$u: обычный логин-пользователь ($shell) — оставляю"
        return 0
    fi

    other_count="$(id -nG "$u" 2>/dev/null | tr ' ' '\n' | grep -c "^$SMB_GROUP_PREFIX" || true)"
    if [[ "${other_count:-0}" -eq 0 ]]; then
        info "$u: SMB-only учётка ($shell), доступа к другим шарам не осталось — удаляю пользователя"
        $SUDO smbpasswd -x "$u" >/dev/null 2>&1 || true
        if $SUDO userdel "$u" 2>/dev/null; then
            ok "Пользователь $u удалён"
        else
            warn "Не удалось удалить $u -> проверьте вручную (userdel $u)"
        fi
    else
        ok "$u: SMB-only, но есть доступ ещё к $other_count шар(е/ам) — учётка остаётся, убрал только из $group"
    fi
}

# Прогоняет remove_user_from_group_linux по ВСЕМ участникам группы шары —
# используется при удалении шары целиком (-d).
cleanup_share_group_users_linux() {
    local group="$1" gid members primary_members all_members u

    gid="$(getent group "$group" | cut -d: -f3)"
    members="$(getent group "$group" | cut -d: -f4 | tr ',' ' ')"
    primary_members="$(getent passwd | awk -F: -v gid="$gid" '$4==gid {print $1}')"
    all_members="$(printf '%s %s\n' "$members" "$primary_members" | tr ' ' '\n' | sed '/^$/d' | sort -u)"

    for u in $all_members; do
        id "$u" >/dev/null 2>&1 || continue
        remove_user_from_group_linux "$u" "$group"
    done
}

# Снимает доступ ОДНОГО пользователя к ОДНОЙ шаре (-x/--remove-user),
# не трогая саму шару и остальных её участников. Шара и группа должны уже
# существовать; сам пользователь — тоже (несуществующего снимать не с чего).
remove_user_from_share_linux() {
    local conf="$SMB_CONF_LINUX"
    if [[ ! -f "$conf" ]] || ! grep -qx "\[$SHARE_NAME\]" "$conf" 2>/dev/null; then
        err "Шара [$SHARE_NAME] не найдена в $conf"
        return 1
    fi
    id "$SHARE_USER" >/dev/null 2>&1 || { err "Пользователь $SHARE_USER не найден"; return 1; }

    local share_group; share_group="$(share_group_name "$SHARE_NAME")"
    if ! getent group "$share_group" >/dev/null 2>&1; then
        warn "Группа $share_group не найдена — у $SHARE_USER и так нет доступа к шаре [$SHARE_NAME] через неё"
        return 0
    fi

    info "Убираю доступ $SHARE_USER к шаре [$SHARE_NAME]"
    remove_user_from_group_linux "$SHARE_USER" "$share_group"
}

delete_share_linux() {
    local conf="$SMB_CONF_LINUX"
    if [[ ! -f "$conf" ]] || ! grep -qx "\[$SHARE_NAME\]" "$conf" 2>/dev/null; then
        err "Шара [$SHARE_NAME] не найдена в $conf — нечего удалять"
        return 1
    fi

    local share_path share_group
    share_path="$(smb_conf_extract_path "$SHARE_NAME")"
    share_group="$(share_group_name "$SHARE_NAME")"

    info "Удаляю шару [$SHARE_NAME] из $conf (файлы на диске НЕ трогаю)"

    local bak="${conf}.bak-$(date +%Y%m%d%H%M%S)"
    $SUDO cp "$conf" "$bak"
    info "Бэкап $conf -> $bak"

    local tmp; tmp="$(mktemp)"
    awk -v s="[$SHARE_NAME]" '
        $0==s {infile=1; next}
        infile && /^\[/ {infile=0}
        !infile {print}
    ' "$conf" > "$tmp"
    $SUDO cp "$tmp" "$conf"
    rm -f "$tmp"
    ok "Секция [$SHARE_NAME] удалена из $conf"

    if getent group "$share_group" >/dev/null 2>&1; then
        cleanup_share_group_users_linux "$share_group"
        if $SUDO groupdel "$share_group" 2>/dev/null; then
            ok "Группа $share_group удалена"
        else
            warn "Не удалось удалить группу $share_group (возможно, она ещё чья-то основная) -> проверьте вручную: getent group $share_group"
            MANUAL_TODO+=("удалить группу $share_group вручную после проверки её участников")
        fi
    else
        warn "Группа $share_group не найдена — либо шара была создана старой версией скрипта (общая группа smbusers, без пер-шаровых групп), либо уже подчищена"
    fi

    $SUDO testparm -s >/dev/null 2>&1 || warn "testparm сообщил о проблемах в конфиге — проверьте: sudo testparm"
    restart_smbd_linux "$conf"

    if [[ -n "$share_path" ]]; then
        ok "Готово. Каталог с файлами НЕ удалён: $share_path — удалите вручную, если больше не нужен"
    else
        ok "Готово"
    fi
}

macos_setup() {
    # Автосоздание SMB-only пользователя (useradd) и пер-шаровые группы —
    # линуксовая история. На macOS учётки заводятся через sysadminctl/dscl
    # (полноценный пользователь с UID/домашним каталогом, своего "SMB-only"
    # режима вроде nologin там нет), а доступ к SMB — через одну общую
    # группу com.apple.access_smb, а не свою группу на каждую шару — это
    # отдельная и более тяжёлая процедура, вне рамок этого скрипта.
    # Пользователь должен существовать заранее.
    id "$SHARE_USER" >/dev/null 2>&1 || { err "Пользователь $SHARE_USER не найден (автосоздание пользователей есть только на Linux) — создайте вручную: sudo sysadminctl -addUser $SHARE_USER -fullName '$SHARE_USER' -password '<пароль>'"; return 1; }

    $SUDO chown "$SHARE_USER" "$SHARE_PATH"
    chmod 775 "$SHARE_PATH"

    if [[ "$GUEST_OK" != "yes" ]]; then
        info "Добавляю $SHARE_USER в группу доступа по SMB (com.apple.access_smb)"
        $SUDO dseditgroup -o edit -a "$SHARE_USER" -t user com.apple.access_smb 2>/dev/null || true
    fi

    command -v sharing >/dev/null 2>&1 || { err "Утилита sharing не найдена, включите общий доступ вручную"; return 1; }

    if sharing -l 2>/dev/null | grep -qF "$SHARE_PATH"; then
        warn "Share point для $SHARE_PATH уже существует (sharing -l), пропускаю добавление"
    else
        local guest_flag; guest_flag=$( [[ "$GUEST_OK" == "yes" ]] && echo 001 || echo 000 )
        $SUDO sharing -a "$SHARE_PATH" -n "$SHARE_NAME" -S "$SHARE_NAME" -s 001 -g "$guest_flag"
        if [[ "$READ_ONLY" == "yes" ]]; then
            $SUDO sharing -e "$SHARE_NAME" -R 1
        fi
        ok "Share point '$SHARE_NAME' создан ($SHARE_PATH)"
    fi

    warn "На macOS остался ручной шаг (Apple не даёт включить это из терминала):"
    warn "  System Settings -> General -> Sharing -> File Sharing:"
    warn "  включите тумблер, убедитесь, что для '$SHARE_NAME' стоит SMB,"
    warn "  и отметьте $SHARE_USER в списке пользователей (потребуется ввести его пароль)."
    MANUAL_TODO+=("System Settings -> Sharing -> File Sharing: включить и добавить $SHARE_USER для '$SHARE_NAME'")

    local host
    host="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"
    ok "После включения тумблера: smb://$host.local/$SHARE_NAME"
}

if [[ "$DELETE_SHARE" == "yes" ]]; then
    [[ -n "$SHARE_NAME" ]] || { err "Для удаления укажите имя шары: -n ИМЯ"; usage; exit 1; }
    [[ -z "$SHARE_PATH" ]] || warn "Путь '$SHARE_PATH' игнорируется при удалении — путь берётся из конфига по имени шары"
    case "$OS" in
        linux) delete_share_linux ;;
        macos) err "Удаление шар пока реализовано только для Linux"; exit 1 ;;
    esac
elif [[ "$REMOVE_USER" == "yes" ]]; then
    [[ -n "$SHARE_NAME" ]] || { err "Укажите имя шары: -n ИМЯ"; usage; exit 1; }
    [[ "$SHARE_USER_SET" == "yes" ]] || { err "Укажите пользователя явно: -u ЮЗЕР (у -x/--remove-user нет умолчания по текущему пользователю)"; usage; exit 1; }
    [[ -z "$SHARE_PATH" ]] || warn "Путь '$SHARE_PATH' игнорируется при снятии доступа"
    case "$OS" in
        linux) remove_user_from_share_linux ;;
        macos) err "Снятие доступа отдельного пользователя пока реализовано только для Linux"; exit 1 ;;
    esac
else
    if [[ -z "$SHARE_PATH" ]]; then
        existing_path=""
        if [[ "$OS" == "linux" && -n "$SHARE_NAME" ]]; then
            existing_path="$(smb_conf_extract_path "$SHARE_NAME" 2>/dev/null || true)"
        fi
        if [[ -n "$existing_path" ]]; then
            SHARE_PATH="$existing_path"
            info "Шара '$SHARE_NAME' уже настроена, путь: $SHARE_PATH"
        elif [[ -n "$SHARE_NAME" ]]; then
            SHARE_PATH="$SMB_ROOT/$SHARE_NAME"
        else
            err "Укажите путь к каталогу или имя шары (-n/--name) — тогда каталог будет создан в $SMB_ROOT/<имя>"
            usage
            exit 1
        fi
    fi
    SHARE_PATH="$(mkdir -p "$SHARE_PATH" && cd "$SHARE_PATH" && pwd)"
    [[ -n "$SHARE_NAME" ]] || SHARE_NAME="$(basename "$SHARE_PATH")"

    case "$OS" in
        linux) linux_setup ;;
        macos) macos_setup ;;
    esac
fi

if [[ ${#MANUAL_TODO[@]} -gt 0 ]]; then
    echo
    warn "Осталось сделать вручную:"
    printf '    - %s\n' "${MANUAL_TODO[@]}"
fi
