local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

describe("MemoryBoard", function()
    local Board

    setup(function()
        Board = require("board")
    end)

    local function newBoard(size, players)
        math.randomseed(42)
        local b = Board:new({ grid_size = size or "small", players = players or 1 })
        b:setup()
        return b
    end

    describe("setup", function()
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
    end)

    describe("tapCard", function()
        it("reveals the first card of a turn", function()
            local b = newBoard()
            assert.are.equal("reveal1", b:tapCard(1, 1))
            assert.are.equal("revealed", b.cards[1][1].state)
            assert.is_true(b.waiting_second)
        end)

        it("reports already_revealed for the same card tapped twice", function()
            local b = newBoard()
            b:tapCard(1, 1)
            assert.are.equal("already_revealed", b:tapCard(1, 1))
        end)

        it("matches two cards with the same value and scores a point", function()
            local b = newBoard()
            -- Find a matching pair.
            local pos = {}
            for v = 1, b.n_pairs do pos[v] = {} end
            for r = 1, b.rows do
                for c = 1, b.cols do
                    local v = b.cards[r][c].value
                    pos[v][#pos[v] + 1] = { r, c }
                end
            end
            local a, bb = pos[1][1], pos[1][2]
            b:tapCard(a[1], a[2])
            assert.are.equal("match", b:tapCard(bb[1], bb[2]))
            assert.are.equal("matched", b.cards[a[1]][a[2]].state)
            assert.are.equal("matched", b.cards[bb[1]][bb[2]].state)
            assert.are.equal(1, b.scores[1])
        end)

        it("reports no_match for two different values without hiding them", function()
            local b = newBoard()
            local pos = {}
            for v = 1, b.n_pairs do pos[v] = {} end
            for r = 1, b.rows do
                for c = 1, b.cols do
                    local v = b.cards[r][c].value
                    pos[v][#pos[v] + 1] = { r, c }
                end
            end
            local a, bb = pos[1][1], pos[2][1]
            b:tapCard(a[1], a[2])
            assert.are.equal("no_match", b:tapCard(bb[1], bb[2]))
            assert.are.equal("revealed", b.cards[a[1]][a[2]].state)
            assert.are.equal("revealed", b.cards[bb[1]][bb[2]].state)
        end)
    end)

    describe("hideRevealed", function()
        it("hides both revealed cards and switches player in 2-player mode", function()
            local b = newBoard("small", 2)
            local pos = {}
            for v = 1, b.n_pairs do pos[v] = {} end
            for r = 1, b.rows do
                for c = 1, b.cols do
                    pos[b.cards[r][c].value][#pos[b.cards[r][c].value] + 1] = { r, c }
                end
            end
            local a, bb = pos[1][1], pos[2][1]
            b:tapCard(a[1], a[2])
            b:tapCard(bb[1], bb[2])
            b:hideRevealed()
            assert.are.equal("hidden", b.cards[a[1]][a[2]].state)
            assert.are.equal("hidden", b.cards[bb[1]][bb[2]].state)
            assert.are.equal(2, b.current_player)
        end)
    end)

    describe("isComplete / matchedCount", function()
        it("is complete once every pair is matched", function()
            local b = newBoard()
            for r = 1, b.rows do
                for c = 1, b.cols do
                    b.cards[r][c].state = "matched"
                end
            end
            assert.is_true(b:isComplete())
            assert.are.equal(b.n_pairs, b:matchedCount())
        end)
    end)

    describe("serialize / load", function()
        it("round-trips cards, scores and turn state", function()
            local b = newBoard("small", 2)
            b:tapCard(1, 1)
            local data = b:serialize()

            local b2 = Board:new()
            assert.is_true(b2:load(data))
            assert.are.equal(b.rows, b2.rows)
            assert.are.equal(b.cards[1][1].value, b2.cards[1][1].value)
            -- load() resolves any mid-flip state back to hidden.
            assert.are.equal("hidden", b2.cards[1][1].state)
        end)

        it("load returns false for invalid data", function()
            local b = newBoard()
            assert.is_false(b:load(nil))
            assert.is_false(b:load({}))
        end)
    end)
end)
