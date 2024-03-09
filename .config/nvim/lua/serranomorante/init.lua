---Global settings
require("serranomorante.set")

---Colorscheme
require("serranomorante.colorscheme")

---Plugin manager
---Depends on configurations from `set.lua` file
require("serranomorante.lazy")

---Global variables
require("serranomorante.globals")

---Global keymaps
---Depends on lazy for the `is_available` util
require("serranomorante.remap")

---Global autocommands
require("serranomorante.autocmds")
