-- This file needs to have same structure as nvconfig.lua 
-- https://github.com/NvChad/ui/blob/v3.0/lua/nvconfig.lua
-- Please read that file to know all available options :( 

---@type ChadrcConfig
local M = {}

M.base46 = {
  theme = "horizon",
  transparency = false,
  hl_override = {
    Normal               = { bg = "NONE" },
    NormalNC             = { bg = "NONE" },
    NormalFloat          = { bg = "NONE" },
    FloatBorder          = { bg = "NONE" },
    SignColumn           = { bg = "NONE" },
    StatusLine           = { bg = "NONE" },
    NvimTreeNormal       = { bg = "NONE" },
    NvimTreeNormalNC     = { bg = "NONE" },
    NvimTreeWinSeparator = { bg = "NONE" },
    CmpPmenu             = { bg = "NONE" },
    CmpPmenuSel          = { bg = "NONE" },
    CmpItemMenu          = { bg = "NONE" },
    CmpItemAbbr          = { bg = "NONE" },
    CmpItemAbbrMatch     = { bg = "NONE" }, 
    TbFill               = { bg = "NONE" },
    Tabline              = { bg = "NONE" },
    TbBufOn              = { bg = "NONE" },
  },
}

-- M.nvdash = { load_on_startup = true }
-- M.ui = {
--       tabufline = {
--          lazyload = false
--      }
-- }

return M
