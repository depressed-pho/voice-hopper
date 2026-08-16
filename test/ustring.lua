require("lunit")
local String = require("ustring")

describe("String", function()
    describe("tostring()", function()
        it("unwraps the string", function()
            expect(tostring(String:new "a🐈c")).to.equal "a🐈c"
        end)
    end)
    describe("..", function()
        it("concatenates two strings", function()
            expect(tostring(String:new("a") .. "🐈c")).to.equal "a🐈c"
            expect(tostring("a" .. String:new("🐈c"))).to.equal "a🐈c"
            expect(tostring(String:new("a") .. String:new("🐈c"))).to.equal "a🐈c"
        end)
    end)
    describe(".length", function()
        it("is the number of codepoints in the string", function()
            expect(String:new("a🐈c").length).to.equal(3)
        end)
    end)
    describe(":slice()", function()
        it("extracts a substring in terms of codepoints", function()
            expect(tostring(String:new("a🐈c"):slice(2))).to.equal "🐈c"
            expect(tostring(String:new("a🐈c"):slice(2, 3))).to.equal "🐈c"
            expect(tostring(String:new("a🐈c"):slice(1, 2))).to.equal "a🐈"
        end)
    end)
end)
