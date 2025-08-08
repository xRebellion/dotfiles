return {
  {
    "mfussenegger/nvim-jdtls",
    opts = {
      project_name = function(root_dir)
        if root_dir == nil then
          return vim.fn.getcwd()
        end
        return root_dir and vim.fs.basename(root_dir)
      end,
    },
  },
  {
    "folke/noice.nvim",
    opts_extend = { "routes" },
    opts = {
      routes = {
        {
          filter = {
            event = "lsp",
            kind = "progress",
            find = "Validate documents",
          },
          opts = {
            skip = true,
          },
        },
      },
    },
  },
}
