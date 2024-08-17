# nvim-plugins

Some reasoning behind my current plugin list.

## Rules

1. I want my plugin list as minimal as possible (not more than 35 plugins?). I don't want the burden of maintainability of having too much plugins
2. Also, I prefer not choosing plugins that extremely "reinvent" what nvim already has (there are some exceptions to this though).
3. I don't like plugins that forces you to install tons of other plugins just to being able to work (examples below)
4. Even if I have to do some extra work, I will prefer plugins with really go extensibility (heirline.nvim). Maybe because it gives me more control over my setup

## Current plugin list and motives

| Plugin                      | Comments                                                                                                                                                                         |
| --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| aerial.nvim                 | Navigating through LSP symbols in a floating window and seeing them also in the winbar is extremely helpful                                                                      |
| Colorizer                   | Useful to format some ascii terminal chars making them readable (on dap-repl for example)                                                                                        |
| fzf                         | Dependency of nvim.bqf                                                                                                                                                           |
| fzf-lua                     | Navigation between files. Extremely good plugin. Author is really nice.                                                                                                          |
| gitsigns.nvim               | Doesn't needs justification                                                                                                                                                      |
| heirline                    | Flexible and configurable statusline                                                                                                                                             |
| lazy.nvim                   | Plugin manager                                                                                                                                                                   |
| nvim-bqf                    | Very good and useful enhacements on default quickfix window                                                                                                                      |
| ALE                         | I'm really satisfied with this linter plugin                                                                                                                                     |
| nvim-lspconfig              | I don't want to do all this configuration manually                                                                                                                               |
| nvim-treesitter             | Need no explanation I think. I use `kevinhwang91/nvim-treesitter` fork because is more minimal. See: https://github.com/kevinhwang91/nvim-bqf/issues/110#issuecomment-1509896444 |
| nvim-treesitter-textobjects | I got really used to some of these movements (like `vif` to select the body of a function)                                                                                       |
| nvim-ufo                    | More performant than native folds (due to lsp). This is the exception to my second rule                                                                                          |
| nvim-web-devicons           | No need to explain                                                                                                                                                               |
| oil.nvim                    | Not going to use :Explorer                                                                                                                                                       |
| overseer.nvim               | Another exception to my second rule. Is just the most beatiful plugin and lua code I've ever seen, I use it to do almost all my interactions with the terminal                   |
| persistence.nvim            | Minimal and invaluable                                                                                                                                                           |
| plenary.nvim                | Dependency for other plugins (like nvim-lspconfig) but also for some of my own code                                                                                              |
| promise-async               | Dependency for other plugins                                                                                                                                                     |
| smartyank.nvim              | Invaluable for my ssh remote ipad setup                                                                                                                                          |
| grapple.nvim                | trailblazer.nvim was giving me issues with saved session. I don't remember                                                                                                       |
| vim-sleuth                  | Invaluable                                                                                                                                                                       |
| blame.nvim                  | Necesary, neither diffview.nvim, nor gitsigns.nvim provide this                                                                                                                  |
| clangd_extensions.nvim      | --                                                                                                                                                                               |
| conform.nvim                | --                                                                                                                                                                               |
| diffview.nvim               | Very complete plugin, improved my git workflow by a lot                                                                                                                          |
| gp.nvim                     | The only AI plugin that I use, simple and powerful                                                                                                                               |
| nvim-dap                    | Best of the best                                                                                                                                                                 |
| nvim-dap-python             | A little treat that I don't use too much, might delete                                                                                                                           |
| one-small-step-for-vimking  | Really good for debugging your nvim setup and plugins                                                                                                                            |
| SchemaStore.nvim            | Useful for config files like lazygit/config.yml or tsconfig.json                                                                                                                 |
| undotree                    | Might delete, I don't use it too much, maybe git is enough                                                                                                                       |

## What I used to have

| Plugin                | Comments                                                                                                                                                                                     |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| neotest               | I don't like having to clutter my setup with extra sources just to make this work                                                                                                            |
| cmp                   | Reinvention of native completion. Same as neotest, I don't like having to clutter my setup with extra plugins (sources). I also don't mind pressing `C-x C-o` whenever I **need** completion |
| nvim-dap-ui           | Not that necessary, nvim-dap has everything for my use case                                                                                                                                  |
| typescript-tools.nvim | Not the best approach for solving the "tsserver" problem I believe.                                                                                                                          |
| telescope.nvim        | I prefer to be closer to the shell (what fzf-lua does)                                                                                                                                       |
| lualine               | too specific and cumbersome                                                                                                                                                                  |
| bufferline.nvim       | I don't like buffers as tabs. Embrace the vim way.                                                                                                                                           |
| neotree               | The tree used to jump a lot. Also, I never felt that the "always opened tree" approach is well suited for vim                                                                                |
| colorscheme plugins   | New neovim default colorscheme is all I need. Now seeing all that color from colorscheme plugins feels overwhelming                                                                          |
| fidget,notify.nvim    | I don't mind not having fancy notifications. I print the LspProgress on a custom autocmd                                                                                                     |
