require("lunit")
local RegExp = require("re")

describe("RegExp", function()
    it("fails to compile syntactically well-formed but semantically invalid regexps", function()
        expect(function() RegExp:new "[b-a]" end).to.throw()
        expect(function() RegExp:new "(?<foo>)(?<foo>)" end).to.throw()
        expect(function() RegExp:new "(foo)\\2" end).to.throw()
        expect(function() RegExp:new "(?<foo>foo)\\k<bar>" end).to.throw()
    end)
end)

-- FIXME: delete this later
local console = require("console")
--[[
console:log("%O", parse "^さよち{2,12}$")
console:log("%O", parse "^さよち\\12a$")
console:log("%O", parse "^(さよ|ち)$")
console:log("%O", parse "^さ[よち]$")
console:log("%O", parse "^さ(?i)よち$")
console:log("%O", parse "^さ(?<よ>.ち)$")
console:log("%O", parse "\\bさ(?<よ>.ち)\\B")
console:log("%O", parse "(?=さよ\\[ち])")
console:log(compile "^さよち$")
console:log(compile "さよ|ち")
]]
console:log("exec", RegExp:new "^さよ":exec("さよち"))
--RegExp:new "さよち*":dump()
error("ABORT NOW")
