#!/usr/bin/env zsh

# Better completion for ssh in Zsh.
# https://github.com/sunlei/zsh-ssh
# v0.0.7
# Copyright (c) 2020 Sunlei <guizaicn@gmail.com>

setopt no_beep # don't beep
zstyle ':completion:*:ssh:*' hosts off # disable built-in hosts completion

SSH_CONFIG_FILE="${SSH_CONFIG_FILE:-$HOME/.ssh/config}"

ZSH_SSH_RECENT_FILE="${ZSH_SSH_RECENT_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/zsh-ssh/recent}"
typeset -gi _zsh_ssh_recent_max=200
typeset -gA _zsh_ssh_optstrings=(
  ssh  "1246AaCfGgKkMNnqsTtVvXxYyZB:b:c:D:E:e:F:I:i:J:L:l:m:O:o:P:p:Q:R:S:W:w:"
  sftp "46AaCfNpqrvB:b:c:D:F:i:J:l:o:P:R:S:s:X:"
)
typeset -gi _zsh_ssh_parse_depth=0
typeset -gA _zsh_ssh_seen_config_files

# Parse the file and handle the include directive.
_parse_config_file() {
  # Include expansion uses the (N) glob qualifier, so enable its option locally.
  setopt localoptions bareglobqual
  unsetopt rematchpcre
  unsetopt nomatch

  local input_path="$1"
  local logical_config_path config_file_path include_base_dir
  local line raw_path expanded include_file_path
  local -a include_paths

  # Keep the caller-visible path for relative Includes so symlinked configs
  # resolve sibling includes from the link location, while realpath is used
  # below for reading and cycle detection.
  logical_config_path="$input_path"
  if [[ $logical_config_path == '~'* ]]; then
    logical_config_path="${logical_config_path/#\~/$HOME}"
  fi
  if [[ "$logical_config_path" != /* ]]; then
    logical_config_path="$PWD/$logical_config_path"
  fi
  include_base_dir="$(dirname "$logical_config_path")"

  # Resolve the full path of the input config file
  config_file_path=$(realpath "$logical_config_path" 2>/dev/null) || return 0

  # If previous parse was interrupted, reset stale global state.
  if (( _zsh_ssh_parse_depth <= 0 )); then
    _zsh_ssh_parse_depth=0
    unset _zsh_ssh_seen_config_files
    typeset -gA _zsh_ssh_seen_config_files
  fi

  (( _zsh_ssh_parse_depth++ ))
  {
    if [[ -n "${_zsh_ssh_seen_config_files[$config_file_path]}" ]]; then
      return 0
    fi
    _zsh_ssh_seen_config_files[$config_file_path]=1

    # Read the file line by line
    while IFS= read -r line || [[ -n "$line" ]]; do
      # Match lines starting with 'Include'
      if [[ $line =~ ^[[:space:]]*[Ii][Nn][Cc][Ll][Uu][Dd][Ee][[:space:]=]+(.*) ]] && (( $#match > 0 )); then
        # Split the rest of the line into individual paths
        include_paths=(${(z)match[1]})

        for raw_path in "${include_paths[@]}"; do
          # Expand ~ and environment variables in the path
          expanded="${(e)raw_path}"

          # Expand a literal leading ~ before testing whether the path is relative.
          if [[ $expanded == '~'* ]]; then
            expanded="${expanded/#\~/$HOME}"
          fi

          # Relative Include paths follow the logical config directory, not the realpath target.
          if [[ "$expanded" != /* ]]; then
            expanded="$include_base_dir/$expanded"
          fi

          # Expand wildcards (e.g. *.conf) and loop over each matched file
          for include_file_path in ${~expanded}(N); do
            if [[ -f "$include_file_path" ]]; then
              # Separate includes with a blank line (for readability)
              echo ""
              # Recursively parse included files
              _parse_config_file "$include_file_path"
            fi
          done
        done
      else
        # Print normal (non-Include) lines
        echo "$line"
      fi
    done < "$config_file_path"
  } always {
    (( _zsh_ssh_parse_depth-- ))
    if (( _zsh_ssh_parse_depth <= 0 )); then
      _zsh_ssh_parse_depth=0
      unset _zsh_ssh_seen_config_files
      typeset -gA _zsh_ssh_seen_config_files
    fi
  }
}

_ssh_known_hosts_list() {
  local known_hosts_file="${ZSH_SSH_KNOWN_HOSTS_FILE:-$HOME/.ssh/known_hosts}"

  [[ -f "$known_hosts_file" ]] || return 0

  command awk '
    function emit_host(host) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", host)

      if (!host || host ~ /^\|1\|/ || host ~ /[*?!]/) {
        return
      }

      if (host ~ /^\[[^]]+\]:[0-9]+$/) {
        host = substr(host, 2, index(host, "]") - 2)
      }

      if (host) {
        printf "%s|->|%s| | |[\033[00;34mknown_hosts\033[0m]\n", host, host
      }
    }

    /^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
    $1 ~ /^@/ { next }

    {
      split($1, hosts, ",")
      for (i in hosts) {
        emit_host(hosts[i])
      }
    }
  ' "$known_hosts_file"
}

# Readers see an entire snapshot; unseen candidates retain their original order.
_zsh_ssh_sort_recent() {
  emulate -L zsh
  [[ -s "$ZSH_SSH_RECENT_FILE" ]] || { command cat; return; }
  command awk -F '|' '
    NR == FNR { rank[$0] = NR; recent_count = NR; next }
    $1 in rank { recent[rank[$1]] = recent[rank[$1]] $0 ORS; next }
    { rest = rest $0 ORS }
    END {
      for (i = 1; i <= recent_count; i++) printf "%s", recent[i]
      printf "%s", rest
    }
  ' "$ZSH_SSH_RECENT_FILE" -
}

# Scope permissions and release the advisory lock when the update subshell exits.
_zsh_ssh_record_recent() {
  emulate -L zsh
  local -a tokens reply hosts
  local host REPLY
  [[ "$ZSH_SSH_SORT_RECENT" == 1 ]] || return 0
  tokens=(${(z)3})
  [[ ${tokens[1]} == command ]] && shift tokens
  _zsh_ssh_destination_index "${tokens[@]}" || return 0
  (( REPLY <= $#tokens )) || return 0
  _zsh_ssh_destination_parts "${tokens[REPLY]}" "${tokens[1]}" || return 0
  host=$reply[2]
  [[ -n "$host" ]] || return 0

  (
    local tmp file="$ZSH_SSH_RECENT_FILE"
    umask 077
    command mkdir -p "${file:h}" || return 0
    zmodload zsh/system 2>/dev/null || return 0
    : >>| "$file.lock" || return 0
    zsystem flock "$file.lock" || return 0
    {
      if [[ -e "$file" ]]; then
        [[ -f "$file" && -r "$file" ]] || return 0
        hosts=(${(f)"$(<"$file")"}) || return 0
      fi
      hosts=("$host" "${(@)hosts:#$host}")
      tmp=$(command mktemp "${file}.XXXXXXXXXX") || return 0
      print -rl -- "${(@)hosts[1,_zsh_ssh_recent_max]}" >| "$tmp" && command mv -f -- "$tmp" "$file"
    } always {
      [[ -z "$tmp" || ! -e "$tmp" ]] || command rm -f -- "$tmp"
    }
  )
  return 0
}

_ssh_host_list() {
  local ssh_config host_list tag_query

  ssh_config=$(_parse_config_file "$SSH_CONFIG_FILE")
  ssh_config=$(printf "%s\n" "$ssh_config" | command grep -v -E "^\s*#[^_]")
  # Ensure blank line before each Host/Match block for AWK paragraph mode (RS="")
  ssh_config=$(printf "%s\n" "$ssh_config" | command awk '/^[[:space:]]*[Hh]ost[[:space:]]|^[[:space:]]*[Mm]atch[[:space:]]/{print ""} {print}')

  host_list=$(printf "%s\n" "$ssh_config" | command awk '
    function join(array, start, end, sep, result, i) {
      # https://www.gnu.org/software/gawk/manual/html_node/Join-Function.html
      if (sep == "")
        sep = " "
      else if (sep == SUBSEP) # magic value
        sep = ""
      result = array[start]
      for (i = start + 1; i <= end; i++)
        result = result sep array[i]
      return result
    }

    function parse_line(line) {
      gsub(/^[[:space:]]+/, "", line)
      n = split(line, line_array, /[[:space:]]*=[[:space:]]*|[[:space:]]+/)

      key = line_array[1]
      value = join(line_array, 2, n)

      return key "#-#" value
    }

    function starts_or_ends_with_star(str) {
        start_char = substr(str, 1, 1)
        end_char = substr(str, length(str), 1)

        return start_char == "*" || end_char == "*" || start_char == "!"
    }

    BEGIN {
      IGNORECASE = 1
      FS="\n"
      RS=""
    }
    {
      match_directive = ""

      # Use spaces to ensure the column command maintains the correct number of columns.
      #   - user
      #   - tag_formated
      #   - desc_formated

      user = " "
      host_name = ""
      alias = ""
      aliases = ""
      tag = ""
      tag_formated = " "
      desc = ""
      desc_formated = " "

      for (line_num = 1; line_num <= NF; ++line_num) {
        line = parse_line($line_num)

        split(line, tmp, "#-#")

        key = tolower(tmp[1])
        value = tmp[2]

        if (key == "match") { match_directive = value }

        if (key == "host") { aliases = value }
        if (key == "user") { user = value }
        if (key == "hostname") { host_name = value }
        if (key == "tag" && !tag) { tag = value }
        if (key == "#_desc") { desc = value }
      }

      if (tag) {
        tag_formated = sprintf("[\033[00;36m%s\033[0m]", tag)
      }

      if (desc) {
        desc_formated = sprintf("[\033[00;34m%s\033[0m]", desc)
      }

      n_aliases = split(aliases, alias_list, " ")
      for (i = 1; i <= n_aliases; i++) {
        alias = alias_list[i]
        effective_hostname = host_name ? host_name : alias

        if (!(effective_hostname && !starts_or_ends_with_star(effective_hostname)) || !(alias && !starts_or_ends_with_star(alias)) || match_directive) {
          continue
        }

        # Per-alias aggregation: each field uses first-non-empty wins
        # Extra rule: explicit HostName takes precedence over fallback value
        if (!(alias in alias_hn)) {
          alias_hn[alias] = effective_hostname
          alias_user[alias] = user
          alias_tag[alias] = tag_formated
          alias_desc[alias] = desc_formated
          if (host_name) alias_explicit_hn[alias] = 1
        } else {
          if (host_name && !alias_explicit_hn[alias]) {
            alias_hn[alias] = host_name
            alias_explicit_hn[alias] = 1
          }
          if (user != " " && alias_user[alias] == " ") {
            alias_user[alias] = user
          }
          if (tag_formated != " " && alias_tag[alias] == " ") {
            alias_tag[alias] = tag_formated
          }
          if (desc_formated != " " && alias_desc[alias] == " ") {
            alias_desc[alias] = desc_formated
          }
        }
      }
    }
    END {
      for (a in alias_hn) {
        printf "%s|->|%s|%s|%s|%s\n", a, alias_hn[a], alias_user[a], alias_tag[a], alias_desc[a]
      }
    }
  ')

  if [[ "$ZSH_SSH_INCLUDE_KNOWN_HOSTS" == "1" ]]; then
    host_list="${host_list}"$'\n'"$(_ssh_known_hosts_list)"
  fi

  if [[ "$1" == tag:* ]]; then
    tag_query="${1#tag:}"
    host_list=$(command awk -F '|' -v q="$tag_query" '
      function plain_tag(value) {
        gsub(/\033\[[0-9;]*m/, "", value)
        gsub(/^\[|\]$/, "", value)
        return value
      }

      BEGIN { q = tolower(q) }
      NF >= 6 && (q == "" || index(tolower(plain_tag($5)), q) > 0)
    ' <<< "$host_list")
  elif [[ -n "$1" ]]; then
    host_list=$(command grep -i -- "$1" <<< "$host_list")
  fi
  host_list=$(printf "%s\n" "$host_list" | command sort -u)

  if [[ "$ZSH_SSH_SORT_RECENT" == 1 ]]; then
    local sorted_hosts
    if sorted_hosts=$(printf "%s\n" "$host_list" | _zsh_ssh_sort_recent); then
      host_list="$sorted_hosts"
    fi
  fi

  printf "%s\n" "$host_list"
}


_zsh_ssh_columnize() {
  if command -v column >/dev/null 2>&1; then
    command column -t -s '|'
    return
  fi

  command awk -F '|' '{
    for (i = 1; i <= NF; i++) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i)
    }

    output = $1
    for (i = 2; i <= NF; i++) {
      output = output "  " $i
    }
    print output
  }'
}

_fzf_list_generator() {
  local header host_list

  if [ -n "$1" ]; then
    host_list="$1"
  else
    host_list=$(_ssh_host_list)
  fi

  if printf "%s\n" "$host_list" | command awk -F '|' 'NF >= 6 && $5 !~ /^[[:space:]]*$/ { found = 1 } END { exit !found }'; then
    header="
Alias|->|Hostname|User|Tag|Desc
─────|──|────────|────|───|────
"
  else
    host_list=$(printf "%s\n" "$host_list" | command awk -F '|' '
      BEGIN { OFS = "|" }
      NF >= 6 { print $1, $2, $3, $4, $6; next }
      { print }
    ')
    header="
Alias|->|Hostname|User|Desc
─────|──|────────|────|────
"
  fi

  host_list="${header}"$'\n'"${host_list}"

  printf "%s\n" "$host_list" | _zsh_ssh_columnize
}

# Locate the destination in the first simple command without evaluating Shell text.
_zsh_ssh_destination_index() {
  emulate -L zsh
  local -a tokens=("$@") ssh_commands=(${ZSH_SSH_COMMANDS:-ssh})
  local opt OPTARG token command_name="${tokens[1]}"
  local -i OPTIND=2 token_count=$#tokens boundary=$(( $#tokens + 1 )) i
  local control='^[;&|()]+$|^#'
  local redirection='^([0-9]*|\{[[:alpha:]_][[:alnum:]_]*\}|&)[<>]'

  (( ${ssh_commands[(Ie)$command_name]} )) || return 1
  for (( i = 2; i <= $#tokens; i++ )); do
    token=${tokens[i]}
    if [[ "$token" =~ "$control" || "$token" =~ "$redirection" ]]; then
      boundary=$i
      break
    fi
  done
  tokens=("${(@)tokens[1,boundary-1]}")
  while getopts ":${_zsh_ssh_optstrings[${tokens[1]}]:-${_zsh_ssh_optstrings[ssh]}}" opt "${(@Q)tokens}"; do
    [[ "$opt" == ([?:QV]|+*) ]] && return 1
  done
  (( boundary > token_count || OPTIND < boundary )) || return 1
  REPLY=$OPTIND
}

# Keep only a proven literal host suffix; a dynamic username stays verbatim.
_zsh_ssh_destination_parts() {
  emulate -L zsh
  local word="$1" command_name="$2" prefix host_part query
  local username='^([[:alnum:]_.+%@-]|\$[[:alpha:]_][[:alnum:]_]*|\$\{[[:alpha:]_][[:alnum:]_]*\})+$'

  host_part="$word"
  if [[ "$word" == *@* ]]; then
    prefix=${word%@*}
    [[ "$prefix" =~ "$username" ]] || return 1
    host_part=${word##*@}
  fi
  [[ "$host_part" != *[\$\`\(\)\{\}]* ]] || return 1
  query=${(Q)host_part}
  [[ "$query" != *[\'\"\\/]* ]] || return 1
  if [[ "$command_name" == sftp && "$query" == *:* && "$query" != tag:* ]]; then
    return 1
  fi
  reply=("$host_part" "$query")
}

_set_lbuffer() {
  local selected_host="$1" host_part="$2"
  LBUFFER="${LBUFFER%"$host_part"}${(q)selected_host}"
}

fzf_complete_ssh() {
  emulate -L zsh
  local -a tokens reply fzf_extra_opts
  local host_word host_part query result key selection REPLY

  tokens=(${(z)LBUFFER})
  if ! _zsh_ssh_destination_index "${tokens[@]}" ||
     (( REPLY < $#tokens )) ||
     { (( REPLY == $#tokens )) && [[ "$LBUFFER" == *[[:space:]] ]]; } ||
     { (( REPLY > $#tokens )) && [[ "$LBUFFER" != *[[:space:]] ]]; } ||
     [[ ${tokens[REPLY]} == - ]] ||
     [[ -n "$RBUFFER" && "$RBUFFER" != [[:space:]]* ]]; then
    zle ${fzf_ssh_default_completion:-expand-or-complete}
    return
  fi

  host_word=${tokens[REPLY]}
  if ! _zsh_ssh_destination_parts "$host_word" "${tokens[1]}"; then
    zle ${fzf_ssh_default_completion:-expand-or-complete}
    return
  fi
  host_part=$reply[1]
  query=$reply[2]
  result=$(_ssh_host_list "$query")
  if [[ -z "$result" ]]; then
    [[ -n "$host_part" ]] || zle ${fzf_ssh_default_completion:-expand-or-complete}
    return
  fi

  if [[ "$result" != *$'\n'* ]]; then
    _set_lbuffer "${result%%|*}" "$host_part"
    zle reset-prompt
    return
  fi

  [[ "$ZSH_SSH_SORT_RECENT" == 1 ]] && fzf_extra_opts=(--tiebreak=index)
  result=$(_fzf_list_generator "$result" | fzf \
    --height 40% \
    --ansi \
    --border \
    --cycle \
    --info=inline \
    --header-lines=2 \
    --reverse \
    --prompt='SSH Remote > ' \
    --query="${query#tag:}" \
    --bind 'shift-tab:up,tab:down,bspace:backward-delete-char/eof' \
    --preview 'ssh -T -G $(cut -f 1 -d " " <<< {}) | grep -i -E "^User |^HostName |^Port |^ControlMaster |^ForwardAgent |^LocalForward |^IdentityFile |^RemoteForward |^ProxyCommand |^ProxyJump " | (command -v column >/dev/null 2>&1 && column -t || cat)' \
    --preview-window=right:40% \
    --expect=alt-enter,enter \
    "${fzf_extra_opts[@]}"
  )

  if [[ -n "$result" ]]; then
    key=${result%%$'\n'*}
    if [[ "$key" == "$result" ]]; then
      selection="$result"
      key=""
    else
      selection=${result#*$'\n'}
    fi
    if [[ -n "$selection" ]]; then
      _set_lbuffer "${selection%%[[:space:]]*}" "$host_part"
      if [[ "$key" == alt-enter ]]; then
        zle reset-prompt
      else
        zle accept-line
      fi
    fi
  fi
  [[ "$key" == alt-enter ]] || zle reset-prompt
}


[ -z "$fzf_ssh_default_completion" ] && {
  binding=$(bindkey '^I')
  [[ $binding =~ 'undefined-key' ]] || fzf_ssh_default_completion=$binding[(s: :w)2]
  unset binding
}


zle -N fzf_complete_ssh
bindkey '^I' fzf_complete_ssh

autoload -Uz add-zsh-hook
add-zsh-hook preexec _zsh_ssh_record_recent

# vim: set ft=zsh sw=2 ts=2 et
