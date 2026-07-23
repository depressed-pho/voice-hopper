require("lunit")
local Event        = require("event/base")
local EventEmitter = require("event/emitter")
local Set          = require("collection/set")
local class        = require("class")

local SomeEvent = class("SomeEvent", Event)
function SomeEvent:__init(value)
    self.value = value
end

describe("EventEmitter", function()
    describe("unrestricted event emitter", function()
        it("does not have a property allowedEvents", function()
            local ee = EventEmitter():new()
            expect(ee.allowedEvents).to.be.null()
            expect(ee:isAllowed("something-you-dont-know")).to.be._true_()
        end)
    end)
    describe(":on()", function()
        it("subscribes to an event", function()
            local ee = EventEmitter():new()
            expect(ee.listenedEvents:toSeq()).to.have.members({})

            local out = nil
            ee:on("foo", function(ev)
                expect(ev).to.be.a(SomeEvent)
                out = ev.value
            end)
            expect(ee.listenedEvents:toSeq()).to.have.members({"foo"})

            ee:emit("foo", SomeEvent:new(42))
            expect(out).to.equal(42)

            ee:emit("foo", SomeEvent:new(43))
            expect(out).to.equal(43)
        end)
        it("allows duplicate subscription of the same listener", function()
            local ee = EventEmitter():new()

            local out  = 0
            local incr = function() out = out + 1 end
            ee:on("foo", incr)
            ee:on("foo", incr)

            ee:emit("foo", SomeEvent:new())
            expect(out).to.equal(2)
        end)
        describe("oneShot", function()
            it("subscribes to an event but listens only once", function()
                local ee  = EventEmitter():new()
                local out = nil
                ee:on("foo", function(ev)
                    expect(ev).to.be.a(SomeEvent)
                    out = ev.value
                end, {oneShot = true})

                ee:emit("foo", SomeEvent:new(42))
                expect(out).to.equal(42)

                ee:emit("foo", SomeEvent:new(43))
                expect(out).to.equal(42)

                expect(ee.listenedEvents:toSeq()).to.have.members({})
            end)
        end)
    end)
    describe(":countListeners()", function()
        it("counts the number of listeners of an event", function()
            local ee = EventEmitter():new()

            local l1 = function() end
            local l2 = function() end
            ee:on("foo", l1)
            ee:on("foo", l1)
            ee:on("foo", l2)

            expect(ee:countListeners("foo")).to.equal(3)
            expect(ee:countListeners("foo", l1)).to.equal(2)
        end)
    end)
    describe("restricted event emitter", function()
        it("raises an error for unknown events", function()
            local ee = EventEmitter():new(Set:new {"foo"})

            expect(function() ee:on("foo", function() end) end).to._not_.throw()
            expect(function() ee:on("bar", function() end) end).to.throw()

            expect(function() ee:emit("foo", SomeEvent:new()) end).to._not_.throw()
            expect(function() ee:emit("bar", SomeEvent:new()) end).to.throw()

            expect(ee:isAllowed("foo")).to.be._true_()
            expect(ee:isAllowed("bar")).to.be._false_()
        end)
        it("has a property allowedEvents", function()
            local ee = EventEmitter():new(Set:new {"foo", "bar"})
            expect(ee.allowedEvents:toSeq()).to.have.members({"foo", "bar"})
        end)
    end)
    describe("newListener", function()
        it("is emitted before a new listener shows up", function()
            local ee = EventEmitter():new()

            local out
            ee:on("newListener", function(ev)
                expect(ev).to.be.a(ee.ListenerEvent)
                out = ev
            end)

            local listener = function() end
            ee:on("foo", listener)
            expect(out).to.have.property("name", "foo")
            expect(out).to.have.property("func", listener)
        end)
    end)
    describe("removeListener", function()
        it("is emitted after an existing listener goes away", function()
            local ee = EventEmitter():new()

            local out
            ee:on("removeListener", function(ev)
                expect(ev).to.be.a(ee.ListenerEvent)
                out = ev
            end)

            local listener = function() end
            ee:off("foo", listener)
            expect(out).to.be.null() -- Because nothing has subscribed to it yet.

            ee:on("foo", listener)
            ee:off("foo", listener)
            expect(out).to.have.property("name", "foo")
            expect(out).to.have.property("func", listener)
        end)
    end)
end)
