.PHONY: test lint format check

NVIM ?= nvim

# Run tests via mini.test
test:
	$(NVIM) --headless -u tests/minimal_init.lua -c "lua require('mini.test').setup(); MiniTest.run()" +q

# Lint with luacheck (if installed)
lint:
	luacheck lua/ tests/ --globals vim describe it assert before_each after_each

# Format with StyLua
format:
	stylua lua/ tests/ plugin/

# Check formatting without modifying
check:
	stylua --check lua/ tests/ plugin/

# Run all checks (CI)
ci: check lint test
