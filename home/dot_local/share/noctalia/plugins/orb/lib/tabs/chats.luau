--!nonstrict
-- Chats tab: the orb's past chats with Hermes. Tap one to carry it on in the Chat tab.
--
--   render(m) with m = { chat, lists, width, confirmDelete,
--                        cb = { cmd, askDelete, cancelDelete, deleteChat } }
--
-- Each chat has a trash button; it asks first (Delete / ×), since Hermes deletes the chat
-- and its transcript for good.

local common = require("./common.luau")

local M = {}
local C = common.COLORS
local tr = common.tr

local function trailing(m, row, current)
  local key = "chat-" .. row.id
  local lists = m.lists or {}
  if lists.deleting == row.id then
    return { common.muted(key .. "-deleting", tr("hermes.chats.deleting")) }
  end
  if m.confirmDelete == row.id then
    return {
      common.pill(key .. "-delete", "trash", tr("hermes.chats.delete"), function()
        m.cb.deleteChat(row.id)
      end, { fill = C.bad, color = C.onBad }),
      common.icon(key .. "-keep", "x", m.cb.cancelDelete, { size = 28, fill = C.clear, color = C.muted }),
    }
  end
  local nodes = {}
  if row.id == current then
    table.insert(nodes, common.pill(key .. "-now", nil, tr("hermes.chats.current"), nil, { fill = C.accentSoft, color = C.accent }))
  end
  table.insert(nodes, common.icon(key .. "-trash", "trash", function()
    m.cb.askDelete(row.id)
  end, { size = 28, fill = C.clear, color = C.muted }))
  return nodes
end

function M.render(m)
  local lists = m.lists or {}
  local current = m.chat and m.chat.sessionId
  local items = {}
  if lists.deleteFailed ~= nil then
    table.insert(items, ui.row({ key = "chats-failed", fill = C.soft, radius = 10, paddingH = 10, paddingV = 8, gap = 8, align = "center" }, {
      ui.glyph({ key = "chats-failed-g", name = "alert-triangle", size = 14, color = C.bad }),
      common.muted("chats-failed-t", tr("hermes.chats.delete_" .. lists.deleteFailed), { flexGrow = 1, maxLines = 2 }),
    }))
  end
  if lists.chats == nil then
    table.insert(items, if lists.problem and lists.problem.chats
      then common.problem("chats-problem", m.cb.cmd)
      else common.muted("chats-loading", tr("hermes.loading")))
  elseif #lists.chats == 0 then
    table.insert(items, common.empty("chats-empty", "messages", tr("hermes.chats.empty")))
  end
  for _, row in lists.chats or {} do
    local confirming = m.confirmDelete == row.id
    table.insert(items, common.row("chat-" .. row.id, "message-circle", row.title, row.ago, trailing(m, row, current), function()
      if confirming then
        m.cb.cancelDelete()
      else
        m.cb.cmd("adopt", { id = row.id })
      end
    end))
  end
  return common.panel("chats", {
    common.header("chats-head", tr("hermes.chats.title"), function()
      m.cb.cmd("refresh", { id = "chats" })
    end),
    common.scroll("chats-scroll", items),
  })
end

return M
