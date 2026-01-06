require("lunit")
local Queue = require("collection/queue")

describe("Queue", function()
    describe("constructor", function()
        it("creates an empty queue if no iterable is provided", function()
            local q = Queue:new()
            expect(q).to.have.a.property("length", 0)
            expect(q:toSeq()).to.deep.equal({})
        end)
    end)

    describe(":push()", function()
        it("inserts an element at the back of the queue", function()
            local q = Queue:new()
            q:push("foo")
            q:push("bar")
            q:push("baz")
            expect(q).to.have.a.property("length", 3)
            expect(q:toSeq()).to.deep.equal({"foo", "bar", "baz"})
        end)

        it("can wrap around due to shift and still functions correctly", function()
            local q = Queue:new()

            -- Insert 4 elements. Now it should be physically full.
            q:push("a")
            q:push("b")
            q:push("c")
            q:push("d")

            -- Remove 2 elements from the front. Now there are 2 empty
            -- slots at the beginning.
            q:shift()
            q:shift()
            expect(q:toSeq()).to.deep.equal({"c", "d"})

            -- Pusing the next element should wrap it around.
            q:push("e")
            expect(q:toSeq()).to.deep.equal({"c", "d", "e"})

            -- Popping the last element should wrap it back.
            expect(q:pop()).to.equal("e")
            expect(q:toSeq()).to.deep.equal({"c", "d"})
        end)
    end)

    describe(":pop()", function()
        it("removes an element at the back of the queue", function()
            local q = Queue:new()
            q:push("foo")
            q:push("bar")
            expect(q:pop()).to.equal("bar")
            expect(q:pop()).to.equal("foo")
            expect(q:pop()).to.be.null()
        end)
    end)

    describe(":unshift()", function()
        it("inserts an element at the front of the queue", function()
            local q = Queue:new()
            q:unshift("foo")
            q:unshift("bar")
            q:unshift("baz")
            expect(q).to.have.a.property("length", 3)
            expect(q:toSeq()).to.deep.equal({"baz", "bar", "foo"})
        end)

        it("can wrap around due to pop and still functions correctly", function()
            local q = Queue:new()

            -- Insert 4 elements. Now it should be physically full.
            q:push("a")
            q:push("b")
            q:push("c")
            q:push("d")

            -- Remove 2 elements from the back. Now there are 2 empty slots
            -- at the end.
            q:pop()
            q:pop()

            -- Unshifting the next element should wrap it around.
            q:unshift("e")
            expect(q:toSeq()).to.deep.equal({"e", "a", "b"})

            -- Shifting the last element should wrap it back.
            expect(q:shift()).to.equal("e")
            expect(q:toSeq()).to.deep.equal({"a", "b"})
        end)
    end)

    describe(":shift()", function()
        it("removes an element at the front of the queue", function()
            local q = Queue:new()
            q:push("foo")
            q:push("bar")
            expect(q:shift()).to.equal("foo")
            expect(q:shift()).to.equal("bar")
            expect(q:shift()).to.be.null()
        end)
    end)

    describe("tostring()", function()
        it("reasonably stringifies a queue", function()
            local q = Queue:new()
            q:push(1)
            q:push(2)
            expect(tostring(q)).to.equal("Queue {1, 2}")
        end)
    end)
end)
