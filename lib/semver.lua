local Array    = require("collection/array")
local P        = require("parser")
local class    = require("class")
local readonly = require("readonly")

local CODE_ZERO   = string.byte("0")
local CODE_PERIOD = string.byte(".")
local CODE_HYPHEN = string.byte("-")
local CODE_PLUS   = string.byte("+")

local SemVer = class("SemVer")

local numericIdentifier =
    P.map(P.const(0), P.char(CODE_ZERO)   ) +
    P.map(tonumber  , P.pat("[1-9][0-9]*"))

local alphaNumericIdentifier =
    P.pat("[0-9a-zA-Z%-]+")

local versionCore =
    P.map(
        function(major, _, minor, _, patch)
            return {
                major = major,
                minor = minor,
                patch = patch
            }
        end,
        numericIdentifier,
        P.char(CODE_PERIOD),
        numericIdentifier,
        P.char(CODE_PERIOD),
        numericIdentifier)

local preReleaseIdentifier =
    numericIdentifier      +
    alphaNumericIdentifier

local preRelease =
    P.map(
        function(fst, rest)
            rest:unshift(fst)
            return rest
        end,
        preReleaseIdentifier,
        P.many(P.char(CODE_PERIOD) * preReleaseIdentifier))

local buildMeta =
    P.map(
        function(fst, rest)
            rest:unshift(fst)
            return rest
        end,
        alphaNumericIdentifier,
        P.many(P.char(CODE_PERIOD) * alphaNumericIdentifier))

local semver =
    P.map(
        function(core, pre, build)
            return {
                core  = core,
                pre   = pre,
                build = build
            }
        end,
        versionCore,
        P.option(Array:new(), P.char(CODE_HYPHEN) * preRelease),
        P.option(Array:new(), P.char(CODE_PLUS  ) * buildMeta ))

function SemVer:__init(str)
    assert(type(str) == "string", "SemVer:new() expects a string")

    local ret = P.parse(P.finishOff(semver), str)
    self._major = ret.core.major -- integer
    self._minor = ret.core.minor -- integer
    self._patch = ret.core.patch -- integer
    self._pre   = ret.pre        -- Array {id, ...}
    self._build = ret.build      -- Array {id, ...}
end

function SemVer:__tostring()
    local ret = {
        tostring(self._major), ".",
        tostring(self._minor), ".",
        tostring(self._patch)
    }
    if self._pre.length > 0 then
        local pre = {}
        for id in self._pre:values() do
            table.insert(pre, tostring(id))
        end
        table.insert(ret, "-")
        table.insert(ret, table.concat(pre, "."))
    end
    if self._build.length > 0 then
        local build = {}
        for id in self._build:values() do
            table.insert(build, tostring(id))
        end
        table.insert(ret, "+")
        table.insert(ret, table.concat(build, "."))
    end
    return table.concat(ret)
end

local function compare(v1, v2)
    assert(
        SemVer:made(v1) and SemVer:made(v2),
        string.format(
            "SemVer can only be compared against SemVer: %s, %s", v1, v2))
    if v1._major ~= v2._major then
        return v1._major - v2._major
    elseif v1._minor ~= v2._minor then
        return v1._minor - v2._minor
    elseif v1._patch ~= v2._patch then
        return v1._patch - v2._patch
    else
        -- Versions without pre-release are lower than those without. This
        -- is branchy but I can't think of better ways.
        local v1pre = v1._pre.length
        local v2pre = v2._pre.length
        if v1pre == 0 and v2pre > 0 then
            return 1
        elseif v1pre > 0 and v2pre == 0 then
            return -1
        else
            for i = 1, math.max(v1pre, v2pre) do
                if v1._pre[i] == nil then
                    return 1
                elseif v2._pre[i] == nil then
                    return -1
                else
                    local v1type = type(v1._pre[i])
                    local v2type = type(v2._pre[i])
                    if v1type == "number" and v2type == "string" then
                        return 1
                    elseif v1type == "string" and v2type == "number" then
                        return -1
                    elseif v1._pre[i] ~= v2._pre[i] then
                        return (v1._pre[i] < v2._pre[i] and -1) or 1
                    end
                end
            end
            return 0
        end
    end
end
function SemVer.__eq(v1, v2)
    return compare(v1, v2) == 0
end
function SemVer.__lt(v1, v2)
    return compare(v1, v2) < 0
end
function SemVer.__le(v1, v2)
    return compare(v1, v2) <= 0
end

function SemVer.__getter:major()
    return self._major
end

function SemVer.__getter:minor()
    return self._minor
end

function SemVer.__getter:patch()
    return self._patch
end

function SemVer.__getter:preRelease()
    return readonly(self._pre:clone())
end

function SemVer.__getter:build()
    return readonly(self._build:clone())
end

-- There are no ranged comparisons because, heck, Semantic Versioning 2.0
-- (https://semver.org/) does not define version ranges and everyone uses
-- their own definition of ranges, which are incompatible with each
-- other. The exact meaning of "^1.2.0" varies from implementation to
-- implementation. We want to stay away from the party.

return SemVer
