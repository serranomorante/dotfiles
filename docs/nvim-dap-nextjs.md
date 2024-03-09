# Next.js with nvim-dap

I use this on a Next.js 14 typescript project with App Router. My project is a monorepo.

> Tip: if you're new to nvim-dap is better to start with a simple project rather than trying to make debugging work

Don't use `next-translate`, use `next-intl`.

```javascript
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Next.js: debug client-side",
      "type": "pwa-chrome",
      "request": "launch",
      "url": "http://localhost:3000",
      "webRoot": "${workspaceFolder}/apps/commerce",
      "userDataDir": true
    },
    {
      "name": "Next.js: debug server-side",
      "type": "pwa-node",
      "request": "launch",
      "cwd": "${workspaceFolder}/apps/commerce",
      "runtimeExecutable": "turbo",
      "runtimeArgs": ["dev", "--filter", "commerce"]
    }
  ]
}
```
