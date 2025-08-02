-- nvim/lua/plugins/noice.lua
return {
  "folke/noice.nvim",
  opts = {
    routes = {
      {
        filter = {
          event = "msg_show",
          kind = "lua_error",
          find = "java.lang.IllegalArgumentException: URI path component is empty",
        },
        opts = { skip = true },
      },
      -- {
      --   filter = {
      --     event = "msg_show",
      --     kind = "emsg",
      --     find = "java.lang.IllegalArgumentException: URI path component is empty",
      --   },
      --   opts = { skip = true },
      -- }
    },
  },
}
