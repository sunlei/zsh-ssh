#!/usr/bin/env zsh

# Simple test framework for zsh-ssh plugin
# 遵循 Linus 哲学：简洁、实用、零废话

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# ANSI colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test result tracking
FAILED_TESTS=()

# Assert functions
assert_equals() {
  local expected="$1"
  local actual="$2"
  local test_name="$3"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if [[ "$expected" == "$actual" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "${GREEN}✓${NC} $test_name"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$test_name")
    echo "${RED}✗${NC} $test_name"
    echo "  Expected: $expected"
    echo "  Actual:   $actual"
  fi
}

assert_contains() {
  local expected="$1"
  local actual="$2" 
  local test_name="$3"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if [[ "$actual" == *"$expected"* ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "${GREEN}✓${NC} $test_name"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$test_name")
    echo "${RED}✗${NC} $test_name"
    echo "  Expected to contain: $expected"
    echo "  Actual: $actual"
  fi
}

# 精确匹配完整行，适合验证结构化输出，避免子串误命中。
assert_line_present() {
  local expected_line="$1"
  local actual="$2"
  local test_name="$3"

  TESTS_RUN=$((TESTS_RUN + 1))

  if printf "%s\n" "$actual" | command grep -F -x -- "$expected_line" >/dev/null 2>&1; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "${GREEN}✓${NC} $test_name"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$test_name")
    echo "${RED}✗${NC} $test_name"
    echo "  Expected line: $expected_line"
    echo "  Actual: $actual"
  fi
}

# 精确确认某一完整行不存在，适合验证过滤逻辑。
assert_line_absent() {
  local unexpected_line="$1"
  local actual="$2"
  local test_name="$3"

  TESTS_RUN=$((TESTS_RUN + 1))

  if ! printf "%s\n" "$actual" | command grep -F -x -- "$unexpected_line" >/dev/null 2>&1; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "${GREEN}✓${NC} $test_name"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$test_name")
    echo "${RED}✗${NC} $test_name"
    echo "  Unexpected line: $unexpected_line"
    echo "  Actual: $actual"
  fi
}

# 统计固定子串出现的行数，用于验证去重和递归 Include 保护。
assert_contains_count() {
  local expected_count="$1"
  local needle="$2"
  local actual="$3"
  local test_name="$4"
  local count

  TESTS_RUN=$((TESTS_RUN + 1))
  count=$(printf "%s\n" "$actual" | command grep -F -c -- "$needle" 2>/dev/null || true)

  if [[ "$expected_count" == "$count" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "${GREEN}✓${NC} $test_name"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$test_name")
    echo "${RED}✗${NC} $test_name"
    echo "  Expected count: $expected_count"
    echo "  Actual count:   $count"
    echo "  Needle: $needle"
    echo "  Actual: $actual"
  fi
}

assert_not_empty() {
  local actual="$1"
  local test_name="$2"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if [[ -n "$actual" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "${GREEN}✓${NC} $test_name"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$test_name")
    echo "${RED}✗${NC} $test_name"
    echo "  Expected non-empty result"
  fi
}

# Negative contains assertion (shared)
assert_not_contains() {
  local not_expected="$1"
  local actual="$2"
  local test_name="$3"

  TESTS_RUN=$((TESTS_RUN + 1))

  if [[ "$actual" != *"$not_expected"* ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "${GREEN}✓${NC} $test_name"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$test_name")
    echo "${RED}✗${NC} $test_name"
    echo "  Should not contain: $not_expected"
    echo "  Actual: $actual"
  fi
}

# Setup function for tests
setup_test_env() {
  # Source the main plugin file first
  local script_dir="$(cd "$(dirname "$0")" && pwd)"
  source "$script_dir/../zsh-ssh.zsh"
  
  # Set test SSH config file
  export SSH_CONFIG_FILE="$script_dir/ssh_config"
  # Provide a stable repo root for includes inside fixtures
  export REPO_ROOT="$(cd "$script_dir/.." && pwd)"
}

# Test data helpers
get_test_config_path() {
  local script_dir="$(cd "$(dirname "$0")" && pwd)"
  echo "$script_dir/ssh_config"
}

# Finish and exit with proper status so test.sh can detect failures
finish_tests() {
  if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
  else
    exit 0
  fi
}
