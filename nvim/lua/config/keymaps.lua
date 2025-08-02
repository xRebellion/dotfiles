-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
vim.keymap.set("n", "<F1>", ":", { desc = "Command" })
vim.keymap.set("n", "<C-\\>", "<ESC>", { desc = "Big Finger Escape" })
vim.keymap.set("n", "<leader>cP", 'gg"0dGpkJ', { desc = "Clear Buffer and Paste Content" })
vim.keymap.set("i", "<C-\\>", "<ESC>", { desc = "Big Finger Escape" })
vim.keymap.set("i", "jk", "<ESC>", { desc = "jk in insert mode to escape" })
vim.keymap.set("n", "<F5>", "<cmd>DapNew<cr>", { desc = "Debug Spring Application" })
vim.keymap.set("n", "<C-F5>", function()
  Snacks.terminal.open("mvn spring-boot:run", { win = { style = "split" } })
end, { desc = "Run Spring Application" })
