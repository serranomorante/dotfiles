# Python development setup with Neovim

> Important distinction: I'm installing my python tools (`ruff-lsp`, `pyright`, `black`, `pylint`, etc.) globally with [mason](https://github.com/williamboman/mason.nvim) and [mason-null-ls](https://github.com/jay-babu/mason-null-ls.nvim). This is the part that causes most of the problems. It would be "easier" to just install these tools as dependencies of my python project but I'm stubborn.

Ok, moving on...

Tools like `ruff-lsp`, `pyright`, etc., seems to work just fine with poetry virtual environments (at least if you have [`in-project`](https://python-poetry.org/docs/configuration/#virtualenvsin-project) poetry config set to `true`). But `pylint` was a nightmare. It seems to be the case that pylint is uncapable to handle virtual environments without me having to hack my way out and force it to do it.

## Dependencies

For my workflow to actually work, I had no choice but install this dependency:

- [pylint-venv](https://github.com/jgosmann/pylint-venv). That's right, there's a dedicated tool to help you solving the problem of pylint and virtual environments.

> I installed it with `sudo pacman -S python-pylint-venv`

## Few notes about the implementation

This document does not intent to be a general guide that works for everyone, this document is just for me to remind me how I did things and what I did it. I hope it can be remotely useful for you, but most probably it won't.

### Setting up lsp-zero

Yes, I use [lsp-zero](https://github.com/VonHeikemen/lsp-zero.nvim/tree/dev-v3) for my whole lsp and null-ls setup.

Here is a step by step of what I changed in the lsp configs to make pylint work:


```lua
require("mason-null-ls").setup({
	ensure_installed = {
		-- python
		"mypy",
		"isort",
		"black",
		"pylint",
		-- ... more
	},
	-- ... more
	handlers = {
		-- Prevent the automatic setup of mason-null-ls and do
		-- the setup manually in the null-ls block below.
		pylint = function() end,
	},
})
```

Prevent the automatic setup of mason-null-ls and do the setup manually in the null-ls block below.

```lua
local venv_path =
	'import sys; sys.path.append("/usr/lib/python3.11/site-packages"); import pylint_venv; pylint_venv.inithook(force_venv_activation=True, quiet=True)'

local null_ls = require("null-ls")
null_ls.setup({
	sources = {
	    -- ... more
		null_ls.builtins.diagnostics.pylint.with({
			extra_args = { "--init-hook", venv_path },
		}),
		-- ... more
	},
})

```

This line `'import sys; sys.path.append("/usr/lib/python3.11/site-packages"); import pylint_venv; pylint_venv.inithook(force_venv_activation=True, quiet=True)'` is for `pylint_venv` to force `pylint` to use the virtualenv in which I opened nvim.

I will explained a little bit:

1. `import sys; sys.path.append("/usr/lib/python3.11/site-packages");`

For some reason, `pylint_venv` gets installed in `/usr/lib/python...` instead of `/usr/bin/python...` so I was experiencing import error when trying to call `import pylint_venv`. Thats why I needed to include the python executable to the path.

2. `import pylint_venv; pylint_venv.inithook(force_venv_activation=True, quiet=True)'`

The important thing here is to pass those 2 params: `...(force_venv_activation=True, quiet=True)` otherwise it won't work.

`force_venv_activation` will force the virtual environment activation when `pylint` is installed itself in a different environment.

`quiet` is just to hide an annoying warning.

## Workflow

With all these in place, I still cannot simply enter into my project with `vim .` but I still have to first activate the virtual environment with `poetry shell` and then and only then I can open my text editor with `vim .`.
