-- luacheck: read_globals utf8
require("shim/utf8")
local Set      = require("collection/set")
local class    = require("class")
local enum     = require("enum")
local readonly = require("readonly")

local ast = {}

-- '^'
local Caret = class("Caret")
function Caret:__tostring()
    return "Caret"
end
ast.Caret = Caret:new()

-- '$'
local Dollar = class("Dollar")
function Dollar:__tostring()
    return "Dollar"
end
ast.Dollar = Dollar:new()

-- Positive and negative lookahead
ast.Lookaround = class("Lookaround")
function ast.Lookaround:__init(positive, ahead, group)
    self.positive = positive -- boolean
    self.ahead    = ahead    -- boolean
    self.group    = group    -- Group
end
function ast.Lookaround:__tostring()
    return table.concat {
        "La (",
        (self.positive and "positive") or "negative",
        ", ",
        (self.ahead and "ahead") or "behind",
        ") ",
        tostring(self.group)
    }
end

-- Modifier
ast.Modifier = enum {
    "IgnoreCase",
    "Multiline",
    "DotAll",
}
local MOD_ENUM_OF = {
    [0x0069] = ast.Modifier.IgnoreCase,
    [0x006D] = ast.Modifier.Multiline,
    [0x0073] = ast.Modifier.DotAll,
}
local MOD_CHAR_OF = {}
do
    for code, mod in pairs(MOD_ENUM_OF) do
        MOD_CHAR_OF[mod] = code
    end
end
local function modsToSet(mods)
    local ret = Set:new()
    for i = 1, #mods do
        ret:add(MOD_ENUM_OF[string.byte(mods, i)])
    end
    return ret
end
ast.Mods = class("Mods")
function ast.Mods:__init(enabled, disabled)
    self.enabled  = modsToSet(enabled )
    self.disabled = modsToSet(disabled)
end
function ast.Mods:__tostring()
    if self.isEmpty then
        return "Mods"
    end
    local ret = {"Mods "}
    for mod in self.enabled:values() do
        table.insert(ret, string.char(MOD_CHAR_OF[mod]))
    end
    if self.disabled.size > 0 then
        table.insert(ret, "-")
        for mod in self.disabled:values() do
            table.insert(ret, string.char(MOD_CHAR_OF[mod]))
        end
    end
    return table.concat(ret)
end
function ast.Mods.__getter:isEmpty()
    return self.enabled.size == 0 and self.disabled.size == 0
end

-- non-empty literal sequence of codepoints
ast.Literal = class("Literal")
function ast.Literal:__init(str)
    self.str = str
end
function ast.Literal:__tostring()
    return string.format("Lit %q", self.str)
end

ast.Alternative = class("Alternative")
function ast.Alternative:__init(nodes)
    self.nodes = nodes
end
function ast.Alternative:__tostring()
    local nodes = {}
    for _i, node in ipairs(self.nodes) do
        table.insert(nodes, tostring(node))
    end
    return table.concat(nodes, ", ")
end

-- Abstract group
ast.Group = class("Group")
function ast.Group:__init(alts)
    self.alts = alts -- {ast.Alternative, ...}
end

-- Capturing group: (...) or (?<name>...)
ast.CapturingGroup = class("CapturingGroup", ast.Group)
function ast.CapturingGroup:__init(alts, name)
    super(alts)
    self.name = name -- string or nil
end
function ast.CapturingGroup:__tostring()
    local alts = {}
    for _i, alt in ipairs(self.alts) do
        table.insert(alts, tostring(alt))
    end

    local ret = {"CapGrp "}
    if self.name then
        table.insert(ret, "<")
        table.insert(ret, self.name)
        table.insert(ret, "> ")
    end
    table.insert(ret, "(")
    table.insert(ret, table.concat(alts, " | "))
    table.insert(ret, ")")
    return table.concat(ret)
end

-- Non-capturing group: (?:...) or (?ims-ims:...)
ast.NonCapturingGroup = class("NonCapturingGroup", ast.Group)
function ast.NonCapturingGroup:__init(alts, mods)
    super(alts)
    if mods and not mods.isEmpty then
        self.mods = mods -- ast.Mods or nil
    end
end
function ast.NonCapturingGroup:__tostring()
    local alts = {}
    for _i, alt in ipairs(self.alts) do
        table.insert(alts, tostring(alt))
    end

    local ret = {"NonCapGrp "}
    if self.mods then
        table.insert(ret, tostring(self.mods))
        table.insert(ret, " ")
    end
    table.insert(ret, "(")
    table.insert(ret, table.concat(alts, " | "))
    table.insert(ret, ")")
    return table.concat(ret)
end

-- Quantified atom such as "a*"
ast.Quantified = class("Quantified")
function ast.Quantified:__init(atom, min, max, greedy)
    self.atom   = atom
    self.min    = min    -- >= 0
    self.max    = max    -- >= 0, can be inf
    self.greedy = greedy
end
function ast.Quantified:__tostring()
    local ret = {tostring(self.atom)}

    if self.min == 0 and self.max == 1 then
        table.insert(ret, "?")
    elseif self.min == 0 and self.max == math.huge then
        table.insert(ret, "*")
    elseif self.min == 1 and self.max == math.huge then
        table.insert(ret, "+")
    else
        table.insert(ret, "{")
        if self.min == self.max then
            table.insert(ret, tostring(self.min))
        else
            if self.min > 0 then
                table.insert(ret, tostring(self.min))
            end
            table.insert(ret, ",")
            if self.max < math.huge then
                table.insert(ret, tostring(self.max))
            end
        end
        table.insert(ret, "}")
    end

    if not self.greedy then
        table.insert(ret, "?")
    end

    return table.concat(ret)
end

-- Backreference
ast.Backreference = class("Backreference")
function ast.Backreference:__init(ref)
    self.ref = ref -- integer (>= 1) or string
end
function ast.Backreference:__tostring()
    local ret = {"Backref "}
    if type(self.ref) == "number" then
        table.insert(ret, tostring(self.ref))
    else
        table.insert(ret, "<")
        table.insert(ret, self.ref)
        table.insert(ret, ">")
    end
    return table.concat(ret)
end

-- Character class
ast.Class = class("Class")
function ast.Class:__init(negated, elems)
    self.negated = negated -- boolean
    self.elems   = elems   -- Sequence whose elements are codepoint
                           -- integers, pairs of {code, code} representing
                           -- ranges, or other classes.
end
function ast.Class:__tostring()
    local ret = {"Class ["}
    if self.negated then
        table.insert(ret, "^")
    end
    for _i, elem in ipairs(self.elems) do
        if ast.Class:made(elem) then
            table.insert(ret, "<")
            table.insert(ret, tostring(elem))
            table.insert(ret, ">")
        elseif type(elem) == "number" then
            if elem == 0x002D then -- '-'
                table.insert(ret, "\\")
            end
            table.insert(ret, utf8.char(elem))
        else
            table.insert(ret, utf8.char(elem[1]))
            table.insert(ret, "-")
            table.insert(ret, utf8.char(elem[2]))
        end
    end
    table.insert(ret, "]")
    return table.concat(ret)
end

return readonly(ast)
