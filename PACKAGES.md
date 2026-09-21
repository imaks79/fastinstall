# Что устанавливает setup.sh

Список того, что ставится (или проверяется на наличие) командой `./setup.sh`,
и как именно — по каждому пакетному менеджеру. Тот же список — с языком
реализации, поддерживаемой ОС и ссылкой на первоисточник (git-репозиторий, а
если нет — сайт разработчика) каждой программы — печатает `./setup.sh --list`,
ничего не устанавливая.

## Прослойка пакетного менеджера

| ОС | Что ставится |
|---|---|
| macOS | Homebrew (если ещё не установлен) |
| Linux | flatpak + репозиторий flathub |

## Базовые пакеты

| Пакет | brew | apt | dnf | pacman | zypper | apk |
|---|---|---|---|---|---|---|
| git | git | git | git | git | git | git |
| ssh | (системный) | openssh-client | openssh-clients | openssh | openssh | openssh-client |
| stow | stow | stow | stow | stow | stow | stow |
| mc | mc | mc | mc | mc | mc | mc |
| vifm | vifm | vifm | vifm | vifm | vifm | vifm |
| htop | htop | htop | htop | htop | htop | htop |
| nvim | neovim | neovim | neovim | neovim | neovim | neovim |
| tmux | tmux | tmux | tmux | tmux | tmux | tmux |
| zsh | zsh | zsh | zsh | zsh | zsh | zsh |
| pass | pass | pass | pass | pass | pass | pass |
| gpg | gnupg | gnupg | gnupg2 | gnupg | gpg2 | gnupg |
| eza | eza | eza | eza | eza | eza | eza |
| wireguard-tools | wireguard-tools | wireguard-tools | wireguard-tools | wireguard-tools | wireguard-tools | wireguard-tools |

После установки zsh скрипт также делает его оболочкой по умолчанию
(`chsh`, функция `set_default_shell_zsh()`) — путь к бинарю при необходимости
дописывается в `/etc/shells`. Если `chsh` не проходит автоматически (нет прав,
недоступен интерактивно), команда попадает в список "сделать вручную".

`stow` этот репозиторий сам не использует (раскладку конфигов делает
отдельный dotfiles-репозиторий) — ставится заранее как зависимость для него.

Сам терминал (alacritty) сюда больше не входит — это опциональный шаг
`./tools-extra.sh alacritty`, см. [TOOLS-EXTRA.md](TOOLS-EXTRA.md). Тема
для него (alacritty-theme) осталась здесь, см. ниже "Клонируемые
git-репозитории".

## Языки и инструменты разработки

| Пакет | Способ установки |
|---|---|
| rust | `rustup` (официальный установщик, обе ОС); перед сборкой на Linux ставится тулчейн — компилятор, `pkg-config`, заголовки openssl |
| uv | brew (macOS) / официальный скрипт `astral.sh/uv/install.sh` (Linux) |
| [Oh My Posh](https://ohmyposh.dev/) | macOS — свой brew tap `jandedobbeleer/oh-my-posh/oh-my-posh` (не `homebrew/core`); Linux — официальный `ohmyposh.dev/install.sh` |

Oh My Posh — движок темы шелла. Ставится здесь только сам бинарь;
инициализация в `.zshrc` (`eval "$(oh-my-posh init zsh)"`) и выбор темы —
дело личных dotfiles, `setup.sh` `.zshrc` не трогает. TUI-мастер настройки
(подбор Nerd Font, темы, прописывание инициализации в шеллы) —
[omp-manager](https://github.com/psmux/omp-manager), опциональный шаг
`./tools-extra.sh omp-manager`, см. [TOOLS-EXTRA.md](TOOLS-EXTRA.md).

## Шрифты (Nerd Fonts)

- Hack
- 0xProto
- JetBrainsMono

macOS — brew cask; Linux — через [`getnf`](https://github.com/getnf/getnf).

## Клонируемые git-репозитории

| Что | Куда |
|---|---|
| oh-my-zsh | `~/.config/.oh-my-zsh` |
| zsh-autosuggestions | `~/.config/.oh-my-zsh/custom/plugins/zsh-autosuggestions` |
| zsh-syntax-highlighting | `~/.config/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting` |
| oh-my-tmux | `~/.config/.oh-my-tmux` |
| tpm | `~/.config/tmux/plugins/tpm` |
| tmux-sensible | `~/.config/tmux/plugins/tmux-sensible` |
| tmux-resurrect | `~/.config/tmux/plugins/tmux-resurrect` |
| tmux-continuum | `~/.config/tmux/plugins/tmux-continuum` |
| tmux-yank | `~/.config/tmux/plugins/tmux-yank` |
| tmux-thumbs | `~/.config/tmux/plugins/tmux-thumbs` |
| tmux-fzf | `~/.config/tmux/plugins/tmux-fzf` |
| tmux-fzf-url | `~/.config/tmux/plugins/tmux-fzf-url` |
| catppuccin-tmux | `~/.config/tmux/plugins/catppuccin-tmux` |
| tmux-sessionx | `~/.config/tmux/plugins/tmux-sessionx` |
| tmux-floax | `~/.config/tmux/plugins/tmux-floax` |
| alacritty-theme | `~/.config/alacritty/themes` |

Сам терминал alacritty сюда не входит — это опциональный шаг
`./tools-extra.sh alacritty`, см. [TOOLS-EXTRA.md](TOOLS-EXTRA.md); тема же
для него (`alacritty-theme` выше) осталась в `setup.sh`.

Альтернативный Neovim IDE (AstroNvim/NvChad/LunarVim по официальным докам,
с переустановкой с нуля при повторном выборе) сюда не входит — это
опциональный шаг `./tools-extra.sh ide` (диалог выбора), см.
[TOOLS-EXTRA.md](TOOLS-EXTRA.md#ide--выбор-neovim-ide).

## Явно исключено

- **Zed** — убран из установки по запросу.
- **musikcube** — убран из установки по запросу.

## Дополнительные инструменты — отдельными скриптами

В `setup.sh` попадает только базовый набор (таблицы выше). Две группы
TUI/CLI-инструментов ставятся отдельными скриптами, чтобы не грузить
основную установку тем, что нужно не всем:

- **`./tools-extra.sh`** — alacritty, yazi, bat, duf, tldr, termusic, lazygit,
  k9s и ещё 21 инструмент. См. [TOOLS-EXTRA.md](TOOLS-EXTRA.md).
- **`./tui-tools.sh`** — семейство [tui-tools](https://github.com/tui-tools)
  для администрирования Linux-сервера (firewall, systemd, cron, сертификаты
  и т.п.), только Linux. См. раздел в [README.md](README.md#tui-toolssh).

Всё, что не удалось поставить автоматически, попадает в список
"сделать вручную", который печатается в конце работы скрипта.

## Как добавить или убрать свой пакет

Вся установка живёт в `lib/packages.sh`, вызовы функций — в `setup.sh` внутри
`cmd_install()`.

**Обычный пакет через системный менеджер** — правь `install_core_packages()`
или `install_terminal()` в `lib/packages.sh`. Формат вызова:

```bash
pkg_native <brew> <apt> <dnf> <pacman> <zypper> <apk>
```

Пустая строка `""` в любой позиции = "в этом менеджере пакета нет, пропустить".
Чтобы добавить пакет — допиши строку с его именами для каждого менеджера.
Чтобы убрать — удали строку (или закомментируй `#`).

**Пакет со своим способом установки** (официальный curl-скрипт, cask,
flatpak и т.п.) — по образцу `install_rust()`, `install_uv()`,
`install_omp_manager()` в `lib/packages.sh`: своя функция с проверкой
`command -v <бинарь>` в начале (чтобы не ставить повторно), и вызов этой
функции из `cmd_install()` в `setup.sh`.

**Клонируемый git-репозиторий** (плагин, тема) — по образцу
`install_oh_my_tmux()` в `lib/packages.sh`: одна строка с
`clone_or_update <url> <путь>` (она сама решает clone или pull). Не забудь
добавить вызов в `cmd_install()`.

**Шрифт** — допиши имя в `install_fonts()`: для brew — в список
`brew install --cask font-...`, для Linux — в список имён у `getnf -i`.

После любых правок: `bash -n setup.sh lib/*.sh` — быстрая проверка синтаксиса
без реального запуска.

**Не забудьте `./setup.sh --list`** — данные для него (описание, язык,
поддерживаемая ОС, ссылка на первоисточник) отдельная таблица в конце
`lib/packages.sh` (`core_group_members()`, `core_pkg_desc()`, `core_pkg_url()`,
`core_pkg_lang()`, `core_pkg_os()`, `CORE_GROUP_NAMES`) и синхронизируется
вручную с тем, что реально устанавливает `cmd_install()` — при
добавлении/удалении пакета допишите (или уберите) его и там.
