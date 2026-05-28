.PHONY: test test-nvim test-shell test-systemd test-scripts test-file test-name test-list

test:
	@tests/run $(if $(UNIT),--unit $(UNIT),) $(if $(FILE),--file $(FILE),) $(if $(NAME),--name $(NAME),) $(if $(TAGS),--tags $(TAGS),)

test-nvim:
	@tests/run --unit nvim $(if $(NAME),--name $(NAME),) $(if $(TAGS),--tags $(TAGS),)

test-shell:
	@tests/run --unit shell $(if $(NAME),--name $(NAME),) $(if $(TAGS),--tags $(TAGS),)

test-systemd:
	@tests/run --unit systemd $(if $(NAME),--name $(NAME),) $(if $(TAGS),--tags $(TAGS),)

test-scripts:
	@tests/run --unit scripts $(if $(NAME),--name $(NAME),) $(if $(TAGS),--tags $(TAGS),)

test-file:
	@test -n "$(FILE)" || { printf 'FILE is required\n' >&2; exit 2; }
	@tests/run --file "$(FILE)" $(if $(NAME),--name $(NAME),) $(if $(TAGS),--tags $(TAGS),)

test-name:
	@test -n "$(NAME)" || { printf 'NAME is required\n' >&2; exit 2; }
	@tests/run --name "$(NAME)" $(if $(UNIT),--unit $(UNIT),) $(if $(TAGS),--tags $(TAGS),)

test-list:
	@tests/run --list $(if $(UNIT),--unit $(UNIT),) $(if $(FILE),--file $(FILE),) $(if $(NAME),--name $(NAME),) $(if $(TAGS),--tags $(TAGS),)
