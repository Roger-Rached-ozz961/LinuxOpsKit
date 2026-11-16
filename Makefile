SHELL := /usr/bin/env bash
.PHONY: help syntax test check
help:
	@printf '%s\n' 'make syntax  - validate Bash syntax' 'make test    - run local integration tests' 'make check   - run syntax and tests'
syntax:
	@find bin lib plugins tests -type f \( -name '*.sh' -o -name 'linuxopskit' \) -print0 | xargs -0 -r -n1 bash -n
	@bash -n install.sh

test: syntax
	@bash tests/run.sh

check: syntax test
