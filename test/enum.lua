require("lunit")
local enum = require("enum")

describe("enum()", function()
    local Test = enum {
        "Foo",
        "Bar",
        "Baz"
    }
    it("creates a table containing given keys", function()
        expect(Test).to.have.a.property("Foo")
        expect(Test).to.have.a.property("Bar")
        expect(Test).to.have.a.property("Baz")
    end)
    describe("the table", function()
        it("has a method :has() that determines if a given value is a member of that enum group", function()
            expect(Test).to.have.a.property("has").that.is.a("function")
            expect(Test:has(Test.Foo)).to.equal(true)
            expect(Test:has("Foo")).to.equal(false)
        end)
    end)
    describe("its values", function()
        it("is equality-comparable", function()
            expect(Test.Foo).to.equal(Test.Foo)
            expect(Test.Foo).to._not_.equal(Test.Bar)
            expect(Test.Foo).to._not_.equal("Foo")
        end)
        it("is ordered", function()
            expect(Test.Foo).to.below(Test.Bar)
            expect(Test.Foo).to.below(Test.Baz)
            expect(Test.Bar).to.above(Test.Foo)
        end)
    end)
end)
