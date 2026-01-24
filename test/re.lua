require("lunit")
--local re = require("re")

-- FIXME: delete this later
local P = require("parser")
local console = require("console")
local pRegex = require("re/parser")
console:log("%O", P.parse(P.tillEnd(pRegex), "^さよち{2,12}$"))
console:log("%O", P.parse(P.tillEnd(pRegex), "^さよち\\12a$"))
--error("ABORT NOW")
