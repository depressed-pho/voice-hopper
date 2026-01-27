require("lunit")
--local re = require("re")

-- FIXME: delete this later
local P = require("parser")
local Set = require("collection/set")
local console = require("console")
local pRegex = require("re/parser")
local function parse(str)
    local ast = P.parse(P.finishOff(pRegex), str)
    ast:optimise()
    return ast
end
--[[
console:log("%O", parse "^さよち{2,12}$")
console:log("%O", parse "^さよち\\12a$")
console:log("%O", parse "^(さよ|ち)$")
console:log("%O", parse "^さ[よち]$")
console:log("%O", parse "^さ(?i)よち$")
console:log("%O", parse "^さ(?<よ>.ち)$")
console:log("%O", parse "\\bさ(?<よ>.ち)\\B")
console:log("%O", parse "(?=さよ\\[ち])")
--]]
local NFA = require("re/nfa")
local function compile(str)
    local flags = Set:new()
    local nfa   =  NFA:new(flags, parse(str))
    nfa:optimise()
    return nfa
end
console:log(compile "^さよち$")
console:log(compile "さよ|ち")
--error("ABORT NOW")
