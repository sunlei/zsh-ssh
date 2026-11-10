# zsh-ssh

Better host completion for ssh in Zsh.

[![asciicast](https://asciinema.org/a/381405.svg)](https://asciinema.org/a/381405)

- [zsh-ssh](#zsh-ssh)
    - [Installation](#installation)
        - [Zinit](#zinit)
        - [Antigen](#antigen)
        - [Oh My Zsh](#oh-my-zsh)
        - [Sheldon](#sheldon)
        - [Manual (Git Clone)](#manual-git-clone)
    - [Usage](#usage)
        - [Configuration](#configuration)
        - [SSH Config Example](#ssh-config-example)

## Installation

Make sure you have [fzf](https://github.com/junegunn/fzf) installed.
The `column` command is optional and only improves table/preview alignment; the plugin falls back to plain formatting when it is unavailable.

### Zinit

```shell
zinit light sunlei/zsh-ssh
```

### Antigen

```shell
antigen bundle sunlei/zsh-ssh
```

### Oh My Zsh

1. Clone this repository into `$ZSH_CUSTOM/plugins` (by default `~/.oh-my-zsh/custom/plugins`)

    ```shell
    git clone https://github.com/sunlei/zsh-ssh ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-ssh
    ```

2. Add the plugin to the list of plugins for Oh My Zsh to load (inside `~/.zshrc`):

    ```shell
    plugins=(zsh-ssh $plugins)
    ```

3. Start a new terminal session.

### Sheldon

1. Add this config to `~/.config/sheldon/plugins.toml`

    ```toml
    [plugins.zsh-ssh]
    github = 'sunlei/zsh-ssh'
    ```

2. Run `sheldon lock` to install the plugin.

3. Start a new terminal session.

### Manual (Git Clone)

1. Clone this repository somewhere on your machine. For example: `~/.zsh/zsh-ssh`.

    ```shell
    git clone https://github.com/sunlei/zsh-ssh ~/.zsh/zsh-ssh
    ```

2. Add the following to your `.zshrc`:

    ```shell
    source ~/.zsh/zsh-ssh/zsh-ssh.zsh
    ```

3. Start a new terminal session.

## Usage

Just press <kbd>Tab</kbd> after `ssh` command as usual.

### Configuration

Known hosts are not included by default. To include plain hostnames from `~/.ssh/known_hosts`, enable it explicitly:

```shell
export ZSH_SSH_INCLUDE_KNOWN_HOSTS=1
```

By default, the plugin reads `$HOME/.ssh/known_hosts`. To use another file:

```shell
export ZSH_SSH_KNOWN_HOSTS_FILE="$HOME/.ssh/known_hosts"
```

Hashed `known_hosts` entries cannot be converted back to hostnames and are skipped.

By default, only `ssh` triggers the host list. To also use it for `sftp` or an SSH-compatible wrapper, set `ZSH_SSH_COMMANDS` before loading the plugin (a Zsh array, without `export`):

```shell
ZSH_SSH_COMMANDS=(ssh sftp)
```

SFTP uses its own option rules; wrappers use SSH option rules. Completion preserves options, spacing, and text after the cursor. Username prefixes such as `user@`, `$USER@`, `${USER}@`, and `team-${USER}@` remain unchanged. Option values, remote-command positions, Shell operators, complex expansions, quoted username prefixes, URI destinations, and SFTP remote paths use normal completion when the destination cannot be safely completed.

To list recently used hosts first, enable recent-host sorting:

```shell
export ZSH_SSH_SORT_RECENT=1
```

When enabled, the plugin records submitted destinations for configured commands, including aliases and an optional `command` prefix. It records connection attempts before execution, without inspecting exit status or requiring shell history. For `ssh target || true`, only the first destination is recorded. Dynamic hostnames and unsupported command forms are skipped. Enter submits the selected command; Alt-Enter only edits it and does not record a host until execution.

The latest 200 unique hosts appear first, followed by the remaining hosts alphabetically. Fzf keeps match relevance first and uses recency to break ties. The state path can be changed before loading the plugin:

```shell
export ZSH_SSH_RECENT_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh-ssh/recent"  # default
```

Recent-host recording uses Zsh's `zsh/system` module and the standard `mkdir`, `mktemp`, `mv`, and `rm` commands. Updates use a separate lock file and atomic replacement; new state files are private to your user. Normal completion remains available if recent-host recording or sorting fails.

### SSH Config Example

You can use `#_Desc` to set description.

~/.ssh/config

```text
Host Bastion-Host
    Hostname 1.1.1.1
    User sunlei

Host Development-Host
    Hostname 2.2.2.2
    IdentityFile ~/.ssh/development-host
    #_Desc For Development
```

You can use OpenSSH `Tag` to group hosts in the list:

```text
Host Work-Bastion
    Hostname bastion.example.com
    User deploy
    Tag work
    #_Desc Bastion host

Host Home-NAS
    Hostname 192.168.1.20
    User root
    Tag personal
    #_Desc NAS
```

When any host has a `Tag`, zsh-ssh shows a `Tag` column. You can type `work`
in fzf to search for tagged hosts, or use `ssh tag:work<Tab>` to filter the
completion list by tag before fzf opens.

Include files are also supported. For example, your main config can include separate files:

~/.ssh/config

```text
Include ~/.ssh/config.d/company.ssh_config
Include ~/.ssh/config.d/home.ssh_config
Include ~/.ssh/config.d/work.ssh_config

# OR

Include ~/.ssh/config.d/*.ssh_config
```
