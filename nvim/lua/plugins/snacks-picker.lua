return {
  "folke/snacks.nvim",
  opts = {
    picker = {
      hidden = true,
      sources = {
        explorer = {
          layout = {
            auto_hide = { "input" },
          },
        },
        files = {
          hidden = true,
          exclude = {
            "**/.git/*",
          },
        },
      },
      matcher = {
        frecency = true,
      },
    },
  },
}
