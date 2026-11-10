#!/usr/bin/env zsh

# Test runner for zsh-ssh plugin
# 简洁实用的测试执行器

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="$SCRIPT_DIR/tests"

# Check dependencies
check_dependencies() {
  if ! command -v zsh >/dev/null 2>&1; then
    echo "${RED}Error: zsh is required but not installed${NC}" >&2
    exit 1
  fi
  
  if ! command -v awk >/dev/null 2>&1; then
    echo "${RED}Error: awk is required but not installed${NC}" >&2
    exit 1
  fi

  if ! command -v fzf >/dev/null 2>&1; then
    echo "${RED}Error: fzf is required but not installed${NC}" >&2
    exit 1
  fi

  if ! command -v column >/dev/null 2>&1; then
    echo "${RED}Error: column is required but not installed${NC}" >&2
    exit 1
  fi

  if ! command -v realpath >/dev/null 2>&1; then
    echo "${RED}Error: realpath is required but not installed (try: brew install coreutils)${NC}" >&2
    exit 1
  fi
}

# 判断文件是否是真正的测试套件，避免把共享框架当成测试执行。
is_test_suite() {
  local test_file="$1"
  [[ -f "$test_file" && "$(basename "$test_file")" != "test_framework.zsh" ]]
}

# 统一生成可运行测试列表，避免错误提示暴露内部 helper 文件。
print_available_tests() {
  local test_file test_name

  for test_file in "$TEST_DIR"/test_*.zsh; do
    if is_test_suite "$test_file"; then
      test_name="$(basename "$test_file")"
      test_name="${test_name#test_}"
      echo "  ${test_name%.zsh}"
    fi
  done
}

# Run single test file
run_test_file() {
  local test_file="$1"
  echo "${YELLOW}Running $(basename "$test_file")${NC}"
  
  # Change to test directory before running test
  local original_dir="$(pwd)"
  cd "$(dirname "$test_file")"
  
  if zsh -f "$(basename "$test_file")"; then
    cd "$original_dir"
    echo "${GREEN}✓ $(basename "$test_file") passed${NC}"
    return 0
  else
    cd "$original_dir"
    echo "${RED}✗ $(basename "$test_file") failed${NC}"
    return 1
  fi
}

# Main test runner
run_all_tests() {
  local failed_count=0
  local total_count=0
  
  echo "${YELLOW}=== zsh-ssh Plugin Test Suite ===${NC}"
  echo
  
  check_dependencies
  
  # Find and run all test files
  for test_file in "$TEST_DIR"/test_*.zsh; do
    if is_test_suite "$test_file"; then
      total_count=$((total_count + 1))
      
      if ! run_test_file "$test_file"; then
        failed_count=$((failed_count + 1))
      fi
      echo
    fi
  done
  
  # Summary
  echo "${YELLOW}=== Test Summary ===${NC}"
  echo "Total test files: $total_count"
  echo "${GREEN}Passed: $((total_count - failed_count))${NC}"
  
  if [[ $failed_count -gt 0 ]]; then
    echo "${RED}Failed: $failed_count${NC}"
    echo
    echo "${RED}Some tests failed. Check output above for details.${NC}"
    return 1
  else
    echo "${GREEN}All test suites passed!${NC}"
    return 0
  fi
}

# Run specific test if provided, otherwise run all
if [[ $# -gt 0 ]]; then
  test_file="$TEST_DIR/test_$1.zsh"
  if is_test_suite "$test_file"; then
    check_dependencies
    run_test_file "$test_file"
  else
    echo "${RED}Test file not found: $test_file${NC}" >&2
    echo "Available tests:"
    print_available_tests
    exit 1
  fi
else
  run_all_tests
fi
