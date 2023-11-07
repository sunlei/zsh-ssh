#!/usr/bin/env zsh

# Better completion for ssh in Zsh.
# https://github.com/sunlei/zsh-ssh
# v0.0.3
# Copyright (c) 2020 Sunlei <guizaicn@gmail.com>

_ssh-host-list() {
  local ssh_config host_list

  ssh_config=$(command awk -v HOME="$HOME" '
    function resolve_path(path) {
      if (substr(path, 1, 1) == "~") {
        path = HOME substr(path, 2)
      }
      else if (substr(path, 1, 1) != "/") {
        path = HOME "/.ssh/" path
      }
      return path
    }
    {
      if (NF == 2 && tolower($1) == "include") {
        file = resolve_path($2)
        cmd = "sed -s '\''$G'\'' " file " 2> /dev/null"
        while ( (cmd | getline line) > 0 ) {
          print line
        }
        close(file)
      } else {
        print
      }
    }
  ' $HOME/.ssh/config)
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

        if (key == "Host") { alias = value }
        if (key == "Hostname") { host_name = value }
        if (key == "#_Desc") { desc = value }
      }

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
	  --bind 'ctrl-y:execute-silent(echo -n {1} | xclip -selection clipboard)+abort' \
	  --bind 'ctrl-h:execute-silent(ssh -T -G {1} | grep -i -E "^HostName" | cut -f2 -d " "| xclip -selection clipboard)+abort' \
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
