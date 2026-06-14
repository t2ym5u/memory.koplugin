-- ---------------------------------------------------------------------------
-- MemoryBoard — game logic for the Mémoire (pairs/memory) game
-- ---------------------------------------------------------------------------

local MemoryBoard = {}
MemoryBoard.__index = MemoryBoard

-- Grid configurations: { rows, cols }
local GRID_CONFIGS = {
    small  = { rows = 4, cols = 4 },   -- 16 cells = 8 pairs
    medium = { rows = 4, cols = 5 },   -- 20 cells = 10 pairs
    large  = { rows = 4, cols = 6 },   -- 24 cells = 12 pairs
}

-- Fisher-Yates shuffle on a flat array
local function shuffleFlat(arr)
    for i = #arr, 2, -1 do
        local j = math.random(i)
        arr[i], arr[j] = arr[j], arr[i]
    end
end

-- ---------------------------------------------------------------------------
-- Constructor
-- ---------------------------------------------------------------------------

function MemoryBoard:new(opts)
    opts = opts or {}
    local o = setmetatable({}, self)
    o.grid_size = opts.grid_size or "small"
    o.players   = tonumber(opts.players) or 1
    -- These will be set properly by :setup()
    o.rows      = 0
    o.cols      = 0
    o.n_pairs   = 0
    o.cards     = {}
    o.revealed_1      = nil
    o.revealed_2      = nil
    o.waiting_second  = false
    o.current_player  = 1
    o.scores          = { [1] = 0, [2] = 0 }
    o.turns           = 0
    o.status          = "playing"
    return o
end

-- ---------------------------------------------------------------------------
-- Setup / generate
-- ---------------------------------------------------------------------------

function MemoryBoard:setup(grid_size, players)
    grid_size = grid_size or self.grid_size
    players   = players   or self.players

    self.grid_size = grid_size
    self.players   = tonumber(players) or 1

    local cfg = GRID_CONFIGS[grid_size] or GRID_CONFIGS.small
    self.rows    = cfg.rows
    self.cols    = cfg.cols
    self.n_pairs = math.floor((self.rows * self.cols) / 2)

    -- Build flat array with each value appearing exactly twice
    local flat = {}
    for v = 1, self.n_pairs do
        flat[#flat + 1] = v
        flat[#flat + 1] = v
    end
    shuffleFlat(flat)

    -- Fill cards grid
    self.cards = {}
    local idx = 1
    for r = 1, self.rows do
        self.cards[r] = {}
        for c = 1, self.cols do
            self.cards[r][c] = {
                value = flat[idx],
                state = "hidden",
            }
            idx = idx + 1
        end
    end

    self.revealed_1     = nil
    self.revealed_2     = nil
    self.waiting_second = false
    self.current_player = 1
    self.scores         = { [1] = 0, [2] = 0 }
    self.turns          = 0
    self.status         = "playing"
end

-- ---------------------------------------------------------------------------
-- Tap logic
-- ---------------------------------------------------------------------------

-- Returns: "reveal1", "reveal2", "match", "no_match",
--          "already_matched", "already_revealed", "invalid"
function MemoryBoard:tapCard(r, c)
    if self.status ~= "playing" then return "invalid" end
    if r < 1 or r > self.rows or c < 1 or c > self.cols then return "invalid" end

    local card = self.cards[r][c]
    if card.state == "matched" then
        return "already_matched"
    end
    if card.state == "revealed" then
        return "already_revealed"
    end
    -- card.state == "hidden"

    card.state = "revealed"

    if not self.waiting_second then
        -- First card of a new turn
        self.revealed_1     = { r, c }
        self.revealed_2     = nil
        self.waiting_second = true
        return "reveal1"
    else
        -- Second card
        self.revealed_2     = { r, c }
        self.waiting_second = false
        self.turns          = self.turns + 1

        local r1, c1 = self.revealed_1[1], self.revealed_1[2]
        if self.cards[r1][c1].value == card.value then
            -- Match! Mark both immediately
            self.cards[r1][c1].state = "matched"
            card.state               = "matched"
            self.scores[self.current_player] = self.scores[self.current_player] + 1
            self.revealed_1 = nil
            self.revealed_2 = nil
            if self:isComplete() then
                self.status = "won"
            end
            -- On a match, the same player goes again (don't switch)
            return "match"
        else
            -- No match — keep both revealed; screen will call hideRevealed after delay
            return "no_match"
        end
    end
end

-- ---------------------------------------------------------------------------
-- Hide revealed cards (called by screen after delay on no_match)
-- ---------------------------------------------------------------------------

function MemoryBoard:hideRevealed()
    if self.revealed_1 then
        local r, c = self.revealed_1[1], self.revealed_1[2]
        if self.cards[r][c].state == "revealed" then
            self.cards[r][c].state = "hidden"
        end
    end
    if self.revealed_2 then
        local r, c = self.revealed_2[1], self.revealed_2[2]
        if self.cards[r][c].state == "revealed" then
            self.cards[r][c].state = "hidden"
        end
    end
    self.revealed_1     = nil
    self.revealed_2     = nil
    self.waiting_second = false

    -- Switch player in 2-player mode on a miss
    if self.players == 2 then
        self.current_player = (self.current_player == 1) and 2 or 1
    end
end

-- ---------------------------------------------------------------------------
-- Query helpers
-- ---------------------------------------------------------------------------

function MemoryBoard:isComplete()
    for r = 1, self.rows do
        for c = 1, self.cols do
            if self.cards[r][c].state ~= "matched" then
                return false
            end
        end
    end
    return true
end

function MemoryBoard:matchedCount()
    local n = 0
    for r = 1, self.rows do
        for c = 1, self.cols do
            if self.cards[r][c].state == "matched" then
                n = n + 1
            end
        end
    end
    return n / 2  -- return pairs, not cells
end

-- ---------------------------------------------------------------------------
-- Serialization
-- ---------------------------------------------------------------------------

function MemoryBoard:serialize()
    local cards_copy = {}
    for r = 1, self.rows do
        cards_copy[r] = {}
        for c = 1, self.cols do
            cards_copy[r][c] = {
                value = self.cards[r][c].value,
                state = self.cards[r][c].state,
            }
        end
    end

    local rev1_copy = nil
    if self.revealed_1 then
        rev1_copy = { self.revealed_1[1], self.revealed_1[2] }
    end
    local rev2_copy = nil
    if self.revealed_2 then
        rev2_copy = { self.revealed_2[1], self.revealed_2[2] }
    end

    return {
        grid_size       = self.grid_size,
        players         = self.players,
        rows            = self.rows,
        cols            = self.cols,
        n_pairs         = self.n_pairs,
        cards           = cards_copy,
        revealed_1      = rev1_copy,
        revealed_2      = rev2_copy,
        waiting_second  = self.waiting_second,
        current_player  = self.current_player,
        scores          = { [1] = self.scores[1], [2] = self.scores[2] },
        turns           = self.turns,
        status          = self.status,
    }
end

function MemoryBoard:load(data)
    if type(data) ~= "table" or not data.cards or not data.rows then
        return false
    end

    self.grid_size      = data.grid_size      or "small"
    self.players        = tonumber(data.players) or 1
    self.rows           = tonumber(data.rows)    or 4
    self.cols           = tonumber(data.cols)    or 4
    self.n_pairs        = tonumber(data.n_pairs) or 8
    self.waiting_second = data.waiting_second    or false
    self.current_player = tonumber(data.current_player) or 1
    self.turns          = tonumber(data.turns) or 0
    self.status         = data.status or "playing"

    local sc = data.scores or {}
    self.scores = {
        [1] = tonumber(sc[1]) or 0,
        [2] = tonumber(sc[2]) or 0,
    }

    -- Restore cards
    self.cards = {}
    for r = 1, self.rows do
        self.cards[r] = {}
        for c = 1, self.cols do
            local src = (data.cards[r] or {})[c] or {}
            self.cards[r][c] = {
                value = tonumber(src.value) or 0,
                state = src.state or "hidden",
            }
        end
    end

    -- Restore revealed positions
    self.revealed_1 = nil
    self.revealed_2 = nil
    if data.revealed_1 and data.revealed_1[1] then
        self.revealed_1 = { data.revealed_1[1], data.revealed_1[2] }
    end
    if data.revealed_2 and data.revealed_2[1] then
        self.revealed_2 = { data.revealed_2[1], data.revealed_2[2] }
    end

    -- Consistency: if we had two revealed cards loaded, they were in mid-flip
    -- Just hide them both so the game resumes cleanly
    if self.revealed_1 then
        local r, c = self.revealed_1[1], self.revealed_1[2]
        self.cards[r][c].state = "hidden"
        self.revealed_1        = nil
    end
    if self.revealed_2 then
        local r, c = self.revealed_2[1], self.revealed_2[2]
        self.cards[r][c].state = "hidden"
        self.revealed_2        = nil
    end
    self.waiting_second = false

    return true
end

return MemoryBoard
