#!/usr/bin/env zsh

source "${0:A:h}/test_framework.zsh"
zsh -f "${0:A:h}/completion.zsh"
assert_equals 0 "$?" 'Retain the original command-preservation checks'

fzf_ssh_default_completion=expand-or-complete
zle() { [[ "$1" == -N ]] || zle_calls+=("$1"); return 0; }
bindkey() { return 0; }
ZSH_SSH_SORT_RECENT=0
source "${0:A:h:h}/zsh-ssh.zsh"
preexec_functions=()
SSH_CONFIG_FILE="${0:A:h}/ssh_config_completion"
ZSH_SSH_KNOWN_HOSTS_FILE=/nonexistent/known_hosts
ZSH_SSH_INCLUDE_KNOWN_HOSTS=0
ZSH_SSH_COMMANDS=(ssh sftp ssht)
fzf() { command cat >/dev/null; print -rl -- "$@" >| "$fzf_args_file"; print -r -- "$fzf_result"; }
fzf_args_file=$(mktemp)
fzf_result=$'alt-enter\ntarget -> 192.0.2.1 user'

check_completion() {
  local LBUFFER="$1" RBUFFER="${4-}"
  local -a zle_calls
  fzf_complete_ssh
  assert_equals "$2" "$LBUFFER" "Preserve command semantics for: $1"
  assert_equals "${3-reset-prompt}" "${(j:,:)zle_calls}" "Use the expected widget for: $1"
  assert_equals "${4-}" "$RBUFFER" "Keep text after the cursor for: $1"
}

check_completion 'ssh $USER@tar' 'ssh $USER@target'
check_completion 'ssh ${USER}@tar' 'ssh ${USER}@target'
check_completion 'ssh team-${USER}@tar' 'ssh team-${USER}@target'
check_completion 'ssh $USER@' 'ssh $USER@target'
check_completion 'ssh user@"tar"' 'ssh user@target'
check_completion 'ssht -p 2222 tar' 'ssht -p 2222 target'
check_completion 'sftp -P 2222 tar' 'sftp -P 2222 target'
check_completion 'sftp -p tar' 'sftp -p target'
check_completion 'sftp -s subsystem tar' 'sftp -s subsystem target'
check_completion 'sftp -X buffer=32768 tar' 'sftp -X buffer=32768 target'
check_completion 'sftp -r tar' 'sftp -r target'
check_completion 'ssh -p 2222 tar' 'ssh -p 2222 target' reset-prompt ' uptime'
check_completion 'ssh -o "ProxyCommand=nc %h %p 2>/dev/null" tar' 'ssh -o "ProxyCommand=nc %h %p 2>/dev/null" target'

for input in 'ssh >' 'ssh |' 'ssh ||' 'ssh ;' 'ssh 2>' 'ssh -p > out' \
             'ssh &>' 'ssh &>>' 'ssh &!' 'ssh &|' 'ssh ;;' 'ssh #comment' \
             'ssh > out tar' 'ssh {fd}> out tar' 'ssh "$USER@tar"' \
             "ssh 'bob'@tar" 'ssh $(id -un)@tar' 'ssh user@$(echo a@tar)' \
             'ssh user@${H:-a@tar}' 'ssh user@$(echo a@tar' \
             'ssh user@${H:-a@tar' 'ssh $HOST' 'ssh "$HOST"' \
             'ssh ssh://user@tar:2222' 'sftp user@tar:file' \
             'sftp user@tar:/path' 'sftp -s subsystem' 'sftp -X ' \
             'ssh target uptime' 'ssh tar '; do
  check_completion "$input" "$input" expand-or-complete
done

setopt ksharrays shwordsplit posixbuiltins globsubst
check_completion 'ssh $USER@tar' 'ssh $USER@target'
unsetopt ksharrays shwordsplit posixbuiltins globsubst

check_completion 'ssh ' 'ssh target'
fzf_result=$'enter\ntarget -> 192.0.2.1 user'
check_completion 'ssh ' 'ssh target' accept-line,reset-prompt
fzf_result=''
check_completion 'ssh ' 'ssh ' reset-prompt
ZSH_SSH_SORT_RECENT=1
ZSH_SSH_RECENT_FILE=/nonexistent/zsh-ssh-recent
fzf_result=$'alt-enter\ntarget -> 192.0.2.1 user'
check_completion 'ssh ' 'ssh target'
assert_line_present --tiebreak=index "$(<"$fzf_args_file")" 'Use MRU order only to break equal fzf scores'
command rm -f -- "$fzf_args_file"
finish_tests
