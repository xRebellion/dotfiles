-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
vim.keymap.set("n", "<leader>cP", 'gg"_dGP', { desc = "Clear Buffer and Paste Content" })
vim.keymap.set("n", "<F5>", "<cmd>DapNew<cr>", { desc = "Debug Spring Application" })
vim.keymap.set("n", "<leader>fy", function()
  local path = vim.fn.expand("%:.")
  vim.fn.setreg("+", "/add " .. path:gsub("\\", "/"))
  vim.notify("Copied aider add command (linux path)", vim.log.levels.INFO)
end, { desc = "Copy aider add command (linux path)" })

vim.keymap.set("n", "<leader>fY", function()
  local path = vim.fn.expand("%:p")
  vim.fn.setreg("+", "/add " .. path)
  vim.notify("Copied aider add command (windows path)", vim.log.levels.INFO)
end, { desc = "Copy aider add command (windows path)" })
