-- lua/plugins/which-key.lua
return {
  "folke/which-key.nvim",
  opts = {
    spec = {
      {
        "<leader>b",
        name = "buffer",
        expand = function()
          local items = {}

          local success, bufferline_state = pcall(require, "bufferline.state")
          if not success or not bufferline_state.components then
            return items
          end

          local components = bufferline_state.components
          for i = 1, 9 do
            local component = components[i]
            if component and component.id then
              local cmd = function()
                vim.cmd("buffer " .. component.id)
              end
              local desc = component.name
              local icon = { icon = component.icon, hl = component.icon_highlight }

              items[#items + 1] = { tostring(i), cmd, desc = desc, icon = icon }
            end
          end
          return items
        end,
      },
    },
  },
}
