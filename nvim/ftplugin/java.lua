-- local config = {
--   cmd = { os.getenv("LOCALAPPDATA") .. "/nvim-data/mason/packages/jdtls/bin/jdtls" },
--   root_dir = vim.fs.dirname(vim.fs.find({ "gradlew", ".git", "mvnw" }, { upward = true })[1]),
-- }
-- if LazyVim.has("mason.nvim") then
--   local mason_registry = require("mason-registry")
--   config.cmd = mason_registry.get_package("jdtls"):get_install_path() .. "/bin/jdtls"
-- end
-- require("jdtls").start_or_attach(config)
vim.opt_local.tabstop = 4
vim.opt_local.shiftwidth = 4
vim.opt_local.expandtab = true
