#!/usr/bin/env zsh

# Run with zsh -f tests/completion.zsh [plugin-path]. No SSH connections or TTY needed.
typeset -a zle_calls
typeset -i checks=0
fzf_ssh_default_completion=expand-or-complete
zle() { [[ "$1" == -N ]] || zle_calls+=("$1"); return 0; }
bindkey() { return 0; }
source "${1:-${0:A:h:h}/zsh-ssh.zsh}" || exit 1

host_rows='target|->|192.0.2.1|user| | '
_ssh_host_list() {
  while [[ "$1" == -* ]]; do shift; done
  [[ "$1" == "$expected_query" ]] || return 1
  print -r -- "$host_rows"
}
_fzf_list_generator() { print -r -- "$1"; }
fzf() { command cat >/dev/null; print -r -- "$fzf_result"; }

check() {
  local expected_query="${3-}" expected_right="${4-}"
  local expected_widgets="${5-reset-prompt}"
  LBUFFER="$1"
  RBUFFER="$expected_right"
  zle_calls=()
  fzf_complete_ssh
  if [[ "$LBUFFER" != "$2" || "$RBUFFER" != "$expected_right" ||
        "${(j:,:)zle_calls}" != "$expected_widgets" ]]; then
    print -u2 -r -- "FAIL: $1 | $expected_right"
    print -u2 -r -- "expected: $2 | $expected_right [$expected_widgets]"
    print -u2 -r -- "actual:   $LBUFFER | $RBUFFER [${(j:,:)zle_calls}]"
    exit 1
  fi
  (( checks++ ))
  return 0
}

check 'ssh -v tar' 'ssh -v target' tar
check 'ssh -p 2222 tar' 'ssh -p 2222 target' tar
check 'ssh tar' 'ssh target' tar
check '  ssh   tar' '  ssh   target' tar
check $'ssh\t-v\ttar' $'ssh\t-v\ttarget' tar
check 'ssh -vAp2222 tar' 'ssh -vAp2222 target' tar
check 'ssh -J jump -i "key with spaces" user@tar' \
      'ssh -J jump -i "key with spaces" user@target' tar ' uptime'
check 'ssh -o "ProxyCommand=nc -x localhost:1080 %h %p" tar' \
      'ssh -o "ProxyCommand=nc -x localhost:1080 %h %p" target' tar
check "ssh 'tar'" 'ssh target' tar
check 'ssh -v tar*' 'ssh -v target' 'tar*'
check 'ssh -- tar' 'ssh -- target' tar
check 'ssh ' 'ssh target'
check 'ssh -p 2222 ' 'ssh -p 2222 target'
check 'ssh user@' 'ssh user@target'
check 'ssh tag:work' 'ssh target' tag:work
check 'ssh -J jump user@tag:work' 'ssh -J jump user@target' tag:work

# Each option consumes its value rather than treating that value as the destination.
for option in B b c D E e F I i J L l m O o P p R S W w; do
  check "ssh -$option value tar" "ssh -$option value target" tar
done

for input in 'ssh' 'ssh -' 'ssh -p ' 'ssh -p 22' 'ssh -i "key with spaces"' \
             'ssh -v' 'ssh -unknown tar' 'ssh -Q cipher ' 'ssh -V ' \
             'ssh target ' 'ssh target uptime' 'ssh target -p 22 ' 'echo tar'; do
  check "$input" "$input" '' '' expand-or-complete
done
check 'ssh -p 2222 tar' 'ssh -p 2222 tar' '' get expand-or-complete

# The fzf path shares the same replacement, while retaining Enter/Alt-Enter behavior.
host_rows+=$'\nother|->|192.0.2.2|user| | '
fzf_result=$'alt-enter\ntarget -> 192.0.2.1 user'
check 'ssh -p 2222 user@tar' 'ssh -p 2222 user@target' tar ' uptime'
fzf_result=$'enter\ntarget -> 192.0.2.1 user'
check 'ssh -J jump tar' 'ssh -J jump target' tar '' accept-line,reset-prompt
fzf_result=''
check 'ssh -J jump tar' 'ssh -J jump tar' tar '' reset-prompt
host_rows=''
check 'ssh -J jump missing' 'ssh -J jump missing' missing '' ''
check 'ssh -p 2222 ' 'ssh -p 2222 ' '' '' expand-or-complete
host_rows='target;echo|->|192.0.2.1|user| | '
check 'ssh tar' 'ssh target\;echo' tar

print -r -- "PASS: $checks completion checks"
