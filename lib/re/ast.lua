-- luacheck: read_globals utf8
require("shim/utf8")
local Array    = require("collection/array")
local Map      = require("collection/map")
local Set      = require("collection/set")
local class    = require("class")
local enum     = require("enum")
local readonly = require("readonly")

-- The maximum repetitions in {m,n} quantifiers.
local MAX_REPETITIONS = 256

local ast = {}

-- The root class for all AST nodes.
ast.Node = class("Node")
function ast.Node:optimise()
    -- Do nothing by default.
end
function ast.Node:validate(_ctx)
    -- Do nothing by default.
end
function ast.Node:validateBackrefs(_ctx)
    -- Do nothing by default.
end

-- '^'
local Caret = class("Caret", ast.Node)
function Caret:__tostring()
    return "Caret"
end
ast.Caret = Caret:new()

-- '$'
local Dollar = class("Dollar", ast.Node)
function Dollar:__tostring()
    return "Dollar"
end
ast.Dollar = Dollar:new()

-- Wildcard '.'
local Wildcard = class("Wildcard", ast.Node)
function Wildcard:__tostring()
    return "Wild"
end
ast.Wildcard = Wildcard:new()

-- Positive and negative lookahead
ast.Lookaround = class("Lookaround", ast.Node)
function ast.Lookaround:__init(positive, ahead, group)
    self.positive = positive -- boolean
    self.ahead    = ahead    -- boolean
    self.group    = group    -- Group
end
function ast.Lookaround:__tostring()
    return table.concat {
        (self.positive and "=") or "!",
        (self.ahead and "La ") or "Lb ",
        tostring(self.group)
    }
end
function ast.Lookaround:optimise()
    self.group:optimise()
end
function ast.Lookaround:validate(ctx)
    self.group:validate(ctx)
end
function ast.Lookaround:validateBackrefs(ctx)
    self.group:validateBackrefs(ctx)
end

-- Word boundary assertion
ast.WordBoundary = class("WordBoundary", ast.Node)
function ast.WordBoundary:__init(positive)
    self.positive = positive -- boolean
end
function ast.WordBoundary:__tostring()
    if self.positive then
        return "=Word"
    else
        return "!Word"
    end
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
function ast.modsToSet(mods)
    local ret = Set:new()
    for i = 1, #mods do
        local code = string.byte(mods, i)
        local mod  = MOD_ENUM_OF[code]
        if mod then
            ret:add(mod)
        else
            error("Unknown modifier: "..string.char(code), 2)
        end
    end
    return ret
end
function ast.modsFromSet(set)
    local ret = Array:new()
    for mod in set:values() do
        ret:push(string.char(MOD_CHAR_OF[mod]))
    end
    return ret:join("")
end
ast.Mods = class("Mods", ast.Node)
function ast.Mods:__init(enabled, disabled)
    self.enabled  = ast.modsToSet(enabled ) -- Set of ast.Modifier
    self.disabled = ast.modsToSet(disabled)
end
function ast.Mods:__tostring()
    if self.isEmpty then
        return "Mods"
    end
    local ret = Array:of(
        "Mods (",
        ast.modsFromSet(self.enabled)
    )
    if self.disabled.size > 0 then
        ret:push("-", ast.modsFromSet(self.disabled))
    end
    return ret:push(")"):join("")
end
function ast.Mods.__getter:isEmpty()
    return self.enabled.size == 0 and self.disabled.size == 0
end

-- non-empty literal sequence of codepoints
ast.Literal = class("Literal", ast.Node)
function ast.Literal:__init(str)
    self.str = str
end
function ast.Literal:__tostring()
    return string.format("Lit %q", self.str)
end

ast.Alternative = class("Alternative", ast.Node)
function ast.Alternative:__init(nodes)
    self.nodes = nodes -- Array of nodes
end
function ast.Alternative:__tostring()
    return self.nodes:join(", ")
end
function ast.Alternative:optimise()
    -- Merge two consecutive literals. This is very important. Our parser
    -- tries its best to avoid creating unnecessarily many literals, but
    -- it's not perfect. /foo\[bar\]/ should really be represented as Lit
    -- "foo[bar]", not {Lit "foo", Lit "\\[", Lit "bar", Lit "\\]"}.
    local lastNodeIsLiteral = false
    local tmp = Array:new()
    for node in self.nodes:values() do
        node:optimise()
        if ast.Literal:made(node) then
            if lastNodeIsLiteral then
                local last = tmp:at(-1)
                last.str = last.str .. node.str
            else
                tmp:push(node)
                lastNodeIsLiteral = true
            end
        else
            tmp:push(node)
            lastNodeIsLiteral = false
        end
    end
    self.nodes = tmp
end
function ast.Alternative:validate(ctx)
    for node in self.nodes:values() do
        node:validate(ctx)
    end
end
function ast.Alternative:validateBackrefs(ctx)
    for node in self.nodes:values() do
        node:validateBackrefs(ctx)
    end
end

-- Abstract group
ast.Group = class("Group", ast.Node)
function ast.Group:__init(alts)
    self.alts = alts -- Array of ast.Alternative
end
function ast.Group:optimise()
    for alt in self.alts:values() do
        alt:optimise()
    end
end
function ast.Group:validate(ctx)
    for alt in self.alts:values() do
        alt:validate(ctx)
    end
end
function ast.Group:validateBackrefs(ctx)
    for alt in self.alts:values() do
        alt:validateBackrefs(ctx)
    end
end

-- Capturing group: (...) or (?<name>...)
ast.CapturingGroup = class("CapturingGroup", ast.Group)
function ast.CapturingGroup:__init(alts, name)
    super(alts)
    self.index = nil  -- integer >= 1, filled by :validate()
    self.name  = name -- string or nil
end
function ast.CapturingGroup:__tostring()
    local ret = Array:of("CapGrp ")
    if self.index then
        ret:push(tostring(self.index), " ")
    end
    if self.name then
        ret:push("<", self.name, "> ")
    end
    ret:push("(", self.alts:join(" | "), ")")
    return ret:join("")
end
function ast.CapturingGroup:validate(ctx)
    ctx.numCapGroups = ctx.numCapGroups + 1
    self.index = ctx.numCapGroups

    if self.name then
        if ctx.namedCapGroups:has(self.name) then
            error("Capturing groups have duplicate names: " .. self.name, 0)
        end
        ctx.namedCapGroups:set(self.name, self.index)
    end

    super:validate(ctx)
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
    local ret = {"NonCapGrp "}
    if self.mods then
        table.insert(ret, tostring(self.mods))
        table.insert(ret, " ")
    end
    table.insert(ret, "(")
    table.insert(ret, self.alts:join(" | "))
    table.insert(ret, ")")
    return table.concat(ret)
end

-- Quantified atom such as "a*"
ast.Quantified = class("Quantified", ast.Node)
function ast.Quantified:__init(atom, min, max, greedy)
    self.atom   = atom   -- Node (but only atoms)
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
function ast.Quantified:optimise()
    self.atom:optimise()
end
function ast.Quantified:validate(ctx)
    if self.max < math.huge and self.max > MAX_REPETITIONS then
        error("Too many repetitions in a {m,n} quantifier: cannot be more than " ..
              tostring(MAX_REPETITIONS), 0)
    end
    self.atom:validate(ctx)
end
function ast.Quantified:validateBackrefs(ctx)
    self.atom:validateBackrefs(ctx)
end

-- Backreference
ast.Backreference = class("Backreference", ast.Node)
function ast.Backreference:__init(ref)
    self.ref = ref -- integer (>= 1) or string
end
function ast.Backreference:__tostring()
    local ret = Array:of("Backref ")
    if type(self.ref) == "number" then
        ret:push(tostring(self.ref))
    else
        ret:push("<", self.ref, ">")
    end
    return ret:join("")
end
function ast.Backreference:validateBackrefs(ctx)
    if type(self.ref) == "number" then
        if self.ref > ctx.numCapGroups then
            error(string.format("Reference to a nonexistent group %d", self.ref), 0)
        end
    else
        if not ctx.namedCapGroups:has(self.ref) then
            error(string.format("Reference to a nonexistent group <%s>", self.ref), 0)
        end
    end
end

-- Character class
ast.Class = class("Class", ast.Node)
function ast.Class:__init(negated, elems)
    self.negated = negated -- boolean
    self.elems   = elems   -- Set whose elements are codepoint integers,
                           -- pairs of {code, code} representing ranges, or
                           -- other Class objects.
end
function ast.Class:__tostring()
    local ret = Array:of("Class [")
    if self.negated then
        ret:push("^")
    end
    for elem in self.elems:values() do
        if ast.Class:made(elem) then
            ret:push("<", tostring(elem), ">")
        elseif type(elem) == "number" then
            if elem == 0x002D then -- '-'
                ret:push("\\")
            end
            ret:push(utf8.char(elem))
        else
            ret:push(utf8.char(elem[1]), "-", utf8.char(elem[2]))
        end
    end
    ret:push("]")
    return ret:join("")
end
function ast.Class:caseIgnored()
    local tmp = Set:new()
    for elem in self.elems:values() do
        if ast.Class:made(elem) then
            tmp:add(elem:caseIgnored())
        elseif type(elem) == "number" then
            -- Wrong, but...
            tmp:add(utf8.codepoint(string.lower(utf8.char(elem))))
        else
            local lower    = string.lower(utf8.char(elem[1], elem[2]))
            local min, max = utf8.codepoint(lower, 1, #lower)
            tmp:add {min, max}
        end
    end
    return ast.Class:new(self.negated, tmp)
end
function ast.Class:contains(code)
    for elem in self.elems:values() do
        if ast.Class:made(elem) then
            if elem:contains(code) then
                return not self.negated
            end
        elseif type(elem) == "number" then
            if code == elem then
                return not self.negated
            end
        else
            if elem[1] <= code and code <= elem[2] then
                return not self.negated
            end
        end
    end
    return self.negated
end
function ast.Class:validate(ctx)
    for elem in self.elems:values() do
        if ast.Class:made(elem) then
            elem:validate(ctx)
        elseif type(elem) == "number" then
            -- Always valid
        else
            if elem[1] >= elem[2] then
                error(string.format("Invalid range in a character class: %s-%s",
                                    utf8.char(elem[1]), utf8.char(elem[2])), 0)
            end
        end
    end
end

-- Regular expression
ast.RegExp = class("RegExp")
function ast.RegExp:__init(node)
    self.root           = node
    self.numCapGroups   = nil -- non-negative integer
    self.namedCapGroups = nil -- Map from string to index
end
function ast.RegExp:__tostring()
    return tostring(self.root)
end
function ast.RegExp:optimise()
    self.root:optimise()
end
function ast.RegExp:validate()
    local ctx = {
        numCapGroups   = 0,
        namedCapGroups = Map:new(),
    }
    do
        local ok, err = pcall(self.root.validate, self.root, ctx)
        if not ok then
            -- ast.Node#validate() is expected to raise errors with no
            -- stacktrace.
            error(err, 2)
        end
    end
    do
        -- This can only be done after :validate() is complete, because we
        -- don't know what capturing groups we have.
        local ok, err = pcall(self.root.validateBackrefs, self.root, ctx)
        if not ok then
            error(err, 2)
        end
    end
    self.numCapGroups   = ctx.numCapGroups
    self.namedCapGroups = ctx.namedCapGroups
end

return readonly(ast)
