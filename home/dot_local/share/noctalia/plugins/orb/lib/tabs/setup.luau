--!nonstrict
-- The card while Hermes has no API key (or rejected it): one screen, no tabs. The service
-- looks in the keyring every few seconds while it shows, so storing the key unlocks it.
--
--   render(m) with m = { linkDetail }

local common = require("./common.luau")

local M = {}

function M.render(m)
  local rejected = m.linkDetail ~= nil and m.linkDetail ~= "no-key"
  return common.panel("setup", {
    common.state("setup-state", "key", common.tr(if rejected then "hermes.setup.rejected" else "hermes.setup.title")),
  })
end

return M
