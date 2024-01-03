#!/usr/bin/env zsh

# Better completion for ssh in Zsh.
# https://github.com/sunlei/zsh-ssh
# v0.0.5
# Copyright (c) 2020 Sunlei <guizaicn@gmail.com>

SSH_CONFIG_FILE="${SSH_CONFIG_FILE:-$HOME/.ssh/config}"

# Parse the file and handle the include directive.
_parse_config_file() {
    # Enable PCRE matching
    setopt localoptions rematchpcre

    local config_file_path=$(realpath "$1")
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ $line =~ ^[Ii]nclude[[:space:]]+(.*) ]] && (( $#match > 0 )); then
            local include_path="${match[1]}"
            # Replace the first occurrence of "~" in the string with the value of the environment variable HOME.
            local expanded_include_path=${include_path/#\~/$HOME}
            # or $~expanded_include_path
            for include_file_path in $expanded_include_path; do
                if [[ -f "$include_file_path" ]]; then
                    _parse_config_file "$include_file_path"
                fi
            done
        else
            echo "$line"
        fi
    done < "$config_file_path"
}

_ssh-host-list() {
  local ssh_config host_list

  ssh_config=$(_parse_config_file $SSH_CONFIG_FILE)
  ssh_config=$(echo $ssh_config | command grep -v -E "^\s*#[^_]")

  host_list=$(echo $ssh_config | command awk '
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
      n = split(line, line_array, " ")

      key = line_array[1]
      value = join(line_array, 2, n)

      return key "#-#" value
    }

    function contains_star(str) {
        return index(str, "*") > 0
    }

    function starts_or_ends_with_star(str) {
        start_char = substr(str, 1, 1)
        end_char = substr(str, length(str), 1)

        return start_char == "*" || end_char == "*"
    }

    BEGIN {
      IGNORECASE = 1
      FS="\n"
      RS=""

      host_list = ""
    }
    {
      host_name = ""
      alias = ""
      desc = ""
      desc_formated = ""

      for (line_num = 1; line_num <= NF; ++line_num) {
        line = parse_line($line_num)

        split(line, tmp, "#-#")

        key = tmp[1]
        value = tmp[2]

        if (key == "Host") { aliases = value }
        if (key == "Hostname") { host_name = value }
        if (key == "#_Desc") { desc = value }
      }

      split(aliases, alias_list, " ")
      for( i in  alias_list)    {
          alias = alias_list[i]

          if (!host_name && alias ) {
              host_name = alias
          }

          if (desc) {
              desc_formated = sprintf("[\033[00;34m%s\033[0m]", desc)
          }

                  if ((host_name && !starts_or_ends_with_star(host_name)) && (alias && !starts_or_ends_with_star(alias))) {
              host = sprintf("%s|->|%s|%s\n", alias, host_name, desc_formated)
              host_list = host_list host
          }

      }
    }
    END {
      print host_list
    }
  ')

  for arg in "$@"; do
    case $arg in
    -*) shift;;
    *) break;;
    esac
  done

  host_list=$(command grep -i "$1" <<< "$host_list")
  host_list=$(echo $host_list | command sort -u)

  echo $host_list
}


_fzf-list-generator() {
  local header host_list

  if [ -n "$1" ]; then
    host_list="$1"
  else
    host_list=$(_ssh-host-list)
  fi

  header="
Alias|->|Hostname|Desc
─────|──|────────|────
"

  host_list="${header}\n${host_list}"

  echo $host_list | command column -t -s '|'
}

_set-lbuffer() {
  local result selected_host connect_cmd is_fzf_result
  result="$1"
  is_fzf_result="$2"

  if [ "$is_fzf_result" = false ] ; then
    result=$(cut -f 1 -d "|" <<< ${result})
  fi

  selected_host=$(cut -f 1 -d " " <<< ${result})
  connect_cmd="ssh ${selected_host}"

  LBUFFER="$connect_cmd"
}

fzf-complete-ssh() {
  local tokens cmd result selected_host
  setopt localoptions noshwordsplit noksh_arrays noposixbuiltins

  tokens=(${(z)LBUFFER})
  cmd=${tokens[1]}

  if [[ "$LBUFFER" =~ "^ *ssh$" ]]; then
    zle ${fzf_ssh_default_completion:-expand-or-complete}
  elif [[ "$cmd" == "ssh" ]]; then
    result=$(_ssh-host-list ${tokens[2, -1]})

    if [ -z "$result" ]; then
      zle ${fzf_ssh_default_completion:-expand-or-complete}
      return
    fi

    if [ $(echo $result | wc -l) -eq 1 ]; then
      _set-lbuffer $result false
      zle reset-prompt
      # zle redisplay
      return
    fi

    result=$(_fzf-list-generator $result | fzf \
      --height 40% \
      --ansi \
      --border \
      --cycle \
      --info=inline \
      --header-lines=2 \
      --reverse \
      --prompt='SSH Remote > ' \
      --no-separator \
      --bind 'shift-tab:up,tab:down,bspace:backward-delete-char/eof' \
      --preview 'ssh -T -G $(cut -f 1 -d " " <<< {}) | grep -i -E "^User |^HostName |^Port |^ControlMaster |^ForwardAgent |^LocalForward |^IdentityFile |^RemoteForward |^ProxyCommand |^ProxyJump " | column -t' \
      --preview-window=right:40%
    )

    if [ -n "$result" ]; then
      _set-lbuffer $result true
      zle accept-line
    fi

    zle reset-prompt
    # zle redisplay

  # Fall back to default completion
  else
    zle ${fzf_ssh_default_completion:-expand-or-complete}
  fi
}


[ -z "$fzf_ssh_default_completion" ] && {
  binding=$(bindkey '^I')
  [[ $binding =~ 'undefined-key' ]] || fzf_ssh_default_completion=$binding[(s: :w)2]
  unset binding
}


zle -N fzf-complete-ssh
bindkey '^I' fzf-complete-ssh
