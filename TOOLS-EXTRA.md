# Что ставит tools-extra.sh

Дополнительные TUI/CLI-инструменты, не входящие в базовый набор `setup.sh`.
Ставятся отдельно, потому что не всем нужны — `./tools-extra.sh --list`
показывает этот же список в терминале, `./tools-extra.sh <имя> ...` ставит
только выбранные.

Для каждого инструмента скрипт сначала пробует нативный пакетный менеджер
(brew/apt/dnf/pacman/zypper/apk), и только если пакета там нет — переходит к
фолбэку (`cargo install`, официальный install-скрипт или бинарь с GitHub
Releases). `cargo` должен быть уже установлен — его ставит основной
`setup.sh` (`install_rust()`), поэтому `tools-extra.sh` имеет смысл запускать
после него.

| Инструмент | Что делает | Fallback, если нет в пакетном менеджере |
|---|---|---|
| **tldr** | Короткие практические примеры для команд вместо полного `man` | `cargo install tealdeer` (на zypper пакет уже называется `tealdeer`) |
| **duf** | Диски и точки монтирования — наглядная замена `df` | нет (Go-проект, не публикуется на crates.io); на apk ставьте вручную |
| **gpg-tui** | Управление ключами GnuPG в TUI | `cargo install gpg-tui` |
| **termusic** | Терминальный музыкальный плеер | `cargo install termusic` |
| **vortix** | TUI для WireGuard/OpenVPN: живая телеметрия, kill switch, детект утечек DNS/IPv6 | `cargo install vortix` |
| **wlctl** | TUI для wifi/ethernet/vpn через NetworkManager | `cargo install wlctl`; **только Linux** — на macOS нет NetworkManager, скрипт пропускает |
| **lazygit** | TUI для git | бинарь с GitHub Releases (tar.gz + проверка sha256 по `checksums.txt`) |
| **lazydocker** | TUI для docker/docker-compose | официальный `install_update_linux.sh` с GitHub |
| **k9s** | TUI для Kubernetes-кластера | `.deb` с GitHub Releases (только там, где есть apt) |
| **termscp** | Терминальный SCP/SFTP/FTP/S3-клиент | `cargo install termscp` |
| **lnav** | Просмотр и анализ логов: подсветка, SQL-запросы к логам | — (есть везде) |
| **dust** | Наглядная замена `du` — что занимает место на диске | `cargo install du-dust` (бинарь всё равно называется `dust`) |
| **yazi** | Быстрый терминальный файловый менеджер | `cargo install yazi-fm yazi-cli` |
| **fastfetch** | Информация о системе при старте терминала (замена neofetch) | `.deb` с GitHub Releases (только там, где есть apt) |
| **bottom** | Монитор процессов и ресурсов (замена top/htop), бинарь `btm` | `cargo install bottom` |
| **gping** | `ping` с графиком задержки в реальном времени | `cargo install gping` |
| **trippy** | `traceroute` + `ping` в одном TUI, бинарь `trip` | `cargo install trippy` |
| **bandwhich** | Какой процесс сколько сетевого трафика потребляет | `cargo install bandwhich` |
| **bat** | `cat` с подсветкой синтаксиса и git-диффом | — (есть везде; на Debian/Ubuntu бинарь называется `batcat`, не `bat`) |
| **chafa** | Показ картинок прямо в терминале | — (есть везде) |
| **pdftoipe** | Конвертация PDF в XML для редактора Ipe | нет; есть только в brew и apt, на dnf/pacman/zypper/apk ставьте из исходников |
| **7zip** | Архиватор 7-Zip | — (есть везде под разными именами: `sevenzip`/`p7zip-full`/`7zip`/`p7zip`) |
| **slumber** | Терминальный REST/gRPC-клиент (TUI-замена Postman/Insomnia) | `cargo install slumber` |
| **[mangofetch](https://github.com/julesklord/mangofetch)** | TUI-загрузчик медиа (YouTube, torrent, SoundCloud, Instagram) — оборачивает `yt-dlp`/`ffmpeg`, сам докачивает недостающие бинари | `cargo install mangofetch` (нет ни в одном пакетном менеджере — новый проект) |
| **[gonzo](https://github.com/control-theory/gonzo)** | TUI для анализа логов в реальном времени в стиле k9s: графики, Kubernetes/OTLP из коробки, AI-инсайты | нативного пакета нет нигде на Linux — бинарь с GitHub Releases с проверкой sha256 (на macOS есть в brew) |
| **[keyward](https://github.com/gateway-of-last-resort/keyward)** | TUI для управления SSH-ключами: редактирование `~/.ssh/config`, аудит безопасности, шифрованные бэкапы | на macOS — `brew install gateway-of-last-resort/tap/keyward` (свой tap); на Linux нативного пакета нет — бинарь с GitHub Releases с проверкой sha256 |
| **[ssh-list](https://github.com/akinoiro/ssh-list)** | TUI-менеджер SSH-подключений: добавление/сортировка/поиск, импорт хостов из `~/.ssh/config` | `cargo install ssh-list` (пакет есть на crates.io); на macOS — `brew install akinoiro/tap/ssh-list` (свой tap); в AUR/PPA есть, но через пакетный менеджер напрямую не ставится (нужны `paru`/PPA-репозиторий) |
| **[lazyssh](https://github.com/Adembc/lazyssh)** | TUI для SSH-подключений в стиле lazydocker/k9s | на macOS — `brew install Adembc/homebrew-tap/lazyssh` (свой tap); на Linux нативного пакета нет и `go install` не годится (в `go.mod` есть `replace` на форкнутый модуль) — бинарь с GitHub Releases с проверкой sha256 по `checksums.txt` |
| **[sshs](https://github.com/quantumsheep/sshs)** | TUI-выбор хостов из `~/.ssh/config` для быстрого подключения по SSH | Rust-проект, но НЕ на crates.io (только `cargo install --git`) — есть в brew (без tap) и в официальном репозитории Arch (`pacman -S sshs`); на apt — `.deb` с GitHub Releases, на dnf/zypper/apk — голый бинарь с релизов с проверкой sha256 |
| **[herdr](https://herdr.dev)** | Агенто-осведомлённый мультиплексор терминала для coding-агентов: держит панели живыми на сервере при закрытии клиента/обрыве SSH, агенты управляют им через CLI/socket API | в `homebrew/core` под своим именем (`brew install herdr`); на Linux нативного пакета нет — голый бинарь с GitHub Releases без проверки sha256 (файла контрольных сумм релиз не публикует). **Не путать** с одноимённым, но не связанным крейтом на crates.io (`ogulcancelik/herdr`) — он сюда не используется как фолбэк |
| **ide** | Neovim IDE — интерактивный диалог: [AstroNvim](https://docs.astronvim.com/) / [NvChad](https://nvchad.com/docs/quickstart/install) / [LunarVim](https://www.lunarvim.org/docs/installation) / очистить редактор | нет (спрашивает номер варианта в терминале), см. раздел ниже |
| **[isd](https://github.com/kainctl/isd)** | TUI для systemd-юнитов: fuzzy-поиск, автообновляемый предпросмотр, умный `sudo`; **только Linux** | нет пакетов нигде — ставится через `uv tool install isd-tui` (Python-проект) |

## ide — выбор Neovim IDE

Раньше AstroNvim ставился безусловно внутри `setup.sh`. Теперь это отдельный
опциональный шаг: `./tools-extra.sh ide` спрашивает номер варианта (1-4) и
ставит выбранное **точно по официальным инструкциям** каждого проекта:

1. **AstroNvim** ([docs.astronvim.com](https://docs.astronvim.com/)) —
   `git clone --depth 1 https://github.com/AstroNvim/template ~/.config/nvim`,
   затем `.git` из клона удаляется (иначе конфиг остаётся форком
   `AstroNvim/template`, а не самостоятельным репозиторием — так в доке).
2. **NvChad** ([nvchad.com/docs/quickstart/install](https://nvchad.com/docs/quickstart/install)) —
   `git clone https://github.com/NvChad/starter ~/.config/nvim` (`.git`
   специально остаётся, как в официальной команде).
3. **LunarVim** ([lunarvim.org/docs/installation](https://www.lunarvim.org/docs/installation)) —
   официальный install-скрипт, ветка `master` (как в доке), `-y --overwrite`
   для неинтерактивного прохождения. Ставится в `~/.config/lvim` и
   `~/.local/share/lunarvim`, свой бинарь `lvim`. На практике (проверено на
   чистой Kali) установщик иногда выходит с ошибкой уже ПОСЛЕ того, как
   `lvim` готов — не сошлась версия плагина по лок-файлу (git-коммит
   отличается от ожидаемого, характерно для первой установки). Это не
   значит, что установка провалилась: скрипт различает этот случай (бинарь
   `lvim` уже есть) и вместо ссылки на доки пишет в "сделать вручную" именно
   `:Lazy sync` внутри `lvim` — как советует сам официальный установщик.
4. **Очистить редактор** — сносит конфиг/данные/state/кэш **всех трёх**
   вариантов разом (не только выбранного), без бэкапа, чтобы затем поставить
   любую сборку с нуля. Спрашивает подтверждение `[y/N]` перед удалением и
   печатает список каталогов, которые реально существуют на диске (если
   нечего чистить — просто сообщает об этом и ничего не делает). На Linux
   дополнительно чистит Flatpak-путь `~/.var/app/io.neovim.nvim/...`.

### `~/.config/nvim` — общий для AstroNvim и NvChad, и маркер

Официально оба ставятся **в один и тот же** `~/.config/nvim`, поэтому
одновременно там может быть только один из них — а по факту наличия каталога
не различить, какой именно. Скрипт хранит это в
`~/.cache/dotfiles-ide-marker` (`astronvim` / `nvchad`) — файл пишется и
читается только этим диалогом, не претендует на «истину» о том, что вообще
лежит в `~/.config/nvim` (например, симлинк, разложенный отдельным
репозиторием с dotfiles, марку не оставляет).

Если каталог уже занят (по марке — или просто существует/это симлинк, марки
нет), скрипт **не обновляет его на месте**, а сносит и ставит заново с нуля:
`~/.config/nvim`, `~/.local/share/nvim`, `~/.local/state/nvim`, `~/.cache/nvim`
(плюс Flatpak `io.neovim.nvim` на Linux) — тот же набор путей, что в разделах
Uninstall самих `docs.astronvim.com` и
[nvchad.com/docs/quickstart/install](https://nvchad.com/docs/quickstart/install).
`rm -rf` на симлинк удаляет только сам симлинк, не трогая то, на что он
указывает — так что снести безопасно, даже если это был симлинк, разложенный
отдельным репозиторием с dotfiles: сам репозиторий не страдает, теряется
только активная ссылка в `~/.config`.

LunarVim в этот маркер не входит — у него свой `NVIM_APPNAME=lvim`
(`~/.config/lvim`), с `~/.config/nvim` он не пересекается ни при установке,
ни при переустановке (та идёт через его собственный бандловый
`utils/installer/uninstall.sh`, флаги `--remove-config --remove-backups` —
без `--remove-config` он оставляет `~/.config/lvim` нетронутым).

## Требует системных библиотек для сборки из исходников

Некоторые cargo-фолбэки тянут системные зависимости помимо компилятора
(который и так ставит `ensure_build_toolchain()` в `lib/packages.sh`):

- **gpg-tui** — `gpgme`, `libgpg-error`, (опционально `libxcb` для буфера обмена)
- **termusic** — аудио-библиотеки (ALSA на Linux)

Если сборка упадёт из-за отсутствующего `-dev`/`-devel` пакета, ошибка
попадёт в `MANUAL_TODO` в конце вывода скрипта — доустановите нужный
`-dev`-пакет вручную и повторите `./tools-extra.sh <имя>`.

## Как добавить новый инструмент

Список специально сделан таблицей одной функции, а не набором отдельных
шагов, — чтобы дописывать было легко:

1. Имя — в массив `TOOLS_EXTRA_NAMES` (`lib/tools_extra.sh`).
2. Описание — строка в `case` внутри `tool_desc()`.
3. Установка — строка в `case` внутри `install_tool()`:
   - если пакет есть хоть где-то нативно (или можно собрать `cargo install`) —
     `pkg_or_cargo <бинарь> <cargo-крейт> <brew> <apt> <dnf> <pacman> <zypper> <apk>`
     (пустая строка = "пакета здесь нет");
   - если у проекта свой официальный install-скрипт или релизы без cargo —
     отдельная функция по образцу `install_lazygit`/`install_k9s` в том же файле.
