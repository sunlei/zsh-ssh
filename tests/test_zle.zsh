#!/usr/bin/env zsh

source "${0:A:h}/test_framework.zsh"
zmodload zsh/zpty || exit 1

test_dir=$(mktemp -d)
plugin_file="${0:A:h:h}/zsh-ssh.zsh"
config_file="${0:A:h}/ssh_config_completion"

read_prompt() {
  local output
  zpty -r ssh_test output "${1-*__SSH_READY__ }"
  REPLY="$output"
}

cancel_line() {
  zpty -w -n ssh_test $'\x03'
  read_prompt
}

TERM=xterm zpty ssh_test zsh -f
{
  # Split the marker so terminal echo cannot be mistaken for the ready prompt.
  zpty -w ssh_test "PROMPT='__SSH_''READY__ '; RPROMPT=''; HISTSIZE=100"
  read_prompt
  zpty -w ssh_test "fzf_ssh_default_completion=expand-or-complete; SSH_CONFIG_FILE=${(q)config_file}; ZSH_SSH_SORT_RECENT=1; ZSH_SSH_RECENT_FILE=${(q)test_dir}/recent; source ${(q)plugin_file}; ssh() { print -r -- \"MOCK_SSH:\${(j:,:)@}\"; return 255; }; sftp() { return 255; }; fzf() { command cat >/dev/null; print -r -- \"\$test_fzf_result\"; }; inspect_buffer() { print -r -- \"LIVE_BUFFER:\$BUFFER\"; zle redisplay; }; zle -N inspect_buffer; bindkey '^X' inspect_buffer"
  read_prompt

  zpty -w -n ssh_test $'ssh -p 2222 tar\t\x18'
  read_prompt '*LIVE_BUFFER:*__SSH_READY__ '
  assert_contains 'LIVE_BUFFER:ssh -p 2222 target' "$REPLY" 'Complete options in a real ZLE widget'
  cancel_line

  zpty -w -n ssh_test $'ssh $USER@tar\t\x18'
  read_prompt '*LIVE_BUFFER:*__SSH_READY__ '
  assert_contains 'LIVE_BUFFER:ssh $USER@target' "$REPLY" 'Preserve a dynamic username in real ZLE'
  cancel_line
  assert_equals no "$([[ -e "$test_dir/recent" ]] && print yes || print no)" 'Do not record canceled editing'

  zpty -w ssh_test "test_fzf_result=\$'alt-enter\ntarget -> 192.0.2.1 user'"
  read_prompt
  zpty -w -n ssh_test $'ssh \t\x18'
  read_prompt '*LIVE_BUFFER:*__SSH_READY__ '
  assert_contains 'LIVE_BUFFER:ssh target' "$REPLY" 'Keep Alt-Enter in the editing buffer'
  assert_equals no "$([[ -e "$test_dir/recent" ]] && print yes || print no)" 'Do not record Alt-Enter before execution'
  cancel_line

  zpty -w ssh_test "test_fzf_result=\$'enter\ntarget -> 192.0.2.1 user'"
  read_prompt
  zpty -w -n ssh_test $'ssh \t'
  read_prompt '*MOCK_SSH:*__SSH_READY__ '
  assert_contains 'MOCK_SSH:target' "$REPLY" 'Execute the selected destination on Enter'
  assert_equals target "$(<"$test_dir/recent")" 'Record a submitted target even when SSH returns 255'

  zpty -w ssh_test 'alias s=ssh; HISTSIZE=0'
  read_prompt
  zpty -w ssh_test 's other'
  read_prompt '*MOCK_SSH:*__SSH_READY__ '
  assert_contains 'MOCK_SSH:other' "$REPLY" 'Execute the expanded SSH alias'
  assert_equals $'other\ntarget' "$(<"$test_dir/recent")" 'Record aliases without depending on history'
} always {
  zpty -d ssh_test
  command rm -rf -- "$test_dir"
}
finish_tests
