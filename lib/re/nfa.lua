local Array = require("collection/array")
local Map   = require("collection/map")
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
    self._ts = Array:new() -- an array of transitions, not a set, because
                           -- the order matters for left-biased regexp
                           -- engines.
end

function State:addEpsilon(to)
    self._ts:push(Epsilon:new(to))
end

function State:addMatching(to, matcher)
    self._ts:push(Matching:new(to, matcher))
end

function State:transitions()
    return self._ts:values()
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

    elseif ast.Literal:made(node) then
        -- ini -[lit]-> fin
        self._fin = State:new()
        self._ini:addMatching(self._fin, m.LiteralMatcher:new(node.str))

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
        if #node.alts > 0 then
            self._fin = State:new()
            for _i, alt in ipairs(node.alts) do
                local altNFA = NFA:new()
                for _j, altNode in ipairs(alt.nodes) do
                    altNFA:append(NFA:new(flags, altNode))
                end

                local ini, fin = self:subsume(altNFA)
                self._ini:addEpsilon(ini)
                fin:addEpsilon(self._fin)
            end
        end
    else
        error("Don't know how to construct an NFA out of "..tostring(node), 2)
    end
end

function NFA:__tostring()
    local ret = {"NFA {\n"}

    if self.isEmpty then
        -- Special case for empty NFA.
        table.insert(ret, "  ini = fin\n")
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
            for tr in s:transitions() do
                table.insert(ret, "  ")
                table.insert(ret, from)
                table.insert(ret, " -> ")
                table.insert(ret, nameOf(tr.to))
                if Matching:made(tr) then
                    table.insert(ret, " [")
                    table.insert(ret, tostring(tr.matcher))
                    table.insert(ret, "]")
                end
                table.insert(ret, "\n")
                showTransitions(tr.to)
            end
        end
        showTransitions(self._ini)
    end

    table.insert(ret, "}")
    return table.concat(ret)
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

return NFA
