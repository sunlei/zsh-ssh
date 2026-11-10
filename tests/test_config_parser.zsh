#!/usr/bin/env zsh

# Test configuration file parsing functionality
# 测试核心数据结构 - SSH 配置文件解析

source "$(dirname "$0")/test_framework.zsh"
setup_test_env

test_parse_basic_config() {
  local result=$(_parse_config_file "$(get_test_config_path)")
  
  assert_contains "Host alias-1" "$result" "Parse basic host entry"
  assert_contains "Hostname 127.0.0.1" "$result" "Parse hostname directive"  
  assert_contains "#_Desc multiple alias test" "$result" "Parse description comment"
}

test_parse_include_directive() {
  local result=$(_parse_config_file "$(get_test_config_path)")
  
  assert_contains "Host include-2" "$result" "Parse included host from include_2"
  assert_contains "Host include-1" "$result" "Parse included host from include_1"  
}

test_parse_wildcard_includes() {
  local result=$(_parse_config_file "$(get_test_config_path)")
  
  # Should include files from config.d/* wildcard - dev/dev contains include-dev
  assert_contains "Host include-dev" "$result" "Parse wildcard include files"
}

test_parse_relative_paths() {
  # 在无写权限环境下跳过此用例
  local tmpdir
  if ! tmpdir=$(mktemp -d 2>/dev/null); then
    echo "${YELLOW}SKIP${NC} test_parse_relative_paths (no writable temp dir)"
    return 0
  fi

  # Create temporary config with relative include
  local temp_config="$tmpdir/test_ssh_config"
  cat > "$temp_config" << 'EOF'
Host test-relative
    Hostname 1.2.3.4

Include config.d/include_1
EOF

  # Create relative include file
  mkdir -p "$tmpdir/config.d"
  cat > "$tmpdir/config.d/include_1" << 'EOF'
Host relative-include
    Hostname 5.6.7.8
EOF

  local result=$(_parse_config_file "$temp_config")

  assert_contains "Host test-relative" "$result" "Parse main config with relative include"
  assert_contains "Host relative-include" "$result" "Parse relative include file"

  # Cleanup
  rm -rf "$tmpdir"
}

test_parse_multiple_include_paths_on_one_line() {
  local tmpdir
  if ! tmpdir=$(mktemp -d 2>/dev/null); then
    echo "${YELLOW}SKIP${NC} test_parse_multiple_include_paths_on_one_line (no writable temp dir)"
    return 0
  fi

  local temp_config="$tmpdir/test_ssh_config"
  cat > "$tmpdir/include_a" << 'EOF'
Host multi-include-a
    Hostname 21.21.21.21
EOF

  cat > "$tmpdir/include_b" << 'EOF'
Host multi-include-b
    Hostname 22.22.22.22
EOF

  cat > "$temp_config" << EOF
Include $tmpdir/include_a $tmpdir/include_b
EOF

  local result=$(_parse_config_file "$temp_config")

  assert_contains "Host multi-include-a" "$result" "Parse first include path from one Include line"
  assert_contains "Host multi-include-b" "$result" "Parse second include path from one Include line"

  rm -rf "$tmpdir"
}

test_parse_environment_variables() {
  local result=$(_parse_config_file "$(get_test_config_path)")
  # $REPO_ROOT 展开后应能解析 Include 文件中的主机
  assert_contains "Host include-2" "$result" "Handle environment variable expansion in includes"
}

test_parse_nonexistent_file() {
  local result=$(_parse_config_file "/nonexistent/config" 2>/dev/null)
  
  # Should handle gracefully without crashing
  assert_equals "" "$result" "Handle nonexistent config file gracefully"
}

test_parse_tilde_include() {
  local tmpdir
  if ! tmpdir=$(mktemp -d 2>/dev/null); then
    echo "${YELLOW}SKIP${NC} test_parse_tilde_include (no writable temp dir)"
    return 0
  fi

  # 创建使用 ~ 路径的 Include 配置
  local temp_config="$tmpdir/test_ssh_config"
  mkdir -p "$tmpdir/config.d"
  cat > "$tmpdir/config.d/tilde_host" << 'EOF'
Host tilde-include-host
    Hostname 7.7.7.7
EOF

  # 使用 $HOME 模拟 ~ 展开（因为 ~ 在 eval 赋值上下文中会展开为 $HOME）
  cat > "$temp_config" << EOF
Include $HOME/.ssh/nonexistent_*

Host tilde-test
    Hostname 8.8.8.8

Include $tmpdir/config.d/*
EOF

  local result=$(_parse_config_file "$temp_config")

  assert_contains "Host tilde-test" "$result" "Parse config with tilde-style includes"
  assert_contains "Host tilde-include-host" "$result" "Parse included file from tilde path"

  rm -rf "$tmpdir"
}

test_parse_plain_include_without_bareglobqual() {
  setopt localoptions

  local tmpdir
  if ! tmpdir=$(mktemp -d 2>/dev/null); then
    echo "${YELLOW}SKIP${NC} test_parse_plain_include_without_bareglobqual (no writable temp dir)"
    return 0
  fi

  local temp_config="$tmpdir/test_ssh_config"
  cat > "$temp_config" << EOF
Include $tmpdir/plain_include
EOF

  cat > "$tmpdir/plain_include" << 'EOF'
Host plain-include-no-bareglobqual
    Hostname 11.11.11.11
EOF

  # Include expansion must not depend on the caller's bareglobqual option.
  unsetopt bareglobqual
  local result=$(_parse_config_file "$temp_config")

  assert_contains "Host plain-include-no-bareglobqual" "$result" "Parse plain include when bareglobqual is disabled"

  rm -rf "$tmpdir"
}

test_parse_wildcard_include_without_bareglobqual() {
  setopt localoptions

  local tmpdir
  if ! tmpdir=$(mktemp -d 2>/dev/null); then
    echo "${YELLOW}SKIP${NC} test_parse_wildcard_include_without_bareglobqual (no writable temp dir)"
    return 0
  fi

  mkdir -p "$tmpdir/config.d"
  local temp_config="$tmpdir/test_ssh_config"
  cat > "$temp_config" << EOF
Include $tmpdir/config.d/*.conf
EOF

  cat > "$tmpdir/config.d/wildcard.conf" << 'EOF'
Host wildcard-include-no-bareglobqual
    Hostname 12.12.12.12
EOF

  # The plugin uses the (N) glob qualifier internally, not as a caller prerequisite.
  unsetopt bareglobqual
  local result=$(_parse_config_file "$temp_config")

  assert_contains "Host wildcard-include-no-bareglobqual" "$result" "Parse wildcard include when bareglobqual is disabled"

  rm -rf "$tmpdir"
}

test_parse_missing_wildcard_include_with_nomatch_enabled() {
  setopt localoptions nomatch

  local tmpdir
  if ! tmpdir=$(mktemp -d 2>/dev/null); then
    echo "${YELLOW}SKIP${NC} test_parse_missing_wildcard_include_with_nomatch_enabled (no writable temp dir)"
    return 0
  fi

  local temp_config="$tmpdir/test_ssh_config"
  cat > "$temp_config" << EOF
Include $tmpdir/missing-*

Host missing-wildcard-main
    Hostname 23.23.23.23
EOF

  local result=$(_parse_config_file "$temp_config")
  local nomatch_state

  [[ -o nomatch ]] && nomatch_state="on" || nomatch_state="off"

  assert_contains "Host missing-wildcard-main" "$result" "Ignore missing wildcard include when nomatch is enabled"
  assert_equals "on" "$nomatch_state" "Restore caller nomatch option after parsing"

  rm -rf "$tmpdir"
}

test_parse_include_cycle_once() {
  local tmpdir
  if ! tmpdir=$(mktemp -d 2>/dev/null); then
    echo "${YELLOW}SKIP${NC} test_parse_include_cycle_once (no writable temp dir)"
    return 0
  fi

  local temp_config="$tmpdir/test_ssh_config"
  cat > "$temp_config" << EOF
Host cycle-main
    Hostname 24.24.24.24

Include $tmpdir/include_a
EOF

  cat > "$tmpdir/include_a" << EOF
Host cycle-a
    Hostname 25.25.25.25

Include $tmpdir/include_b
EOF

  cat > "$tmpdir/include_b" << EOF
Host cycle-b
    Hostname 26.26.26.26

Include $tmpdir/include_a
EOF

  local result=$(_parse_config_file "$temp_config")

  assert_contains "Host cycle-main" "$result" "Parse root config before include cycle"
  assert_contains_count "1" "Host cycle-a" "$result" "Parse cyclic include only once"
  assert_contains_count "1" "Host cycle-b" "$result" "Parse nested cyclic include only once"

  rm -rf "$tmpdir"
}

test_parse_symlinked_config_relative_include_from_link_dir() {
  local tmpdir
  if ! tmpdir=$(mktemp -d 2>/dev/null); then
    echo "${YELLOW}SKIP${NC} test_parse_symlinked_config_relative_include_from_link_dir (no writable temp dir)"
    return 0
  fi

  mkdir -p "$tmpdir/home/.ssh" "$tmpdir/dotfiles"

  cat > "$tmpdir/dotfiles/config" << 'EOF'
Include config.home

Host symlink-main
    Hostname 30.30.30.30
EOF

  cat > "$tmpdir/home/.ssh/config.home" << 'EOF'
Host symlink-home-include
    Hostname 31.31.31.31
EOF

  cat > "$tmpdir/dotfiles/config.home" << 'EOF'
Host symlink-target-include
    Hostname 32.32.32.32
EOF

  ln -s "$tmpdir/dotfiles/config" "$tmpdir/home/.ssh/config"

  local original_home="$HOME"
  HOME="$tmpdir/home"
  local result=$(_parse_config_file "$tmpdir/home/.ssh/config")
  HOME="$original_home"

  assert_contains "Host symlink-home-include" "$result" "Parse relative include from symlink config directory"
  assert_not_contains "Host symlink-target-include" "$result" "Do not resolve symlink config relative include from target directory"

  rm -rf "$tmpdir"
}

test_parse_state_cleanup_after_completion() {
  local result=$(_parse_config_file "$(get_test_config_path)")

  assert_not_empty "$result" "Parse fixture before checking parser state"
  assert_equals "0" "$_zsh_ssh_parse_depth" "Reset parse depth after top-level parse"
  assert_equals "0" "${#_zsh_ssh_seen_config_files}" "Clear seen include cache after top-level parse"
}

# Run tests
test_parse_basic_config
test_parse_include_directive
test_parse_wildcard_includes
test_parse_relative_paths
test_parse_multiple_include_paths_on_one_line
test_parse_environment_variables
test_parse_nonexistent_file
test_parse_tilde_include
test_parse_plain_include_without_bareglobqual
test_parse_wildcard_include_without_bareglobqual
test_parse_missing_wildcard_include_with_nomatch_enabled
test_parse_include_cycle_once
test_parse_symlinked_config_relative_include_from_link_dir
test_parse_state_cleanup_after_completion
finish_tests
