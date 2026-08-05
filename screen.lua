-- ---------------------------------------------------------------------------
-- MemoryScreen — full-screen UI for the Memory (pairs) game
-- ---------------------------------------------------------------------------

local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local ButtonTable     = require("ui/widget/buttontable")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")

local MenuHelper          = require("menu_helper")
local ScreenBase          = require("screen_base")

local MemoryBoard         = lrequire("board")
local MemoryBoardWidget   = lrequire("board_widget")

local DeviceScreen = Device.screen

-- Delay (seconds) before hiding a non-matching pair
local FLIP_BACK_DELAY = 1.0

local GRID_LABELS = {
    small  = _("4×4"),
    medium = _("4×5"),
    large  = _("4×6"),
}

-- ---------------------------------------------------------------------------
-- MemoryScreen
-- ---------------------------------------------------------------------------

local GAME_RULES_EN = _([[
Memory (Concentration) — Rules

Find all matching pairs of face-down cards by flipping two at a time.

On your turn:
1. Tap any face-down card to flip it over.
2. Tap a second face-down card to flip it.
3. If the two cards match, they remain face up.
4. If they do not match, both cards flip back face down after a short pause.

Remember the positions of cards you have seen to find matches more quickly.
The game is won when all pairs have been matched.
]])

local GAME_RULES_FR = [[
Mémoire (Concentration) — Règles

Trouvez toutes les paires de cartes face cachée en en retournant deux à la fois.

À votre tour :
1. Appuyez sur une carte face cachée pour la retourner.
2. Appuyez sur une deuxième carte face cachée.
3. Si les deux cartes correspondent, elles restent face visible.
4. Si elles ne correspondent pas, les deux cartes se retournent face cachée après une courte pause.

Mémorisez la position des cartes que vous avez vues pour trouver les paires plus rapidement.
La partie est gagnée quand toutes les paires ont été trouvées.
]]

local MemoryScreen = ScreenBase:extend{}

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function MemoryScreen:init()
    local state     = self.plugin:loadState()
    local grid_size = self.plugin:getSetting("grid_size", "small")
    local players   = self.plugin:getSetting("players", 1)

    self.board = MemoryBoard:new{ grid_size = grid_size, players = players }
    if not self.board:load(state) then
        self.board:setup()
    end

    self._flipping = false  -- true while waiting to hide a non-matched pair

    ScreenBase.init(self)
end

function MemoryScreen:serializeState()
    return self.board:serialize()
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function MemoryScreen:buildLayout()
    local board = self.board

    self.board_widget = MemoryBoardWidget:new{
        board        = board,
        onCellAction = function(r, c) self:onCellAction(r, c) end,
    }

    local is_landscape = self:isLandscape()
    local sw = DeviceScreen:getWidth()

    local board_frame = FrameContainer:new{
        padding = Size.padding.default,
        margin  = Size.margin.default,
        self.board_widget,
    }

    local bw_size    = self.board_widget.board_w
        + (Size.padding.default + Size.margin.default) * 2
    local buttons_w  = is_landscape
        and math.max(sw - bw_size - Size.span.horizontal_default * 2, 100)
        or  math.floor(sw * 0.92)

    -- The status line can get long ("Paires trouvées: 1 / 8  Coups: 12").
    -- In portrait it sits directly alongside board_frame in the same
    -- VerticalGroup, which centers each child against the widest one --
    -- unbounded, a long status string overflows past the screen edge
    -- instead of wrapping, getting cut off rather than centered. Bind it
    -- to the board's own width there; in landscape it's alone in the
    -- right-hand panel, so buttons_w is the correct reference.
    self.status_text:setMaxWidth(is_landscape and buttons_w or bw_size)

    local title_bar = self:buildTitleBar(_("Memory"), function()
        return {
            { text = _("New"),                  callback = function() self:onNewGame() end },
            { text = self:_getGridButtonText(),     callback = function() self:openGridMenu() end },
            { text = self:_getPlayersButtonText(),  callback = function() self:openPlayersMenu() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)

    if is_landscape then
        local right_panel = VerticalGroup:new{
            align = "center",
            self.status_text,
        }
        local content = HorizontalGroup:new{
            align = "center",
            board_frame,
            HorizontalSpan:new{ width = Size.span.horizontal_default },
            right_panel,
        }
        self:buildLandscapeLayout(title_bar, content)
    else
        local content = VerticalGroup:new{
            align = "center",
            board_frame,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
        }
        self:buildPortraitLayout(title_bar, content, nil)
    end

    self:updateStatus()
end

-- ---------------------------------------------------------------------------
-- Cell interaction
-- ---------------------------------------------------------------------------

function MemoryScreen:onCellAction(r, c)
    -- Block input while waiting for flip-back animation
    if self._flipping then return end
    if self.board.status ~= "playing" then return end

    local result = self.board:tapCard(r, c)

    if result == "reveal1" then
        self.board_widget:refresh()
        self:updateStatus()

    elseif result == "match" then
        self.board_widget:refresh()
        self.plugin:saveState(self.board:serialize())
        self:updateStatus()
        if self.board.status == "won" then
            UIManager:scheduleIn(0.3, function() self:onGameWon() end)
        end

    elseif result == "no_match" then
        self._flipping = true
        self.board_widget:refresh()
        self:updateStatus()
        UIManager:scheduleIn(FLIP_BACK_DELAY, function()
            self.board:hideRevealed()
            self._flipping = false
            self.board_widget:refresh()
            self.plugin:saveState(self.board:serialize())
            self:updateStatus()
        end)

    -- "already_matched", "already_revealed", "invalid": ignore
    end
end

-- ---------------------------------------------------------------------------
-- New game
-- ---------------------------------------------------------------------------

function MemoryScreen:onNewGame()
    -- Cancel any pending flip-back
    self._flipping = false
    local grid_size = self.plugin:getSetting("grid_size", "small")
    local players   = self.plugin:getSetting("players", 1)
    self.board = MemoryBoard:new{ grid_size = grid_size, players = players }
    self.board:setup()
    self.plugin:saveState(self.board:serialize())
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

-- ---------------------------------------------------------------------------
-- Game won
-- ---------------------------------------------------------------------------

function MemoryScreen:onGameWon()
    local board   = self.board
    local turns   = board.turns
    local players = board.players
    local msg
    if players == 2 then
        local s1, s2 = board.scores[1], board.scores[2]
        if s1 > s2 then
            msg = string.format(_("Player 1 wins! %d − %d  (%d moves)"), s1, s2, turns)
        elseif s2 > s1 then
            msg = string.format(_("Player 2 wins! %d − %d  (%d moves)"), s2, s1, turns)
        else
            msg = string.format(_("Tie! %d − %d  (%d moves)"), s1, s2, turns)
        end
    else
        msg = string.format(_("Well done! All pairs found in %d moves."), turns)
    end
    self:showMessage(msg, 5)
    self:updateStatus()
end

-- ---------------------------------------------------------------------------
-- Status bar
-- ---------------------------------------------------------------------------

function MemoryScreen:updateStatus(msg)
    local status
    if msg then
        status = msg
    else
        local board   = self.board
        local players = board.players
        if board.status == "won" then
            if players == 2 then
                local s1, s2 = board.scores[1], board.scores[2]
                if s1 > s2 then
                    status = string.format(_("Player 1 wins! %d − %d"), s1, s2)
                elseif s2 > s1 then
                    status = string.format(_("Player 2 wins! %d − %d"), s2, s1)
                else
                    status = string.format(_("Tie! %d − %d"), s1, s2)
                end
            else
                status = string.format(_("Well done! %d moves"), board.turns)
            end
        else
            local matched = board:matchedCount()
            local total   = board.n_pairs
            if players == 2 then
                local cp = board.current_player
                status = string.format(_("Player %d  Pairs: %d/%d  P1: %d  P2: %d"),
                    cp, matched, total, board.scores[1], board.scores[2])
            else
                status = string.format(_("Pairs found: %d / %d  Moves: %d"),
                    matched, total, board.turns)
            end
        end
    end
    ScreenBase.updateStatus(self, status)
end

-- ---------------------------------------------------------------------------
-- Button label helpers
-- ---------------------------------------------------------------------------

function MemoryScreen:_getGridButtonText()
    local gs = self.plugin:getSetting("grid_size", "small")
    return GRID_LABELS[gs] or gs
end

function MemoryScreen:_getPlayersButtonText()
    local p = self.plugin:getSetting("players", 1)
    return p == 1 and _("1 player") or _("2 players")
end

-- ---------------------------------------------------------------------------
-- Menus
-- ---------------------------------------------------------------------------

function MemoryScreen:openGridMenu()
    MenuHelper.openPickerMenu{
        title      = _("Grid size"),
        items      = {
            { id = "small",  text = _("Small (4×4 — 8 pairs)")  },
            { id = "medium", text = _("Medium (4×5 — 10 pairs)") },
            { id = "large",  text = _("Large (4×6 — 12 pairs)")  },
        },
        current_id = self.plugin:getSetting("grid_size", "small"),
        on_select  = function(id)
            self.plugin:saveSetting("grid_size", id)
            local btn = self.top_buttons and self.top_buttons:getButtonById("grid_btn")
            if btn then btn:setText(self:_getGridButtonText(), btn.width) end
            self:onNewGame()
        end,
        parent = self,
    }
end

function MemoryScreen:openPlayersMenu()
    MenuHelper.openPickerMenu{
        title      = _("Number of players"),
        items      = {
            { id = 1, text = _("1 player") },
            { id = 2, text = _("2 players") },
        },
        current_id = self.plugin:getSetting("players", 1),
        on_select  = function(id)
            self.plugin:saveSetting("players", id)
            local btn = self.top_buttons and self.top_buttons:getButtonById("players_btn")
            if btn then btn:setText(self:_getPlayersButtonText(), btn.width) end
            self:onNewGame()
        end,
        parent = self,
    }
end

return MemoryScreen
