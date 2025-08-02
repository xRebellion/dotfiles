return {
  "folke/flash.nvim",
  opts = {
    -- incremental = true,

    highlight = {
      groups = {
        label = "Substitute",
        backdrop = "",
        match = "Search",
      },
      backdrop = false,
    },
    modes = {
      char = {
        multi_line = true,
        -- keys = { ";", "," },
      },
      highlight = {
        backdrop = false,
      },
    },
  },
}
