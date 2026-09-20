# Что устанавливает setup.sh

Список того, что ставится (или проверяется на наличие) командой `./setup.sh`,
и как именно — по каждому пакетному менеджеру.

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

## Терминал

| Пакет | macOS | Linux |
|---|---|---|
| alacritty | brew cask | нативный пакет, иначе flatpak `org.alacritty.Alacritty` |

## Языки и инструменты разработки

| Пакет | Способ установки |
|---|---|
| rust | `rustup` (официальный установщик, обе ОС); перед сборкой на Linux ставится тулчейн — компилятор, `pkg-config`, заголовки openssl |
| uv | brew (macOS) / официальный скрипт `astral.sh/uv/install.sh` (Linux) |
| [omp-manager](https://github.com/psmux/omp-manager) | `cargo install omp-manager` (все ОС) — нет ни в одном пакетном менеджере, только crates.io |

omp-manager — TUI-мастер для [Oh My Posh](https://ohmyposh.dev): ставит сам
OMP, помогает подобрать Nerd Font, тему и настраивает шеллы через один
интерфейс (`omp-manager` после установки). Нужен `cargo`, поэтому в
`cmd_install()` идёт после `install_rust`.

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
| alacritty-theme | `~/.config/alacritty/themes` |

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

- **`./tools-extra.sh`** — yazi, bat, duf, tldr, termusic, lazygit, k9s и
  ещё 16 инструментов. См. [TOOLS-EXTRA.md](TOOLS-EXTRA.md).
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
`install_oh_my_tmux()` / `install_alacritty_theme()`: одна строка с
`clone_or_update <url> <путь>` (она сама решает clone или pull). Не забудь
добавить вызов в `cmd_install()`.

**Шрифт** — допиши имя в `install_fonts()`: для brew — в список
`brew install --cask font-...`, для Linux — в список имён у `getnf -i`.

После любых правок: `bash -n setup.sh lib/*.sh` — быстрая проверка синтаксиса
без реального запуска.
