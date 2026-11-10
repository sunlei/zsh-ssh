#!/usr/bin/env zsh

# Test host list generation and filtering
# 测试主机列表生成逻辑 - 核心业务功能

source "$(dirname "$0")/test_framework.zsh"
setup_test_env

test_extract_basic_hosts() {
  local result=$(_ssh_host_list)
  
  assert_contains "alias-1|->|127.0.0.1" "$result" "Extract basic host alias"
  assert_contains "Bastion-Host|->|3.3.3.3" "$result" "Extract host with description"
  assert_contains "Development-Host|->|9.9.9.9" "$result" "Extract host without description"
}

test_structured_host_lines() {
  local result=$(_ssh_host_list)

  assert_line_present "Development-Host|->|9.9.9.9| | | " "$result" "Emit host without user or description as a full row"
  assert_line_present "Equals-Host|->|10.10.10.10|testuser| | " "$result" "Emit parsed user field in the expected column"
  assert_line_present "cross-block-host|->|36.36.36.36|crossuser| | " "$result" "Emit merged cross-block fields in one row"
}

test_extract_multiple_aliases() {
  local result=$(_ssh_host_list)
  
  # Should extract each alias separately  
  assert_contains "alias-1|->|127.0.0.1" "$result" "Extract first alias"
  assert_contains "alias-2|->|127.0.0.1" "$result" "Extract second alias"
  assert_contains "alias-3|->|127.0.0.1" "$result" "Extract third alias"
}

test_extract_descriptions() {
  local result=$(_ssh_host_list)
  
  # Description should be formatted with ANSI colors - includes color codes
  assert_contains "multiple alias test" "$result" "Extract and format host description"
  assert_contains "Bastion Host" "$result" "Extract bastion host description"
}

test_filter_wildcard_hosts() {
  local result=$(_ssh_host_list)
  
  # Should NOT contain wildcard hosts like "Host *"
  assert_not_contains "Host *" "$result" "Filter out wildcard hosts"
}

test_search_filtering() {
  local result=$(_ssh_host_list "bastion")
  
  assert_contains "Bastion-Host" "$result" "Filter hosts by search term (case insensitive)"
  assert_line_absent "Development-Host|->|9.9.9.9| | | " "$result" "Exclude non-matching host row"
}

test_search_after_option_like_args() {
  local result=$(_ssh_host_list -p "bastion")

  assert_contains "Bastion-Host" "$result" "Ignore ssh option-like args before search term"
  assert_not_contains "Development-Host" "$result" "Apply search term after skipped option-like arg"
}

test_search_case_insensitive() {
  local result_upper=$(_ssh_host_list "BASTION")  
  local result_lower=$(_ssh_host_list "bastion")
  
  assert_equals "$result_lower" "$result_upper" "Case insensitive search"
}

test_empty_search_returns_all() {
  local result_all=$(_ssh_host_list)
  local result_empty=$(_ssh_host_list "")
  
  assert_equals "$result_all" "$result_empty" "Empty search returns all hosts"
}

test_no_match_returns_empty() {
  local result=$(_ssh_host_list "nonexistent-host-xyz")
  
  assert_equals "" "$result" "No matching hosts returns empty result"
}

test_handle_include_hosts() {
  local result=$(_ssh_host_list "include")
  
  assert_contains "include-1" "$result" "Include hosts from included files"
  assert_contains "include-2" "$result" "Include hosts from multiple included files"
}

test_sort_and_unique() {
  local result=$(_ssh_host_list)
  local sorted=$(printf "%s\n" "$result" | command sort -u)
  
  assert_equals "$sorted" "$result" "Sort host list deterministically"
  assert_contains_count "1" "alias-1|->|" "$result" "Ensure normal hosts are unique in results"
  assert_contains_count "1" "include-2|->|" "$result" "Deduplicate hosts included through multiple paths"
}

test_filter_negated_hosts() {
  local result=$(_ssh_host_list)
  # ! 前缀是 SSH config 的取反模式，不应出现在补全列表中
  assert_not_contains "!negated-host" "$result" "Filter out negated host patterns"
}

test_filter_match_directive() {
  local result=$(_ssh_host_list)
  # Match 块不应产生主机条目
  assert_not_contains "*.example.com" "$result" "Filter out Match directive entries"
}

test_key_equals_value_syntax() {
  local result=$(_ssh_host_list)
  # Host=value 和 Hostname=value 等号语法应被正确解析
  assert_contains "Equals-Host" "$result" "Parse Host with equals syntax"
  assert_contains "10.10.10.10" "$result" "Parse Hostname with equals syntax"
}

test_hosts_without_blank_line() {
  local result=$(_ssh_host_list)
  # 紧邻的 Host 块（无空行分隔）应被正确拆分为独立条目
  assert_contains "NoBlank-Host-1" "$result" "Parse first host without blank line separator"
  assert_contains "NoBlank-Host-2" "$result" "Parse second host without blank line separator"
}

test_cross_block_alias_dedup() {
  local result=$(_ssh_host_list)
  # 跨块重复 alias：显式 HostName 优先，只出现一次
  local count=$(echo "$result" | grep -c "issue34-host|->|")
  assert_equals "1" "$count" "Cross-block alias appears exactly once"
  assert_contains "issue34-host|->|34.34.34.34" "$result" "Cross-block alias maps to explicit HostName"
  # 其他 IP alias 正常出现
  assert_contains "35.35.35.35|->|35.35.35.35" "$result" "IP alias in shared block maps to itself"
}

test_cross_block_field_merge() {
  local result=$(_ssh_host_list)
  # User 在第一块，HostName 在第二块，两者都应保留
  assert_contains "cross-block-host|->|36.36.36.36|crossuser" "$result" "Merge User and HostName from different blocks"
}

test_explicit_hostname_conflict() {
  local result=$(_ssh_host_list)
  # 两块都有显式 HostName，first-match wins
  local count=$(echo "$result" | grep -c "hn-conflict-host|->|")
  assert_equals "1" "$count" "Conflicting HostName alias appears exactly once"
  assert_contains "hn-conflict-host|->|80.80.80.80" "$result" "First explicit HostName wins on conflict"
}

test_orphan_record_no_pollution() {
  local result=$(_ssh_host_list)
  # 无 Host 行的 record 不应产生条目
  assert_not_contains "88.88.88.88|->|" "$result" "Record without Host line produces no alias entry"
  assert_not_contains "orphaned-user" "$result" "Orphaned User directive does not leak"
}

test_multi_alias_hostname_mapping() {
  local result=$(_ssh_host_list)
  # 无 HostName：每个 alias 映射到自身
  assert_contains "Multi-Alias-Host|->|Multi-Alias-Host" "$result" "Alias maps to itself when no HostName"
  assert_contains "40.40.40.40|->|40.40.40.40" "$result" "IP alias maps to itself when no HostName"
  # 有 HostName：所有 alias 映射到显式值
  assert_contains "Named-Multi-Alias|->|70.70.70.70" "$result" "Alias maps to explicit HostName"
  assert_contains "60.60.60.60|->|70.70.70.70" "$result" "IP alias maps to explicit HostName"
}

test_tag_column_output() {
  local result=$(_ssh_host_list)
  local work_line=$(printf "%s\n" "$result" | command grep -F "Tagged-Work-Host|->|")
  local work_tag=$(printf "%s\n" "$work_line" | command awk -F '|' '{ print $5 }')
  local development_fields=$(printf "%s\n" "$result" | command awk -F '|' '$1 == "Development-Host" { print NF }')

  assert_contains "work" "$work_tag" "Emit parsed Tag in the expected column"
  assert_contains "00;36mwork" "$work_tag" "Format Tag with cyan ANSI color"
  assert_equals "6" "$development_fields" "Keep six fields for hosts without Tag"
}

test_tag_filtering() {
  local result=$(_ssh_host_list "tag:work")

  assert_contains "Tagged-Work-Host" "$result" "Filter hosts by Tag"
  assert_not_contains "Tagged-Personal-Host" "$result" "Exclude non-matching Tag"
}

test_tag_filtering_case_insensitive() {
  local result_upper=$(_ssh_host_list "tag:WORK")
  local result_lower=$(_ssh_host_list "tag:work")

  assert_equals "$result_lower" "$result_upper" "Tag filtering is case insensitive"
}

test_tag_filtering_literal_query() {
  local result=$(_ssh_host_list "tag:[")

  assert_equals "" "$result" "Tag filtering treats query as literal text"
}

test_tag_first_value_wins() {
  local result=$(_ssh_host_list)
  local tag=$(printf "%s\n" "$result" | command awk -F '|' '$1 == "Tagged-First-Wins" { print $5 }')

  assert_contains "first" "$tag" "First Tag value wins"
  assert_not_contains "second" "$tag" "Later Tag values do not override first Tag"
}

# Run tests
test_extract_basic_hosts
test_structured_host_lines
test_extract_multiple_aliases
test_extract_descriptions
test_filter_wildcard_hosts
test_search_filtering
test_search_after_option_like_args
test_search_case_insensitive
test_empty_search_returns_all
test_no_match_returns_empty
test_handle_include_hosts
test_sort_and_unique
test_filter_negated_hosts
test_filter_match_directive
test_key_equals_value_syntax
test_hosts_without_blank_line
test_cross_block_alias_dedup
test_cross_block_field_merge
test_explicit_hostname_conflict
test_orphan_record_no_pollution
test_multi_alias_hostname_mapping
test_tag_column_output
test_tag_filtering
test_tag_filtering_case_insensitive
test_tag_filtering_literal_query
test_tag_first_value_wins
finish_tests
