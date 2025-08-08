-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
LazyVim.terminal.setup("pwsh")
vim.o.expandtab = true -- Converts tabs to spaces when inserting
vim.o.swapfile = false
vim.o.autoread = true
vim.o.title = true
vim.o.titlestring = "nvim - %t"
-- Determine OS
if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
  vim.opt.shellslash = false -- Enable shellslash for Windows compatibility
  vim.defer_fn(function()
    vim.opt.shellslash = false
  end, 5000)
else
  print("OS not found, defaulting to 'linux'")
end
