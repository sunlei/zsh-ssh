# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project Overview

zsh-ssh is a Zsh plugin that replaces `ssh` host completion with an fzf picker. It parses the SSH config (including `Include` files), lists the hosts, and opens fzf with a preview when the user presses <kbd>Tab</kbd> after `ssh`.

Design principles:

- Activate only on <kbd>Tab</kbd> after a configured command (default `ssh`); fall back to the original <kbd>Tab</kbd> binding outside a supported destination context.
- Filter hosts that cannot be connected to directly (wildcards, `!` negations, `Match` blocks).
- Do not require network access or optional tools at runtime; degrade gracefully when an optional tool is missing.

## Project Structure

- `zsh-ssh.zsh`: The whole plugin (config parsing, host listing, fzf integration).
- `zsh-ssh.plugin.zsh`: Symlink to `zsh-ssh.zsh` for plugin managers.
- `test.sh`: Test runner (all suites or one suite).
- `tests/`: `test_framework.zsh` (assertion helpers), `test_*.zsh` (suites), `ssh_config` and `config.d/` (fixture configs).
- `docs/`: Issue analyses, fix plans, and `lessons.md`.
- `README.md`: User-facing installation, usage, and configuration.

## Architecture

Key functions in `zsh-ssh.zsh` (search by name; do not rely on line numbers):

- `_parse_config_file`: Recursively expands `Include` directives (globs, `~`, relative paths resolved from the logical config directory, symlinked configs) and guards against include cycles. Uses zsh's POSIX regex (`unsetopt rematchpcre`), not PCRE.
- `_ssh_known_hosts_list`: Extracts plain hostnames from `known_hosts`; skips hashed entries.
- `_ssh_host_list`: AWK-based extraction of alias, hostname, user, `Tag`, and `#_Desc` description per host; merges known hosts when enabled; handles `tag:<name>` filtering.
- `_zsh_ssh_columnize`: Aligns columns with `column` when available, otherwise prints plain output.
- `_fzf_list_generator`: Formats the host list (header row, optional `Tag` column) for fzf.
- `_zsh_ssh_destination_index`: Locates the destination using raw Shell boundaries and command-specific `getopts` rules shared by completion and recording.
- `_zsh_ssh_destination_parts`: Validates a literal host suffix and preserves supported literal or variable username prefixes without evaluating Shell text.
- `_zsh_ssh_sort_recent`: Reorders candidates from a recent-host snapshot with one AWK pass; leaves unseen candidates in their original order.
- `_zsh_ssh_record_recent`: A `preexec` hook using alias-expanded argument 3; records submitted destinations in a locked, atomically replaced list of 200 unique hosts.
- `fzf_complete_ssh`: ZLE widget bound to <kbd>Tab</kbd>; prefills the fzf query from the partial input and falls back to `fzf_ssh_default_completion`.

Configuration variables:

- `SSH_CONFIG_FILE`: SSH config path (default `$HOME/.ssh/config`).
- `ZSH_SSH_INCLUDE_KNOWN_HOSTS`: Set to `1` to include hosts from `known_hosts` (default off).
- `ZSH_SSH_KNOWN_HOSTS_FILE`: `known_hosts` path (default `$HOME/.ssh/known_hosts`).
- `ZSH_SSH_COMMANDS`: Zsh array of supported commands (default `(ssh)`); SFTP has separate option rules and wrappers use SSH rules.
- `ZSH_SSH_SORT_RECENT`: Set to `1` to record submitted destinations and prefer recent hosts (default off).
- `ZSH_SSH_RECENT_FILE`: State path, set before loading the plugin (default `${XDG_STATE_HOME:-$HOME/.local/state}/zsh-ssh/recent`). Capacity is an internal constant of 200 hosts.
- `fzf_ssh_default_completion`: Internal backup of the original <kbd>Tab</kbd> widget.

Dependencies: `zsh`, `fzf`, `awk`, `grep`, `cut`, and `realpath` are required. `column` is optional for the plugin but required by `test.sh`.

Optional recent-host recording uses `zsh/system`, `mkdir`, `mktemp`, `mv`, and `rm`. Its failure must preserve the previous state and normal host completion. Scope file permissions and lock descriptors to the update subshell.

## Commands

- Syntax check: `zsh -n zsh-ssh.zsh`
- Run all tests: `./test.sh`
- Run one suite: `./test.sh <suite>`, where `<suite>` is the `tests/test_<suite>.zsh` suffix (`config_parser`, `host_list`, `fzf_integration`, `integration`, `completion`, `recent`, `zle`).
- Inspect host list output against a fixture: `SSH_CONFIG_FILE=./tests/ssh_config zsh -f -c 'source ./zsh-ssh.zsh; _ssh_host_list'`

## Coding Style

- Indent with 2 spaces.
- Write comments in `zsh-ssh.zsh` in English; explain why, not what.
- Prefix private helpers with `_` (e.g. `_parse_config_file`); use uppercase for environment and configuration variables (e.g. `SSH_CONFIG_FILE`).
- Keep functions focused; extract a helper only when it removes real duplication or names a real concept.
- Quote variable expansions to avoid word splitting and globbing; avoid `eval`, and document the reason and bounds if it is unavoidable.
- Do not depend on the user's interactive shell options: declare required options with `setopt localoptions ...` (e.g. `bareglobqual` for glob qualifiers such as `(N)`).
- Prefer portable standard tools and simple pipelines; keep AWK code readable with stable input and output formats.

## Testing

- Use the assertion helpers in `tests/test_framework.zsh` (`assert_equals`, `assert_contains`, `assert_line_present`, `assert_line_absent`, etc.); keep each test independent with a clear assertion message.
- Add fixtures under `tests/ssh_config` or `tests/config.d/` rather than reading the user's real SSH config.
- Add or update tests when changing core logic; `./test.sh` must pass before committing.
- Before concluding that an issue is already fixed, confirm that a test exercises the issue's exact scenario; if none does, reproduce it first. A green suite does not prove coverage.
- Add regression tests with the relevant shell option disabled when code depends on a shell option.
- Completion tests combine real fixture parsing with mocked fzf/ZLE boundaries. The `zle` suite uses a real pseudo-terminal with mocked SSH/fzf, and the `recent` suite checks concurrent writers and safe state replacement. Tests must not connect to real hosts or read user SSH configuration.
- Read `docs/lessons.md` before working on a related area, and record new lasting lessons there.

## Commits & Pull Requests

- Write commit messages in English using Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`), with a lowercase subject of at most 50 characters.
- In PRs, describe the change and motivation, link the related issue, and include before/after output (text, screenshot, or asciinema) when behavior visibly changes. Ensure tests pass and no new warnings appear.

## Security & Configuration

- Never commit keys or real SSH configs.
- Avoid hardcoded paths; respect `SSH_CONFIG_FILE` and handle `Include` correctly.
- Keep fzf-related logic able to fall back safely to the default completion.
