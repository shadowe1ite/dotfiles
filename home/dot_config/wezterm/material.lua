return {
  foreground = "#d5c4a1",
  background = "#0f1512",

  cursor_bg = "#88d6bb",
  cursor_fg = "#136b55",

  selection_bg = "#dee4df",
  selection_fg = "#2c322f",

  ansi = {
    "#3c3836", -- black
    "#fb4934", -- red
    "#b8bb26", -- green
    "#fabd2f", -- yellow
    "#83a598", -- blue
    "#d3869b", -- magenta
    "#8ec07c", -- cyan
    "#d5c4a1", -- white
  },

  brights = {
    "#484442", -- bright black
    "#fb4934", -- bright red
    "#b8bb26", -- bright green
    "#fabd2f", -- bright yellow
    "#83a598", -- bright blue
    "#d3869b", -- bright magenta
    "#8ec07c", -- bright cyan
    "#fbf1c7", -- bright white
  },

  -- FIX: Using explicit { Color = ... } wrapper to solve the error
  copy_mode_active_highlight_bg = { Color = "#a3f2d7" },
  copy_mode_active_highlight_fg = { Color = "#136b55" },
  copy_mode_inactive_highlight_bg = { Color = "#00513f" },
  copy_mode_inactive_highlight_fg = { Color = "#a3f2d7" },
}
