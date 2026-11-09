local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

-- Difficulty guarantees: the grid size is the level (small 8 pairs, medium
-- 10, large 12); each size deals every pair exactly twice, face down; a
-- seed always deals the same grid.
local SIZES = { "small", "medium", "large" }
local EXPECTED = { small = { 4, 4, 8 }, medium = { 4, 5, 10 }, large = { 4, 6, 12 } }

describe("Memory difficulty", function()
    local Board

    setup(function()
        Board = require("board")
    end)

    local function newBoard(size, seed)
        math.randomseed(seed or 42)
        local b = Board:new({ grid_size = size or "small", players = 1 })
        b:setup()
        return b
    end

    local function deal(b)
        local t = {}
        for r = 1, b.rows do
            for c = 1, b.cols do t[#t + 1] = b.cards[r][c].value end
        end
        return t
    end

    it("builds a 4x4 grid with every value appearing exactly twice", function()
        local b = newBoard("small")
        assert.are.equal(4, b.rows)
        assert.are.equal(4, b.cols)
        assert.are.equal(8, b.n_pairs)
        local counts = {}
        for r = 1, b.rows do
            for c = 1, b.cols do
                local v = b.cards[r][c].value
                counts[v] = (counts[v] or 0) + 1
                assert.are.equal("hidden", b.cards[r][c].state)
            end
        end
        for v = 1, b.n_pairs do
            assert.are.equal(2, counts[v])
        end
    end)

    it("every size deals its pairs exactly twice each, more pairs as it grows", function()
        local prev = 0
        for _, size in ipairs(SIZES) do
            for seed = 1, 5 do
                local b = newBoard(size, seed)
                assert.are.same(EXPECTED[size], { b.rows, b.cols, b.n_pairs })
                local counts = {}
                for _, v in ipairs(deal(b)) do counts[v] = (counts[v] or 0) + 1 end
                for v = 1, b.n_pairs do assert.are.equal(2, counts[v], size) end
            end
            assert.is_true(EXPECTED[size][3] > prev, size)
            prev = EXPECTED[size][3]
        end
    end)

    it("the same seed deals the same grid", function()
        for _, size in ipairs(SIZES) do
            assert.are.same(deal(newBoard(size, 9)), deal(newBoard(size, 9)))
        end
    end)
end)
