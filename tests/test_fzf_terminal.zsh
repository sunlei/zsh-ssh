#!/usr/bin/env zsh

source "${0:A:h}/test_framework.zsh"
zmodload zsh/zpty || exit 1
zmodload zsh/zselect || exit 1
command -v fzf >/dev/null || exit 1

test_dir=$(mktemp -d)
plugin_file="$REPO_ROOT/zsh-ssh.zsh"
config_file="${0:A:h}/ssh_config_completion"
export FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE=/dev/null
export SHELL="$(command -v zsh)" TEST_SSH_LOG="$test_dir/ssh"
mkdir "$test_dir/bin"
# A real executable also intercepts preview subprocesses, unlike a Shell function.
cat > "$test_dir/bin/ssh" <<'EOF'
#!/bin/sh
if [ "$1" = -T ] && [ "$2" = -G ]; then
  printf '%s\n' "$*" >> "$TEST_SSH_LOG.preview"
  printf '%s\n' 'user fixture-user' "hostname preview-$3.invalid" 'port 2222'
else
  printf '%s\n' "$*" >> "$TEST_SSH_LOG.execution"
  printf 'MOCK_SSH:%s\n' "$*"
  exit 255
fi
EOF
chmod +x "$test_dir/bin/ssh"

send_keys() {
  terminal_output=''
  zpty -w -n ssh_fzf "$1"
}

expect_terminal() {
  local pattern="$1" description="$2" chunk cursor_requests=''
  local deadline=$(( SECONDS + 10 )) matched=no
  while (( SECONDS < deadline )); do
    if zpty -r ssh_fzf chunk; then
      terminal_output+="$chunk"
      # zpty is not a terminal emulator; answer fzf's cursor-position request.
      cursor_requests+="$chunk"
      while [[ "$cursor_requests" == *$'\e[6n'* ]]; do
        zpty -w -n ssh_fzf $'\e[1;1R'
        cursor_requests=${cursor_requests#*$'\e[6n'}
      done
      if [[ "$terminal_output" == ${~pattern} ]]; then
        matched=yes
        break
      fi
    else
      zpty -t ssh_fzf || break
      zselect -t 1
    fi
  done
  assert_equals yes "$matched" "$description"
  if [[ "$matched" != yes ]]; then
    (( ${#terminal_output} > 1200 )) && terminal_output=${terminal_output[-1200,-1]}
    print -r -- "Terminal output: ${(qqq)terminal_output}"
  fi
  [[ "$matched" == yes ]]
}

run_terminal_test() {
  # Split the prompt marker to distinguish the prompt from terminal echo.
  zpty -w ssh_fzf "stty rows 40 cols 120; PROMPT='__SSH_''READY__ '; RPROMPT=''; bindkey -e"
  expect_terminal '*__SSH_READY__ *' 'Start a sized interactive terminal' || return
  send_keys "PATH=${(q)test_dir}/bin:\$PATH; fzf_ssh_default_completion=expand-or-complete; SSH_CONFIG_FILE=${(q)config_file}; ZSH_SSH_SORT_RECENT=1; ZSH_SSH_RECENT_FILE=${(q)test_dir}/recent; source ${(q)plugin_file}; inspect_buffer() { print -r -- \"LIVE_BUFFER:\$BUFFER\"; zle redisplay; }; zle -N inspect_buffer; bindkey '^X' inspect_buffer"$'\n'
  expect_terminal '*__SSH_READY__ *' 'Load the plugin with isolated SSH executables' || return

  send_keys $'ssh \t'
  expect_terminal '*SSH Remote >*' 'Open the actual fzf picker from ZLE' || return
  send_keys target
  expect_terminal '*preview-target.invalid*' 'Render output from the actual preview pipeline' || return
  assert_line_present '-T -G target' "$(<"$TEST_SSH_LOG.preview")" 'Preview the selected alias with SSH configuration flags'
  send_keys $'\e\r'
  expect_terminal '*__SSH_READY__ *' 'Leave real fzf with Alt-Enter' || return
  send_keys $'\x18'
  expect_terminal '*LIVE_BUFFER:*__SSH_READY__ *' 'Return Alt-Enter to the editing widget' || return
  assert_contains 'LIVE_BUFFER:ssh target' "$terminal_output" 'Keep the selected alias editable with real fzf'
  assert_equals no "$([[ -e "$TEST_SSH_LOG.execution" || -e "$test_dir/recent" ]] && print yes || print no)" 'Do not execute or record Alt-Enter'
  send_keys $'\x03'
  expect_terminal '*__SSH_READY__ *' 'Cancel the unsubmitted editing buffer' || return

  send_keys $'ssh \t'
  expect_terminal '*SSH Remote >*' 'Reopen fzf for Enter selection' || return
  send_keys other
  expect_terminal '*preview-other.invalid*' 'Update the preview after filtering' || return
  send_keys $'\r'
  expect_terminal '*MOCK_SSH:other*__SSH_READY__ *' 'Execute the real fzf Enter selection' || return
  assert_equals other "$(<"$TEST_SSH_LOG.execution")" 'Execute only the selected destination'
  assert_equals other "$(<"$test_dir/recent")" 'Record the submitted real fzf selection'

  send_keys $'ssh -p 2222 \t'
  expect_terminal '*preview-other.invalid*' 'Start the picker with the recent alias first' || return
  send_keys $'\t'
  expect_terminal '*preview-target.invalid*' 'Move down with the actual Tab binding' || return
  send_keys $'\e[Z'
  expect_terminal '*preview-other.invalid*' 'Move up with the actual Shift-Tab binding' || return
  send_keys $'\e'
  expect_terminal '*__SSH_READY__ *' 'Cancel the actual fzf picker with Escape' || return
  send_keys $'\x18'
  expect_terminal '*LIVE_BUFFER:*__SSH_READY__ *' 'Inspect the buffer after fzf cancellation' || return
  assert_contains 'LIVE_BUFFER:ssh -p 2222 ' "$terminal_output" 'Preserve the original command when fzf is canceled'
  assert_equals other "$(<"$TEST_SSH_LOG.execution")" 'Do not execute a canceled picker selection'
  assert_equals other "$(<"$test_dir/recent")" 'Do not change recency for a canceled picker'
}

TERM=xterm zpty -b ssh_fzf zsh -f
{
  run_terminal_test
} always {
  zpty -d ssh_fzf
  command rm -rf -- "$test_dir"
}
finish_tests
