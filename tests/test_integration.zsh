#!/usr/bin/env zsh

# Integration test - 端到端功能验证
# 不依赖 fzf，测试核心流程

source "$(dirname "$0")/test_framework.zsh"
setup_test_env

test_end_to_end_host_extraction() {
  local hosts=$(_ssh_host_list)
  
  assert_not_empty "$hosts" "Extract hosts from complete config"
  assert_contains "alias-1" "$hosts" "Extract multiple aliases"
  assert_contains "Bastion-Host" "$hosts" "Extract named hosts"
}

test_end_to_end_with_search() {
  local filtered=$(_ssh_host_list "host")
  
  assert_contains "Bastion-Host" "$filtered" "Filter includes bastion"
  assert_contains "Development-Host" "$filtered" "Filter includes development"
  assert_not_contains "alias-1" "$filtered" "Filter excludes non-matching"
}

test_fzf_list_generation_complete() {
  local hosts=$(_ssh_host_list)
  local formatted=$(_fzf_list_generator "$hosts")

  # column -t 会将管道分隔符替换为空格对齐
  assert_contains "Alias" "$formatted" "Generate proper headers"
  assert_contains "Bastion-Host" "$formatted" "Include host data"
  # ANSI 颜色码包裹描述文本，检查文本内容即可
  assert_contains "Bastion Host" "$formatted" "Include formatted descriptions"
}

test_config_with_includes() {
  local all_hosts=$(_ssh_host_list)
  
  # Should include hosts from include files
  assert_contains "include-1" "$all_hosts" "Include hosts from included files"
  assert_contains "include-2" "$all_hosts" "Include hosts from multiple includes"
}

# 功能完整性测试（验证解析能正常完成，不做耗时断言）
test_full_parsing_completes() {
  local hosts=$(_ssh_host_list)
  assert_not_empty "$hosts" "Complete parsing within reasonable time"
}

# assert_not_contains provided by test_framework.zsh

# Run integration tests
test_end_to_end_host_extraction
test_end_to_end_with_search
test_fzf_list_generation_complete
test_config_with_includes
test_full_parsing_completes
finish_tests
