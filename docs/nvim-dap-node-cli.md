# Setup nvim-dap for typescript node cli app

Just some notes for my self about making nvim-dap and vscode-js-debug work with node cli app written in typescript without using ts-node.

I believe the most important part of this guide is the section in which I show you how to debug all this mess by yourself

## What about [nvim-dap-vscode-js](https://github.com/mxsdev/nvim-dap-vscode-js)

Just use the dap debug server directly without this plugin.

[example from my dotfiles](https://github.com/serranomorante/.dotfiles/blob/main/.config%2Fnvim%2Flua%2Fserranomorante%2Fplugins%2Fdap%2Fnvim-dap.lua#L94-L119)

More context:

vscode-js-debug is a package that provides 2 debug servers: vsDebugServer and dapDebugServer. If you go with vsDebugServer, then you need to use this plugin. If you go with dapDebugServer then you can use it directly without this plugin as showed in my config. I prefer the latter.

Make sure to always install latest version of vscode-js-debug. Right now that is 1.86.1 and that version is working fine for me even on Nextjs14 (server side and client side) projects with typescript and app router.

Don't use oudated guides. vscode-js-debug changes a lot. Don't put configurations like "resolveSourceMapLocations" if you dont understand them. Also vscode-js-debug already provides good defaults.

This stuff is hard, sadly.

## Terminology

- dap client: nvim-dap
- debugger: the [vscode-js-debug](https://github.com/microsoft/vscode-js-debug) debugger
- editor: neovim

This launch.json works:

```javascript
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Launch node cli app",
      "type": "pwa-node",
      "request": "launch",
      "preLaunchTask": "tsc: build - tsconfig.json",
      "cwd": "${workspaceFolder}",
      "args": ["${workspaceFolder}/dist/index.js"],
      "stopOnEntry": true
    }
  ]
}
```

Lets explain each of this options:

- **name**: This can be any string, it doesn't matter.
- **type**: Use `pwa-node` as much as you can (when debugging node). Don't worry too much about this naming.
- **request**: There are only 2 possible requests: "attach" or "launch". Just those and no more. `launch` means that nvim-dap is going to start your app. This means that you don't have to worry about connecting the debugger to your running app process port, it happens automatically for you. `attach` means that you will handle starting your app in debug mode (usually with node --inspect option) and also picking the right process of your running app. I prefer the first option. [More on that](https://code.visualstudio.com/docs/editor/debugging#_launch-versus-attach-configurations)
- **preLaunchTask**: (only works in vscode, if you're not using vscode or you're not using [overseer.nvim](https://github.com/stevearc/overseer.nvim) on neovim, just compile your app manually, I'm using this to avoid doing that) as we are using typescript, we need to compile the source code into javascript files. Why? because neither node nor your browser understand typescript, those execution environments only understand javascript. Typescript is for your editor only. Javascript is for the runtime execution of your code. [Here's an example of my preLaunchTask](https://github.com/serranomorante/.dotfiles/blob/a66128533113263dc6569471eeb1d4172dbe83c6/.config/nvim/lua/overseer/template/vscode/tsc_build.lua)
- **cwd**: I hate that [this option](https://github.com/microsoft/vscode-js-debug/blob/main/OPTIONS.md#cwd-1) is supposed to come as default but you still have to set it manually!! otherwise it will not work. I understand this can give you less confidence on the other defaults that `vscode-js-debug` provides, but I still recommend you not to override any options that already have a good default.
- **args**: the javascript entry point of your cli app. Don't try to put a typescript file here.
- **stopOnEntry**: very important option, otherwise your app might finish running without stopping at any of your breakpoints, I believe that is because `vscode-js-debug` breakpoints are set asynchronously and somehow you need to force your app to stop at the entry.

## How to better debug?

`nvim-dap` and `vscode-js-debug` logs are your friend. Doesn't `nvim-dap` show the `vscode-js-debug` logs already? not really, `vscode-js-debug` generates more verbose logging compressed files that are very very useful for understanding what is going wrong with your config.

How to enable `nvim-dap` logging? read the docs.

How to enable `vscode-js-debug`, add the `trace: true` option to the previous config file:

```javascript
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Launch node cli app",
      "type": "pwa-node",
      "request": "launch",
      "preLaunchTask": "tsc: build - tsconfig.json",
      "cwd": "${workspaceFolder}",
      "args": ["${workspaceFolder}/dist/index.js"],
      "trace": true,
      "stopOnEntry": true
    }
  ]
}
```

Where is this `vscode-js-debug` verbose file? First enter the `nvim-dap` log file and search for the `Verbose` word (sensitive case). You will then find the path to the verbose logs, something similar to this: `/tmp/vscode-debugadapter-cbafe612.json.gz`

How to uncompress that? Use this to avoid any [silly mistakes](https://github.com/microsoft/vscode/issues/150047):

`cat /tmp/vscode-debugadapter-cbafe612.json.gz | gunzip`

### Tips for debugging

On this verbose logging file, search for any of your typescript files to make sure they are correctly mapped. For example, I searched `PostmanAPIService.ts` and realized that the full path that `vscode-js-debug` was resolving was wrong. Search specific typescript files not those generic ones like `index.ts`.

### How sourcemaps work?

It might seem intuitive to think that source maps work by mapping your typescript files (where you set your breakpoints) to your javascript files but is actually the otherway around. Your javascript files (`index.js`) will contain a link (in a comment) to your source map files (`index.js.map`) which in consequence will contain a link to your typescript file (`index.ts`). Your debugger uses this information to stop on the breakpoint you set on the typescript file in your source code.

### What can go wrong?

- If you're new to nvim-dap, first try to make it work with minimal projects (like those from framework examples like: vite, parcel, nextjs, etc). Don't use projects that are bloated with dependencies that can mess things up.
- `vscode-js-debug` not resolving your paths correctly are one of the most common problems. Use the techniques presented above to make sure your paths are correct.
- [next-translate](https://github.com/aralroca/next-translate?tab=readme-ov-file#3-configuration) uses a custom webpack loader that mess up with the source map locations of your next.js project. Use `loader: false` on next-translate to fix this.
