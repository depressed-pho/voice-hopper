local Array = require("collection/array")
local Map   = require("collection/map")
local Set   = require("collection/set")
local ast   = require("re/ast")
local class = require("class")
local m     = require("re/matcher")

--
-- A transition of states.
--
local Transition = class("Transition")

function Transition:__init(to)
    self.to = to -- State
end

--
-- Epsilon transition: unconditional, never consumes any input.
--
local Epsilon = class("Epsilon", Transition)

--
-- Grouping transition: like epsilon but cannot be eliminated.
--
local Grouping = class("Grouping", Transition)

function Grouping:__init(to, isOpen, index, name)
    super(to)
    self.isOpen = isOpen -- boolean
    self.index  = index  -- positive integer
    self.name   = name   -- string or nil
end

--
-- Matching transition: conditional, may consume some input.
--
local Matching = class("Matching", Transition)

function Matching:__init(to, matcher)
    super(to)
    self.matcher = matcher
end

--
-- A state of an NFA.
--
local State = class("State")

function State:__init()
    self.trs = Array:new() -- an array of transitions, not a set, because
                           -- the order matters for left-biased regexp
                           -- engines.
end

function State:addEpsilon(to)
    self.trs:push(Epsilon:new(to))
end

function State:addGrouping(to, isOpen, index, name)
    self.trs:push(Grouping:new(to, isOpen, index, name))
end

function State:addMatching(to, matcher)
    self.trs:push(Matching:new(to, matcher))
end

-- Return true iff this state has a direct ε-transition to the given state.
function State:hasEpsilonTo(to)
    for tr in self.trs:values() do
        if Epsilon:made(tr) and tr.to == to then
            return true
        end
    end
    return false
end

--
-- A composable NFA. By composable it means it has exactly one initial
-- state and exactly one final state.
--
local NFA = class("NFA")

NFA.Transition = Transition
NFA.Epsilon    = Epsilon
NFA.State      = State

function NFA:__init(flags, node)
    self._ini = nil -- State
    self._fin = nil -- State
    self:clear()

    if not node then
        -- Do nothing; just construct an empty NFA.

    elseif ast.Caret:made(node) then
        -- ini -[^]-> fin
        self._fin = State:new()
        self._ini:addMatching(
            self._fin,
            m.CaretMatcher:new(flags:has(ast.Modifier.Multiline)))

    elseif ast.Dollar:made(node) then
        -- ini -[$]-> fin
        self._fin = State:new()
        self._ini:addMatching(
            self._fin,
            m.DollarMatcher:new(flags:has(ast.Modifier.Multiline)))

    elseif ast.Literal:made(node) then
        -- ini -[lit]-> fin
        self._fin = State:new()
        self._ini:addMatching(
            self._fin,
            m.LiteralMatcher:new(node.str, flags:has(ast.Modifier.IgnoreCase)))

    elseif ast.Alternative:made(node) then
        -- ini -> node1 + node2 + ... -> fin
        --   where a+b is an NFA concatenation.
        for altNode in node.nodes:values() do
            self:append(NFA:new(flags, altNode))
        end

    elseif ast.CapturingGroup:made(node) then
        --             /-> alt1 -.
        -- ini -[open]-+-> alt2 -+-[close]-> fin
        --             `-> ...  -/
        if not node.index then
            error(string.format("This capturing group has no index assigned. " ..
                                "You haven't validated the AST, have you?: %s", node), 2)
        end
        if node.alts.length > 0 then
            self._fin = State:new()
            for alt in node.alts:values() do
                local ini, fin = self:subsume(NFA:new(flags, alt))
                self._ini:addGrouping(ini, true, node.index, node.name)
                fin:addGrouping(self._fin, false, node.index, node.name)
            end
        end

    elseif ast.NonCapturingGroup:made(node) then
        --      /-> alt1 -.
        -- ini -+-> alt2 -+-> fin
        --      `-> ...  -/
        if node.mods then
            -- The group itself locally modifies the flags.
            flags = (flags .. node.modes.enabled) - node.modes.disabled
        else
            -- Any changes to flags are restored upon exiting this group.
            flags = flags:clone()
        end
        if node.alts.length > 0 then
            self._fin = State:new()
            for alt in node.alts:values() do
                local ini, fin = self:subsume(NFA:new(flags, alt))
                self._ini:addEpsilon(ini)
                fin:addEpsilon(self._fin)
            end
        end

    elseif ast.Backreference:made(node) then
        -- ini -[ref]-> fin
        self._fin = State:new()
        self._ini:addMatching(
            self._fin,
            m.BackrefMatcher:new(node.ref))

    elseif ast.Class:made(node) then
        -- ini -[class]-> fin
        self._fin = State:new()
        self._ini:addMatching(
            self._fin,
            m.ClassMatcher:new(node, flags:has(ast.Modifier.IgnoreCase)))

    else
        error("Don't know how to construct an NFA out of "..tostring(node), 2)
    end
end

function NFA:__tostring()
    local ret = Array:of("NFA {\n")

    if self.isEmpty then
        -- Special case for empty NFA.
        ret:push("  ini = fin\n")
    else
        local seen = Map:new {
            [self._ini] = "ini",
            [self._fin] = "fin"
        }
        local function nameOf(s)
            local name = seen:get(s)
            if not name then
                name = "q" .. tostring(seen.size)
            end
            seen:set(s, name)
            return name
        end
        local function showTransitions(s)
            local from = nameOf(s)
            for tr in s.trs:values() do
                ret:push("  ", from, " -> ", nameOf(tr.to))
                if Epsilon:made(tr) then
                    -- Do nothing
                elseif Grouping:made(tr) then
                    ret:push(" [")
                    if tr.isOpen then
                        ret:push("open ")
                    else
                        ret:push("close ")
                    end
                    ret:push(tostring(tr.index))
                    if tr.name then
                        ret:push(" <", tr.name, ">")
                    end
                    ret:push("]")
                elseif Matching:made(tr) then
                    ret:push(" [", tostring(tr.matcher), "]")
                else
                    error("Unknown transition type: "..tostring(tr), 2)
                end
                ret:push("\n")
                showTransitions(tr.to)
            end
        end
        showTransitions(self._ini)
    end

    ret:push("}")
    return ret:join("")
end

function NFA.__getter:isEmpty()
    return self._ini == self._fin
end

function NFA:clear()
    self._ini = State:new()
    self._fin = self._ini
end

function NFA:append(other)
    if self.isEmpty then
        -- Special case for self being empty: overwrite self with other.
        self._ini = other._ini
        self._fin = other._fin

        -- other should now be empty.
        other:clear()

    elseif other.isEmpty then
        -- Special case for other being empty: do nothing.

    else
        -- Concatenate with ε.
        self._fin:addEpsilon(other._ini)
        self._fin = other._fin

        -- other should now be empty.
        other:clear()
    end
end

function NFA:subsume(other)
    if self.isEmpty then
        -- Special case for self being empty: overwrite self with other.
        self._ini = other._ini
        self._fin = other._fin

        -- other should now be empty.
        other:clear()

        return self._ini, self._fin

    else
        local ini, fin = other._ini, other._fin

        -- other should now be empty.
        other:clear()

        return ini, fin
    end
end

-- Remove all ε-transitions. This may also reduce the number of states.
function NFA:optimise()
    local seen  = Set:new()
    local queue = Array:of(self._ini)

    while queue.length > 0 do
        local st = queue:pop()

        local i = 1
        while i <= st.trs.length do
            local tr = st.trs[i]
            if Epsilon:made(tr) and tr.to ~= self._fin then
                -- This is an ε-transition to a non-final state, which
                -- means we can replace this with all the outgoing edges
                -- from tr.to
                st.trs:splice(i, 1, tr.to.trs:unpack())
                i = i - 1 + tr.to.trs.length
            else
                i = i + 1
            end
        end

        for tr in st.trs:values() do
            if tr.to:hasEpsilonTo(self._fin) then
                --
                -- This transition indirectly reaches the final state like
                -- this:
                --
                --   q -> r -[ε]-> fin
                --
                -- which means we can redirect the destination to the final
                -- state and turn it into this:
                --
                --   q -> fin
                --
                tr.to = self._fin
            end
            if not seen:has(tr.to) then
                -- We haven't seen this destination state so recurse into
                -- it. The reason why we do this as a loop is that we might
                -- overflow the stack if the NFA is large.
                seen:add(tr.to)
                queue:push(tr.to)
            end
        end
    end
end

return NFA
