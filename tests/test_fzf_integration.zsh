#!/usr/bin/env zsh

# Test FZF integration and list formatting
# 测试用户界面逻辑 - FZF 列表生成

source "$(dirname "$0")/test_framework.zsh"
setup_test_env

test_generate_fzf_list_basic() {
  local host_data="alias-1|->|127.0.0.1| |[test desc]"
  local result=$(_fzf_list_generator "$host_data")
  
  assert_contains "Alias" "$result" "Generate header with column names"
  assert_contains "─────" "$result" "Generate header separator line"
  assert_contains "alias-1" "$result" "Include host data in formatted output"
  assert_not_contains "Tag" "$result" "Do not show Tag column for legacy five-field input"
}

test_generate_fzf_list_empty_input() {
  local result=$(_fzf_list_generator "")
  
  # 经 column 对齐后不应再包含管道分隔符，但应包含列名
  assert_contains "Alias" "$result" "Generate header even with empty input"
  assert_contains "─────" "$result" "Generate separator even with empty input"
}

test_generate_fzf_list_no_input() {
  # Test with default host list
  local result=$(_fzf_list_generator)
  
  assert_contains "alias-1" "$result" "Use default host list when no input provided"
  assert_contains "Bastion-Host" "$result" "Include multiple hosts from default list"
}

test_column_formatting() {
  local host_data="short|->|very-long-hostname-here.example.com| |[description]"
  local result=$(_fzf_list_generator "$host_data")
  
  # Should use column command to align properly
  assert_contains "short" "$result" "Format columns with proper alignment"
  assert_contains "very-long-hostname-here.example.com" "$result" "Handle long hostnames"
}

test_tag_column_visible_when_any_tag_exists() {
  local host_data=$'tagged|->|1.1.1.1|deploy|[\033[00;36mwork\033[0m]|[desc]'
  local result=$(_fzf_list_generator "$host_data")

  assert_contains "Tag" "$result" "Show Tag column when a host has Tag"
  assert_contains "work" "$result" "Preserve Tag value in formatted output"
}

test_tag_column_hidden_for_empty_six_field_tags() {
  local host_data="untagged|->|1.1.1.1| | |[desc]"
  local result=$(_fzf_list_generator "$host_data")

  assert_not_contains "Tag" "$result" "Hide Tag column when all Tag fields are empty"
  assert_contains "[desc]" "$result" "Preserve description after removing empty Tag column"
}

test_known_hosts_description_survives_tag_column_removal() {
  local host_data=$'known-host|->|known-host| | |[\033[00;34mknown_hosts\033[0m]'
  local result=$(_fzf_list_generator "$host_data")

  assert_not_contains "Tag" "$result" "Hide Tag column for known_hosts-only rows"
  assert_contains "known_hosts" "$result" "Preserve known_hosts description without Tag column"
}

test_extract_host_from_fzf_output() {
  # 直接验证 _set_lbuffer，避免只测试一段重复实现的 cut 命令。
  local LBUFFER="ssh "
  local fzf_line="alias-1     127.0.0.1     user     [desc]"

  _set_lbuffer "$fzf_line" true ""

  assert_equals "ssh alias-1" "$LBUFFER" "Set LBUFFER from fzf formatted line"
}

test_extract_host_from_pipe_output() {
  # 单候选路径使用管道分隔格式，也必须走真实函数。
  local LBUFFER="ssh "
  local direct_result="alias-1|->|127.0.0.1| |[desc]"

  _set_lbuffer "$direct_result" false ""

  assert_equals "ssh alias-1" "$LBUFFER" "Set LBUFFER from direct result format"
}

test_set_lbuffer_overwrites_existing_command() {
  local LBUFFER="ssh old-host"

  _set_lbuffer "new-host|->|10.0.0.1| | " false "old-host"

  assert_equals "ssh new-host" "$LBUFFER" "Replace existing ssh command with selected host"
}

test_multiple_host_formatting() {
  local host_data=$'host1|->|1.1.1.1| | \nhost2|->|2.2.2.2| |[desc2]'
  local result=$(_fzf_list_generator "$host_data")
  
  assert_contains "host1" "$result" "Include first host in multi-host formatting"
  assert_contains "host2" "$result" "Include second host in multi-host formatting"
  assert_contains "[desc2]" "$result" "Preserve descriptions in formatting"
}

test_special_characters_in_descriptions() {
  local host_data="test|->|1.1.1.1| |[desc with spaces and (parens)]"
  local result=$(_fzf_list_generator "$host_data")
  
  assert_contains "desc with spaces and (parens)" "$result" "Handle special characters in descriptions"
}

test_color_codes_in_descriptions() {
  # Description with ANSI color codes
  local host_data="test|->|1.1.1.1| |[\033[00;34mdesc\033[0m]"
  local result=$(_fzf_list_generator "$host_data")
  
  assert_contains "desc" "$result" "Preserve color codes in descriptions"
}

test_empty_description_handling() {
  local host_data="test|->|1.1.1.1| | "
  local result=$(_fzf_list_generator "$host_data")
  
  assert_contains "test" "$result" "Handle hosts with empty descriptions"
  assert_not_contains "[]" "$result" "Don't show empty description brackets"
}

# assert_not_contains provided by test_framework.zsh

# Run tests
test_generate_fzf_list_basic
test_generate_fzf_list_empty_input
test_generate_fzf_list_no_input
test_column_formatting
test_tag_column_visible_when_any_tag_exists
test_tag_column_hidden_for_empty_six_field_tags
test_known_hosts_description_survives_tag_column_removal
test_extract_host_from_fzf_output
test_extract_host_from_pipe_output
test_set_lbuffer_overwrites_existing_command
test_multiple_host_formatting
test_special_characters_in_descriptions
test_color_codes_in_descriptions
test_empty_description_handling
finish_tests
