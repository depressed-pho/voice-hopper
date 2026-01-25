-- luacheck: read_globals utf8
require("shim/utf8")
local class    = require("class")
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
    return table.concat {
        "{",
        table.concat(nodes, ", "),
        "}"
    }
end

-- (...)
ast.Group = class("Group")
function ast.Group:__init(alts, capturing)
    self.alts      = alts      -- {Alternative, ...}
    self.capturing = capturing -- boolean
end
function ast.Group:__tostring()
    local alts = {}
    for _i, alt in ipairs(self.alts) do
        table.insert(alts, tostring(alt))
    end
    return table.concat {
        "Grp (",
        (self.capturing and "capturing") or "non-capturing",
        ") {",
        table.concat(alts, " | "),
        "}"
    }
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
function ast.Backreference:__init(index)
    self.index = index -- >= 1
end
function ast.Backreference:__tostring()
    return string.format("Backref %d", self.index)
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
