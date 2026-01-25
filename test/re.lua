require("lunit")
--local re = require("re")

-- FIXME: delete this later
local P = require("parser")
local console = require("console")
local pRegex = require("re/parser")
console:log("%O", P.parse(P.finishOff(pRegex), "^さよち{2,12}$"))
console:log("%O", P.parse(P.finishOff(pRegex), "^さよち\\12a$"))
console:log("%O", P.parse(P.finishOff(pRegex), "^(さよ|ち)$"))
console:log("%O", P.parse(P.finishOff(pRegex), "^さ[よち]$"))
--error("ABORT NOW")
