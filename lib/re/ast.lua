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
function ast.Quantified:__init(atom, greedy)
    self.atom   = atom
    self.greedy = greedy
end

-- Atom quantified with * or *?
ast.ZeroPlus = class("ZeroPlus", ast.Quantified)
function ast.ZeroPlus:__tostring()
    return tostring(self.atom) .. ((self.greedy and "*?") or "*")
end

return readonly(ast)
