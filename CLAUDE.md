# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

zsh-ssh is a Zsh plugin that provides better SSH host completion using fzf. It parses SSH config files and presents an interactive selection interface when users press Tab after the `ssh` command.

## Core Architecture

### Key Files

- `zsh-ssh.zsh` - Main plugin implementation containing all core functionality
- `zsh-ssh.plugin.zsh` - Oh My Zsh plugin entry point that sources the main file
- `tests/` - Test configuration directory with SSH config examples

### Core Components

**SSH Config Parser** (`_parse_config_file`)

- Recursively parses SSH config files with full Include directive support
- Handles wildcard path expansion and relative path resolution
- Uses PCRE regex matching for robust parsing

**Host List Generator** (`_ssh_host_list`)

- Uses AWK script to parse configuration content
- Extracts host aliases, hostnames, users, and descriptions
- Filters out wildcard hosts and Match directive entries
- Supports `#_Desc` comments for host descriptions

**FZF Integration** (`fzf_complete_ssh`)

- Provides interactive search and selection interface
- Shows formatted host list with preview panel
- Auto-populates search keywords from partial input
- Falls back to default completion when appropriate

### Design Philosophy

The plugin follows a non-intrusive design:
- Only activates on Tab after `ssh` command
- Preserves original Tab completion as fallback
- Intelligently filters inappropriate hosts (wildcards, Match conditions)
- Provides rich preview of SSH configuration details

## Testing

Manual testing using configurations in `tests/`:
- `tests/ssh_config` - Main test configuration
- `tests/config.d/` - Include directive test files

No automated test framework - verification is done through manual testing.

## Dependencies

- **fzf** (required) - For interactive selection interface
- Standard Unix tools: awk, grep, column, cut, realpath

## Configuration

- `SSH_CONFIG_FILE` - Path to SSH config file (default: `$HOME/.ssh/config`)
- `fzf_ssh_default_completion` - Backup of original Tab completion command

## Key Functions

When modifying the code, understand these critical functions:

- `_parse_config_file:15` - Recursive config parser with Include support
- `_ssh_host_list:56` - AWK-based host extraction with filtering logic
- `fzf_complete_ssh:202` - Main completion handler with fallback logic
- `_fzf_list_generator:168` - Formats host data for fzf display

## Usage Pattern

The plugin automatically triggers when users type `ssh <partial-host>` and press Tab. If multiple matches exist, fzf displays an interactive list with preview panel showing SSH configuration details.
