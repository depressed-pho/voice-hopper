require("lunit")
local path = require("path")

describe("path", function()
    describe(".sep", function()
        it("is a platform-dependent path separator", function()
            expect(path.posix  .sep).to.equal("/")
            expect(path.windows.sep).to.equal("\\")

            expect(path.sep).to.match("[/\\]")
        end)
    end)
    describe(".join()", function()
        it("joins all given path segments together", function()
            expect(path.posix  .join("foo", "bar", "baz")).to.equal("foo/bar/baz")
            expect(path.windows.join("foo", "bar", "baz")).to.equal("foo\\bar\\baz")

            expect(path.join("foo", "bar", "baz")).to.be.oneOf(
                {"foo/bar/baz", "foo\\bar\\baz"})
        end)
    end)
    -- path.resolve() is unfortunately not testable.
end)
