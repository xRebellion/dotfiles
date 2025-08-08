-- Pull in the wezterm API
local wezterm = require("wezterm")

-- This will hold the configuration.
local config = wezterm.config_builder()

-- This is where you actually apply your config choices.

-- For example, changing the initial geometry for new windows:
config.initial_cols = 120
config.initial_rows = 28

-- or, changing the font size and color scheme.
config.font = wezterm.font_with_fallback({ "MesloLGL Nerd Font" })
config.font_size = 10
config.color_scheme = "catppuccin-mocha"
config.default_prog = { "pwsh" }
config.use_fancy_tab_bar = true
config.window_frame = {
	font = wezterm.font({ family = "Cascadia Mono", weight = "Regular" }),
	active_titlebar_bg = "#11111b",
}
config.colors = {
	background = "#181825",
	-- cursor_bg = "#94e2d5",
	cursor_fg = "#11111b",
	tab_bar = {
		background = "#11111b",
		inactive_tab_edge = "#181825",
		active_tab = {
			bg_color = "#1e1e2e",
			fg_color = "#cdd6f4",
		},
		inactive_tab = {
			bg_color = "#181825",
			fg_color = "#585b70",
			intensity = "Half",
		},
		inactive_tab_hover = {
			bg_color = "#1e1e2e",
			fg_color = "#cdd6f4",
		},
		new_tab = {
			bg_color = "#11111b",
			fg_color = "#585b70",
		},
	},
}
config.window_background_opacity = 1.0
config.window_padding = {
	left = 0,
	right = 0,
	top = 0,
	bottom = 0,
}
local padding = {
	left = 0,
	right = 0,
	top = 0,
	bottom = 0,
}
config.keys = {
	{
		key = " ",
		mods = "CTRL",
		action = wezterm.action.SendKey({
			key = " ",
			mods = "CTRL",
		}),
	},
}
wezterm.on("user-var-changed", function(window, pane, name, value)
	if name == "NVIM_ENTER" then
		local overrides = window:get_config_overrides() or {}
		if value == "1" then
			overrides.window_padding = {
				left = 0,
				right = 0,
				top = 0,
				bottom = 0,
			}
		else
			overrides.window_padding = padding
		end
		window:set_config_overrides(overrides)
	end
end)
-- Finally, return the configuration to wezterm:
return config
