require("lunit")
local Array  = require("collection/array")
local RegExp = require("re")

describe("RegExp", function()
    it("fails to compile syntactically well-formed but semantically invalid regexps", function()
        expect(function() RegExp:new "[b-a]" end).to.throw()
        expect(function() RegExp:new "a{3,2}" end).to.throw()
        expect(function() RegExp:new "(?<foo>)(?<foo>)" end).to.throw()
        expect(function() RegExp:new "(foo)\\2" end).to.throw()
        expect(function() RegExp:new "(?<foo>foo)\\k<bar>" end).to.throw()
    end)
    describe(":exec()", function()
        it("returns nil on a failed match", function()
            expect(RegExp:new "foo":exec "bar").to.be.null()
        end)
        it("returns an array of matched groups with possibly some extra properties", function()
            expect(RegExp:new "(fo+)bar":exec "foobarbaz")
                .to.deep.equal(Array:of("foobar", "foo"))
        end)
        it("may return an array with extra property \"groups\"", function()
            local m = RegExp:new "(?<g1>fo+)bar":exec "foobarbaz"
            expect(m).to.deep.equal(Array:of("foobar", "foo"))
            expect(m).to.have.a.property("groups")
                .which.deep.equals({g1 = "foo"})
        end)
        it("returns an array with extra property \"indices\" when asked", function()
            local m = RegExp:new "(?<g1>fo+)bar":exec("foobarbaz", {indices = true})
            expect(m).to.deep.equal(Array:of("foobar", "foo"))
            expect(m).to.have.a.property("groups")
                .which.deep.equals({g1 = "foo"})
            expect(m).to.have.a.property("indices")
                .which.deep.equals(Array:of({1, 6}, {1, 3}))
            expect(m.indices).to.have.a.property("groups")
                .which.deep.equals {g1 = {1, 3}}
        end)
    end)
    it("can handle Unicode characters", function()
        local m = RegExp:new "さよ+":exec("さよよよち")
        expect(m).to.deep.equal(Array:of("さよよよ"))
    end)
    it("can match literals case-insensitively", function()
        expect "aaa".to.match("^A+$", "i")
    end)
    it("supports backreferences", function()
        expect   "-"  .to.match "^(a*)-\\1"
        expect  "a-a" .to.match "^(a*)-\\1"
        expect "aa-aa".to.match "^(a*)-\\1"
        expect "aa-a" .to._not_.match "^(a*)-\\1"

        -- Named ones are also supported.
        expect "さよちさよち".to.match "(?<foo>さよち)\\k<foo>"
    end)
    it("supports character class escapes", function()
        expect "123".to.match "^\\d+$"
        expect "aaa".to.match "^\\D+$"
        expect "   ".to.match "^\\s+$"
        expect "---".to.match "^\\S+$"
        expect "a12".to.match "^\\w+$"
        expect "***".to.match "^\\W+$"
    end)
    it("supports character classes", function()
        expect "abc".to.match "^[a-c]+$"
        expect "ABC".to.match("^[a-c]+$", "i")
        expect "abc".to.match("^[A-C]+$", "i")
        expect "def".to.match "^[^a-c]+$"
    end)
    it("supports character escapes", function()
        expect "2^3".to.match "^2\\^3$"
    end)
    it("supports disjunctions", function()
        expect "foo".to.match "foo|bar"
        expect "bar".to.match "foo|bar"
        expect "baz".to._not_.match "foo|bar"
    end)
    it("supports input boundary assertions", function()
        expect "abc".to.match "^abc"
        expect "-abc".to._not_.match "^abc"
        expect "\nabc".to._not_.match "^abc"
        expect "\nabc".to.match("^abc", "m")

        expect "abc".to.match "abc$"
        expect "abc-".to._not_.match "abc$"
        expect "abc\n".to._not_.match "abc$"
        expect "abc\n".to.match("abc$", "m")
    end)
    it("supports lookahead assertions", function()
        -- positive
        expect(RegExp:new "^(.*?)(?=Z)":exec "abcZ").to.deep.equal(Array:of("abc", "abc"))

        -- negative
        expect "foo".to      .match "^(?!bar)\\w+"
        expect "bar".to._not_.match "^(?!bar)\\w+"
    end)
    it("supports lookbehind assertions", function()
        -- positive
        expect(RegExp:new "(?<=([ab]+)([bc]+))$":exec "abc").to.deep.equal(Array:of("", "a", "bc"))

        -- negative
        expect "bar"   .to      .match "(?<!foo)bar$"
        expect "foobar".to._not_.match "(?<!foo)bar$"
    end)
    it("supports modifiers, both bounded and unbounded ones", function()
        -- bounded
        expect "abcDEF".to      .match "^(?i:[A-Z]{3})[A-Z]{3}$"
        expect "abcdef".to._not_.match "^(?i:[A-Z]{3})[A-Z]{3}$"

        -- unbounded
        expect "abcDEF".to      .match "^(?i)[A-Z]{3}(?-i)[A-Z]{3}$"
        expect "abcdef".to._not_.match "^(?i)[A-Z]{3}(?-i)[A-Z]{3}$"
    end)
    it("supports non-capturing groups", function()
        expect(RegExp:new "(?:\\d+)":exec "123abc").to.deep.equal(Array:of("123"))
    end)
    it("supports both greedy and non-greedy quantifiers", function()
        -- ? and ??
        expect(RegExp:new "^(\\d?)(\\d+)$" :exec "1234").to.deep.equal(Array:of("1234", "1", "234"))
        expect(RegExp:new "^(\\d??)(\\d+)$":exec "1234").to.deep.equal(Array:of("1234", "", "1234"))

        -- * and **
        expect(RegExp:new "^(\\d*)(\\d*)$" :exec "1234").to.deep.equal(Array:of("1234", "1234", ""))
        expect(RegExp:new "^(\\d*?)(\\d*)$":exec "1234").to.deep.equal(Array:of("1234", "", "1234"))

        -- + and +?
        expect(RegExp:new "^(\\d+)(\\d*)$" :exec "1234").to.deep.equal(Array:of("1234", "1234", ""))
        expect(RegExp:new "^(\\d+?)(\\d*)$":exec "1234").to.deep.equal(Array:of("1234", "1", "234"))

        -- {n} and {n}?
        expect(RegExp:new "^(\\d{2})(\\d*)$" :exec "1234").to.deep.equal(Array:of("1234", "12", "34"))
        expect(RegExp:new "^(\\d{2}?)(\\d*)$":exec "1234").to.deep.equal(Array:of("1234", "12", "34"))

        -- {,m} and {,m}?
        expect(RegExp:new "^(\\d{,3})(\\d*)$" :exec "1234").to.deep.equal(Array:of("1234", "123", "4"))
        expect(RegExp:new "^(\\d{,3}?)(\\d*)$":exec "1234").to.deep.equal(Array:of("1234", "", "1234"))

        -- {n,} and {n,}?
        expect(RegExp:new "^(\\d{3,})(\\d*)$" :exec "1234").to.deep.equal(Array:of("1234", "1234", ""))
        expect(RegExp:new "^(\\d{3,}?)(\\d*)$":exec "1234").to.deep.equal(Array:of("1234", "123", "4"))

        -- {n,m} and {n,m}?
        expect(RegExp:new "^(\\d{2,3})(\\d*)$" :exec "1234").to.deep.equal(Array:of("1234", "123", "4"))
        expect(RegExp:new "^(\\d{2,3}?)(\\d*)$":exec "1234").to.deep.equal(Array:of("1234", "12", "34"))
    end)
    it("supports wildcards", function()
        expect(RegExp:new "^.+"      :exec "abc\ndef").to.deep.equal(Array:of("abc"))
        expect(RegExp:new("^.+", "s"):exec "abc\ndef").to.deep.equal(Array:of("abc\ndef"))
    end)
end)

-- FIXME: delete this later
--local console = require("console")
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
--console:log("exec", RegExp:new "^さよ":exec("さよち"))
--RegExp:new "さよち?":dump()
--RegExp:new "さよち*":dump()
--RegExp:new "さよち{2,}":dump()
--RegExp:new "さよち{3}":dump()
--RegExp:new "さよち{2,4}":dump()
--RegExp:new "(さよ)\\1":dump()
--console:log("res:", RegExp:new "さよち{2,4}":exec("さよちち"))
--console:log("res:", RegExp:new "^(さよ)ち":exec("さよちち"))
--console:log("res:", RegExp:new "(?<ch>さよ+)ち":exec("おさよよち", {indices=true}).indices.groups)
--console:log("res:", RegExp:new "(さよ)\\1":exec("さよさよち"))
--error("ABORT NOW")
