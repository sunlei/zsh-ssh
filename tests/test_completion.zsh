#!/usr/bin/env zsh

source "${0:A:h}/test_framework.zsh"
zsh -f "${0:A:h}/completion.zsh"
assert_equals 0 "$?" 'Run the command-preservation regression checks'
finish_tests
