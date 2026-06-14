-- ---------------------------------------------------------------------------
-- MemoryBoardWidget — renders the Memory (pairs) card grid
-- ---------------------------------------------------------------------------

local Blitbuffer     = require("ffi/blitbuffer")
local Device         = require("device")
local Font           = require("ui/font")
local Geom           = require("ui/geometry")
local GestureRange   = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText     = require("ui/rendertext")
local UIManager      = require("ui/uimanager")

local Screen = Device.screen

local C_BG       = Blitbuffer.COLOR_WHITE
local C_BORDER   = Blitbuffer.COLOR_BLACK
local C_HIDDEN   = Blitbuffer.COLOR_GRAY_4
local C_PATTERN  = Blitbuffer.COLOR_GRAY_5
local C_FACE     = Blitbuffer.COLOR_WHITE
local C_MATCHED  = Blitbuffer.COLOR_GRAY_E
local C_TEXT     = Blitbuffer.COLOR_BLACK
local C_TEXT_M   = Blitbuffer.COLOR_GRAY_9

-- ---------------------------------------------------------------------------
-- MemoryBoardWidget
-- ---------------------------------------------------------------------------

local MemoryBoardWidget = InputContainer:extend{
    board        = nil,
    onCellAction = nil,
    size_ratio   = 0.78,
}

function MemoryBoardWidget:init()
    local board   = self.board
    local ncols   = board.cols or 4
    local nrows   = board.rows or 4
    self.n_cols   = ncols
    self.n_rows   = nrows

    local sw      = Screen:getWidth()
    local sh      = Screen:getHeight()
    local base    = math.floor(math.min(sw, sh) * self.size_ratio)
    -- Keep cells square: use smallest dimension that fits both rows and cols
    local cell    = math.min(math.floor(base / ncols), math.floor(base / nrows))
    self.cell_w   = cell
    self.cell_h   = cell

    local bw      = cell * ncols
    local bh      = cell * nrows
    self.board_w  = bw
    self.board_h  = bh

    self.dimen      = Geom:new{ w = bw, h = bh }
    self.paint_rect = Geom:new{ x = 0, y = 0, w = bw, h = bh }

    -- Fit a font for card labels (values up to 12 digits)
    local max_w    = math.floor(cell * 0.65)
    local max_h    = math.floor(cell * 0.65)
    local fsize    = math.max(10, math.floor(cell * 0.55))
    while fsize > 10 do
        local face = Font:getFace("cfont", fsize)
        local m    = RenderText:sizeUtf8Text(0, max_w, face, "12", true, false)
        local fh   = m.y_bottom - m.y_top
        if m.x <= max_w and fh <= max_h then break end
        fsize = fsize - 1
    end
    self.card_face = Font:getFace("cfont", fsize)

    self.ges_events = {
        Tap = {
            GestureRange:new{
                ges   = "tap",
                range = Geom:new{ x = 0, y = 0, w = sw, h = sh },
            },
        },
    }
end

function MemoryBoardWidget:onTap(_, ges)
    if not (ges and ges.pos) then return false end
    local rect = self.paint_rect
    local lx   = ges.pos.x - rect.x
    local ly   = ges.pos.y - rect.y
    if lx < 0 or ly < 0 or lx >= rect.w or ly >= rect.h then return false end
    local col  = math.min(self.n_cols, math.floor(lx / self.cell_w) + 1)
    local row  = math.min(self.n_rows, math.floor(ly / self.cell_h) + 1)
    if row >= 1 and col >= 1 and self.onCellAction then
        self.onCellAction(row, col)
    end
    return true
end

function MemoryBoardWidget:paintTo(bb, x, y)
    self.paint_rect = Geom:new{ x = x, y = y, w = self.board_w, h = self.board_h }

    local board  = self.board
    local ncols  = self.n_cols
    local nrows  = self.n_rows
    local cw     = self.cell_w
    local ch     = self.cell_h
    local face   = self.card_face

    bb:paintRect(x, y, self.board_w, self.board_h, C_BG)

    for r = 1, nrows do
        for c = 1, ncols do
            local cx  = x + (c - 1) * cw
            local cy  = y + (r - 1) * ch
            local brd = math.max(1, math.floor(math.min(cw, ch) * 0.05))
            local pad = math.max(3, math.floor(math.min(cw, ch) * 0.07))

            -- Outer cell border
            bb:paintRect(cx,           cy,           cw, brd, C_BORDER)
            bb:paintRect(cx,           cy + ch - brd, cw, brd, C_BORDER)
            bb:paintRect(cx,           cy,           brd, ch, C_BORDER)
            bb:paintRect(cx + cw - brd, cy,           brd, ch, C_BORDER)

            local ix = cx + pad
            local iy = cy + pad
            local iw = cw - 2 * pad
            local ih = ch - 2 * pad

            local card = board.cards[r] and board.cards[r][c]
            if not card then goto continue end

            if card.state == "hidden" then
                bb:paintRect(ix, iy, iw, ih, C_HIDDEN)
                -- Vertical stripe pattern on back
                local step = math.max(4, math.floor(cw * 0.18))
                local lw   = math.max(1, math.floor(step * 0.35))
                local off  = 0
                while off < iw do
                    local px = ix + off
                    local pw = math.min(lw, ix + iw - px)
                    if pw > 0 then
                        bb:paintRect(px, iy, pw, ih, C_PATTERN)
                    end
                    off = off + step
                end
            else
                -- Revealed or matched
                local bg  = (card.state == "matched") and C_MATCHED or C_FACE
                local tc  = (card.state == "matched") and C_TEXT_M  or C_TEXT
                bb:paintRect(ix, iy, iw, ih, bg)

                local label = tostring(card.value)
                local m     = RenderText:sizeUtf8Text(0, iw, face, label, true, false)
                local fh    = m.y_bottom - m.y_top
                local tx    = ix + math.floor((iw - m.x) / 2)
                local ty    = iy + math.floor((ih - fh) / 2) + math.abs(m.y_top)
                RenderText:renderUtf8Text(bb, tx, ty, face, label, true, false, tc)
            end

            ::continue::
        end
    end
end

function MemoryBoardWidget:refresh()
    local rect = self.paint_rect
    UIManager:setDirty(self, function()
        return "ui", Geom:new{ x = rect.x, y = rect.y, w = rect.w, h = rect.h }
    end)
end

return MemoryBoardWidget
