#!/usr/bin/env zsh

source "${0:A:h}/test_framework.zsh"
unsetopt bgnice
fzf_ssh_default_completion=expand-or-complete
zle() { return 0; }
bindkey() { return 0; }
source "${0:A:h:h}/zsh-ssh.zsh"
preexec_functions=()
SSH_CONFIG_FILE="${0:A:h}/ssh_config_completion"
ZSH_SSH_COMMANDS=(ssh sftp ssht)
ZSH_SSH_INCLUDE_KNOWN_HOSTS=0
ZSH_SSH_SORT_RECENT=1
recent_test_dir=$(mktemp -d)
ZSH_SSH_RECENT_FILE="$recent_test_dir/order/recent"

_zsh_ssh_record_recent '' '' 'ssh alpha'
_zsh_ssh_record_recent '' '' 'ssh zeta'
_zsh_ssh_record_recent '' '' 'ssh alpha || true'
assert_equals $'alpha\nzeta' "$(<"$ZSH_SSH_RECENT_FILE")" 'Keep unique hosts in submission order'
_zsh_ssh_record_recent '' '' 'sftp -s subsystem beta'
_zsh_ssh_record_recent '' '' 'ssht -p 2222 $USER@gamma'
assert_equals $'gamma\nbeta\nalpha\nzeta' "$(<"$ZSH_SSH_RECENT_FILE")" 'Share option parsing with SFTP and wrappers'

before=$(<"$ZSH_SSH_RECENT_FILE")
for input in 'ssh $HOST' 'ssh "$HOST"' 'ssh > logfile alpha' 'ssh | true' \
             'ssh user@${H:-a@tar}' 'ssh user@$(echo a@tar)' 'ssh -p ' \
             'ssh' 'echo ssh alpha' 'sftp user@target:/path'; do
  _zsh_ssh_record_recent '' '' "$input"
done
assert_equals "$before" "$(<"$ZSH_SSH_RECENT_FILE")" 'Skip missing, dynamic, and unsupported destinations'
ZSH_SSH_SORT_RECENT=0
_zsh_ssh_record_recent '' '' 'ssh disabled'
assert_equals "$before" "$(<"$ZSH_SSH_RECENT_FILE")" 'Do not record when MRU is disabled'
ZSH_SSH_SORT_RECENT=1

setopt ksharrays shwordsplit posixbuiltins globsubst noclobber
unsetopt appendcreate
ZSH_SSH_RECENT_FILE="$recent_test_dir/options/recent"
_zsh_ssh_record_recent '' '' 'ssh alpha'
unsetopt ksharrays shwordsplit posixbuiltins globsubst noclobber
setopt appendcreate
assert_equals alpha "$(<"$ZSH_SSH_RECENT_FILE")" 'Localize array, parsing, and file-creation options'

ZSH_SSH_RECENT_FILE="$recent_test_dir/capacity"
for i in {1..200}; do print -r -- "host-$i"; done > "$ZSH_SSH_RECENT_FILE"
_zsh_ssh_record_recent '' '' 'ssh newest'
assert_equals 200 "$(command wc -l < "$ZSH_SSH_RECENT_FILE" | command tr -d ' ')" 'Keep at most 200 recent hosts'
assert_equals newest "$(command head -1 "$ZSH_SSH_RECENT_FILE")" 'Put the latest host first'
assert_line_absent host-200 "$(<"$ZSH_SSH_RECENT_FILE")" 'Evict the oldest host at capacity'

ZSH_SSH_RECENT_FILE="$recent_test_dir/safe"
print -r -- original > "$recent_test_dir/sentinel"
ln -s "$recent_test_dir/sentinel" "$ZSH_SSH_RECENT_FILE.tmp"
before_umask=$(umask)
_zsh_ssh_record_recent '' '' 'ssh alpha'
assert_equals original "$(<"$recent_test_dir/sentinel")" 'Leave a pre-existing temporary symlink target untouched'
assert_equals "$before_umask" "$(umask)" 'Do not change the calling shell umask'
zmodload zsh/stat
zstat -H recent_stat "$ZSH_SSH_RECENT_FILE"
assert_equals 0 "$(( recent_stat[mode] & 077 ))" 'Keep recent state private'

mkdir "$recent_test_dir/bin"
print -rl -- '#!/bin/sh' 'exit 1' > "$recent_test_dir/bin/mv"
chmod +x "$recent_test_dir/bin/mv"
PATH="$recent_test_dir/bin:$PATH" _zsh_ssh_record_recent '' '' 'ssh write-failed'
assert_equals alpha "$(<"$ZSH_SSH_RECENT_FILE")" 'Keep the previous snapshot when rename fails'
_zsh_ssh_record_recent '' '' 'ssh after-failure'
assert_equals after-failure "$(command head -1 "$ZSH_SSH_RECENT_FILE")" 'Release the lock after a failed update'
local_tmp_files=("$ZSH_SSH_RECENT_FILE".??????????(N))
assert_equals 0 "$#local_tmp_files" 'Clean up only this update temporary file'

ZSH_SSH_RECENT_FILE="$recent_test_dir/sorted"
print -rl -- zeta alpha > "$ZSH_SSH_RECENT_FILE"
rows=$'alpha|->|a| | | \nzeta|->|z| | | \nunused|->|u| | | '
expected=$'zeta|->|z| | | \nalpha|->|a| | | \nunused|->|u| | | '
assert_equals "$expected" "$(print -r -- "$rows" | _zsh_ssh_sort_recent)" 'Order recent candidates first and preserve the rest'
result=$( _zsh_ssh_sort_recent() { return 1; }; _ssh_host_list )
assert_contains target "$result" 'Keep candidates when optional recent sorting fails'

# Pause an actual update midway through its output, before the atomic rename.
zmodload zsh/zselect
zmodload zsh/system
wait_for_marker() {
  local marker="$1" deadline=$(( SECONDS + 10 ))
  while [[ ! -e "$marker" ]] && (( SECONDS < deadline )); do
    zselect -t 1
  done
  [[ -e "$marker" ]]
}

ZSH_SSH_RECENT_FILE="$recent_test_dir/transaction"
old_snapshot=$'old-1\nold-2'
first_snapshot=$'first\nold-1\nold-2'
second_snapshot=$'second\nfirst\nold-1\nold-2'
print -r -- "$old_snapshot" > "$ZSH_SSH_RECENT_FILE"
mkfifo "$recent_test_dir/release"
exec {release_fd}<> "$recent_test_dir/release"
(
  print() {
    # Only the state write is split; the production lock/rename path is intact.
    if [[ "$1" == -rl && "$2" == -- ]]; then
      builtin print -r -- "$3"
      : > "$recent_test_dir/partial-ready"
      local release
      read -r -t 10 -u "$release_fd" release || return 1
      builtin print -rl -- "${@:4}"
    else
      builtin print "$@"
    fi
  }
  _zsh_ssh_record_recent '' '' 'ssh first'
) &
first_writer=$!
wait_for_marker "$recent_test_dir/partial-ready"
assert_equals 0 "$?" 'Reach the partial temporary write barrier'
assert_equals "$old_snapshot" "$(<"$ZSH_SSH_RECENT_FILE")" 'Keep the published snapshot complete during a partial write'

(
  local -i snapshots=0
  local snapshot
  while [[ ! -e "$recent_test_dir/stop-reader" ]]; do
    snapshot=$(<"$ZSH_SSH_RECENT_FILE")
    if [[ "$snapshot" != "$old_snapshot" && "$snapshot" != "$first_snapshot" &&
          "$snapshot" != "$second_snapshot" ]]; then
      print -r -- invalid > "$recent_test_dir/reader-result"
      exit 1
    fi
    (( snapshots++ ))
    : > "$recent_test_dir/reader-ready"
    zselect -t 1
  done
  print -r -- "$snapshots" > "$recent_test_dir/reader-result"
) &
reader=$!
wait_for_marker "$recent_test_dir/reader-ready"
assert_equals 0 "$?" 'Read concurrently while the temporary file is incomplete'
(
  : > "$recent_test_dir/second-started"
  _zsh_ssh_record_recent '' '' 'ssh second'
) &
second_writer=$!
wait_for_marker "$recent_test_dir/second-started"
assert_equals 0 "$?" 'Start the second writer before releasing the first'
( zsystem flock -t 0 "$ZSH_SSH_RECENT_FILE.lock" ) 2>/dev/null
assert_equals 1 "$?" 'Hold the stable lock through the entire state write'
print -r -u "$release_fd" -- release
wait "$first_writer" "$second_writer"
: > "$recent_test_dir/stop-reader"
wait "$reader"
assert_equals 0 "$?" 'Expose only complete snapshots to concurrent readers'
assert_equals yes "$([[ "$(<"$recent_test_dir/reader-result")" == <1-> ]] && print yes || print no)" 'Observe at least one snapshot during the overlapping update'
assert_equals "$second_snapshot" "$(<"$ZSH_SSH_RECENT_FILE")" 'Serialize two overlapping read-modify-write transactions'
exec {release_fd}>&-

ZSH_SSH_RECENT_FILE="$recent_test_dir/concurrent"
plugin_file="${0:A:h:h}/zsh-ssh.zsh"
typeset -a writers
for i in {1..30}; do
  zsh -f -c '
    fzf_ssh_default_completion=expand-or-complete
    zle() { return 0; }; bindkey() { return 0; }
    source "$1"
    preexec_functions=()
    ZSH_SSH_SORT_RECENT=1
    ZSH_SSH_RECENT_FILE=$2
    _zsh_ssh_record_recent "" "" "ssh parallel-$3"
  ' recent-worker "$plugin_file" "$ZSH_SSH_RECENT_FILE" "$i" &
  writers+=($!)
done
for writer in "${writers[@]}"; do wait "$writer"; done
assert_equals 30 "$(command sort -u "$ZSH_SSH_RECENT_FILE" | command wc -l | command tr -d ' ')" 'Keep all 30 concurrent submissions'
for i in {1..30}; do
  assert_line_present "parallel-$i" "$(<"$ZSH_SSH_RECENT_FILE")" "Retain concurrent host $i"
done
command rm -rf -- "$recent_test_dir"
finish_tests
