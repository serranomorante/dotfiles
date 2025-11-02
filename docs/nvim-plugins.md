# nvim-plugins

Some reasoning behind my current plugin list.

## Rules

1. I want my plugin list as minimal as possible (not more than 35 plugins?). I don't want the burden of maintainability of having too much plugins
1. Also, I prefer not choosing plugins that extremely "reinvent" what nvim already has (there are some exceptions to this though).
1. I don't like plugins that forces you to install tons of other plugins just to being able to work (examples below)
1. Even if I have to do some extra work, I will prefer plugins with really go extensibility (heirline.nvim). Maybe because it gives me more control over my setup

## Current plugin list and motives

| Plugin                      | Comments                                                                                                                                                                         |
| --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| aerial.nvim                 | Navigating through LSP symbols in a floating window and seeing them also in the winbar is extremely helpful                                                                      |
| gitsigns.nvim               | Doesn't needs justification                                                                                                                                                      |
| ALE                         | I'm really satisfied with this linter plugin                                                                                                                                     |
| nvim-treesitter             | Need no explanation I think. I use `kevinhwang91/nvim-treesitter` fork because is more minimal. See: https://github.com/kevinhwang91/nvim-bqf/issues/110#issuecomment-1509896444 |
| nvim-treesitter-textobjects | I got really used to some of these movements (like `vif` to select the body of a function)                                                                                       |
| nvim-ufo                    | More performant than native folds (due to lsp). This is the exception to my second rule                                                                                          |
| overseer.nvim               | Another exception to my second rule. Is just the most beatiful plugin and lua code I've ever seen, I use it to do almost all my interactions with the terminal                   |
| plenary.nvim                | Dependency for other plugins (like nvim-lspconfig) but also for some of my own code                                                                                              |
| promise-async               | Dependency for other plugins                                                                                                                                                     |
| blame.nvim                  | Necesary, neither diffview.nvim, nor gitsigns.nvim provide this                                                                                                                  |
| conform.nvim                | --                                                                                                                                                                               |
| diffview.nvim               | Very complete plugin, improved my git workflow by a lot                                                                                                                          |
| nvim-dap                    | Best of the best                                                                                                                                                                 |
| one-small-step-for-vimking  | Really good for debugging your nvim setup and plugins                                                                                                                            |
| coc.nvim                    | -                                                                                                                                                                                |
| nvim-fundo                  | --                                                                                                                                                                               |
| vim-rsi                     | --                                                                                                                                                                               |
| guess-indent                | --                                                                                                                                                                               |
| codecompanion.nvim          | --                                                                                                                                                                               |
| codecompanion-history.nvim  | --                                                                                                                                                                               |
| mcphub.nvim                 | --                                                                                                                                                                               |
| VectorCode                  | --                                                                                                                                                                               |
| img-clip.nvim               | --                                                                                                                                                                               |
