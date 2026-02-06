-- luacheck: read_globals table.unpack
require("shim/table")
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

function State:pushEpsilon(to)
    self.trs:push(Epsilon:new(to))
end

function State:unshiftEpsilon(to)
    self.trs:unshift(Epsilon:new(to))
end

function State:pushGrouping(to, isOpen, index, name)
    self.trs:push(Grouping:new(to, isOpen, index, name))
end

function State:pushMatching(to, matcher)
    self.trs:push(Matching:new(to, matcher))
end

-- Return true iff every transition from this state is an ε-transition to
-- the given state.
function State:isAliasTo(to)
    if self.trs.length == 0 then
        return false
    end
    for tr in self.trs:values() do
        if not Epsilon:made(tr) or tr.to ~= to then
            return false
        end
    end
    return true
end

--
-- A composable NFA. By composable it means it has exactly one initial
-- state and exactly one final state.
--
local NFA = class("NFA")

NFA.Transition = Transition
NFA.Epsilon    = Epsilon
NFA.State      = State

function NFA:__init(flags, reverse, node)
    self._ini      = nil -- State
    self._fin      = nil -- State
    self._reversed = reverse
    self:clear()

    if not node then
        -- Do nothing; just construct an empty NFA.

    elseif ast.Caret:made(node) then
        -- ini -[^]-> fin
        self._fin = State:new()
        self._ini:pushMatching(
            self._fin,
            m.CaretMatcher:new(flags:has(ast.Modifier.Multiline)))

    elseif ast.Dollar:made(node) then
        -- ini -[$]-> fin
        self._fin = State:new()
        self._ini:pushMatching(
            self._fin,
            m.DollarMatcher:new(flags:has(ast.Modifier.Multiline)))

    elseif ast.Mods:made(node) then
        -- Empty NFA; just modify the flags.
        for mod in node.enabled:values() do
            flags:add(mod)
        end
        for mod in node.disabled:values() do
            flags:delete(mod)
        end

    elseif ast.Literal:made(node) then
        -- ini -[lit]-> fin
        self._fin = State:new()
        self._ini:pushMatching(
            self._fin,
            m.LiteralMatcher:new(node.str, flags:has(ast.Modifier.IgnoreCase), reverse))

    elseif ast.Alternative:made(node) then
        -- ini -> node1 + node2 + ... -> fin
        --   where a+b is an NFA concatenation.
        local nodes = (reverse and node.nodes:toReversed()) or node.nodes
        for altNode in nodes:values() do
            self:append(NFA:new(flags, reverse, altNode))
        end

    elseif ast.CapturingGroup:made(node) then
        --  ,---[open]-> alt1 -[close]----v
        -- ini -[open]-> alt2 -[close]-> fin
        --  `---[open]-> ...  -[close]----^
        if not node.index then
            error(string.format("This capturing group has no index assigned. " ..
                                "You haven't validated the AST, have you?: %s", node), 2)
        end
        if node.alts.length > 0 then
            self._fin = State:new()
            for alt in node.alts:values() do
                local ini, fin = self:subsume(NFA:new(flags, reverse, alt))
                self._ini:pushGrouping(ini, true, node.index, node.name)
                fin:pushGrouping(self._fin, false, node.index, node.name)
            end
        end

    elseif ast.NonCapturingGroup:made(node) then
        --  ,---> alt1 ----v
        -- ini -> alt2 -> fin
        --  `---> ...  ----^
        if node.mods then
            -- The group itself locally modifies the flags.
            flags = (flags .. node.mods.enabled) - node.mods.disabled
        else
            -- Any changes to flags are restored upon exiting this group.
            flags = flags:clone()
        end
        if node.alts.length > 0 then
            self._fin = State:new()
            for alt in node.alts:values() do
                local ini, fin = self:subsume(NFA:new(flags, reverse, alt))
                self._ini:pushEpsilon(ini)
                fin:pushEpsilon(self._fin)
            end
        end

    elseif ast.Quantified:made(node) then
        --
        -- The easiest case, /a?/ and /a??/, are equivalent to /a{0,1}/ and
        -- /a{0,1}?/ and are compiled as:
        --
        --     ini -> a -> fin        ,-----------v
        --      `-----------^   and  ini -> a -> fin  respectively.
        --
        -- /a*/ and /a*?/, which are equivalent to /a{0,}/ and /a{0,}?/
        -- can be represented as:
        --                            ,------------.
        --            v--.            |     ,----v v
        --     ini -> a -' fin  and  ini -> a -. fin
        --      |     `----^ ^              ^--'
        --      `------------'
        --
        -- /a+/, which is equivalent to /a{1,}/, is as follows:
        --
        --            v--.
        --     ini -> a -' fin
        --            `-----^
        --
        -- /a{2,}/ involves 2 copies of a:
        --
        --                 v--.
        --     ini -> a -> a -' fin
        --                 `-----^
        --
        -- /a{3}/ has a very simple shape, which is in fact identical to
        -- /a{3}?/:
        --
        --     ini -> a -> a -> a -> fin
        --
        -- /a{2,4}/ has short circuits to the final state after visiting 2
        -- copies but can visit at most 4 copies:
        --
        --     ini -> a -> a -> a -> a -> fin
        --                 |    `---------^ ^
        --                 `----------------'
        --
        -- So the NFA forms a loop when there is no upper bound (i.e. inf).
        --
        if node.max > 0 then
            self._fin = State:new()
            local tail = self._ini

            local nCopies
            if node.max == math.huge then
                nCopies = math.max(node.min, 1)
            else
                nCopies = node.max
            end
            for i=1, nCopies do
                local ini, fin = self:subsume(NFA:new(flags, reverse, node.atom))
                if node.greedy then
                    -- Establish an entrance route to subgraph. This is
                    -- the most preferred route from the final state of
                    -- the parent because it's greedy.
                    tail:unshiftEpsilon(ini)
                    if i >= node.min then
                        if node.max == math.huge then
                            -- Form a loop. This is the most preferred
                            -- route from the subgraph because it's
                            -- greedy.
                            fin:pushEpsilon(ini)
                        end
                        -- We've matched at least the minimum number of
                        -- required atoms. Establish an exit route to
                        -- the final state with a precedence lower than
                        -- the loop.
                        fin:pushEpsilon(self._fin)
                        if i > node.min then
                            -- Also Establish a skip-over route that
                            -- jump into the final state without
                            -- entering the subgraph.
                            tail:pushEpsilon(self._fin)
                        end
                    end
                else
                    if i >= node.min then
                        if i > node.min then
                            tail:unshiftEpsilon(self._fin)
                        end
                        fin:pushEpsilon(self._fin)
                        if node.max == math.huge then
                            fin:pushEpsilon(ini)
                        end
                    end
                    tail:pushEpsilon(ini)
                end
                tail = fin
            end
        end

    elseif ast.Backreference:made(node) then
        -- ini -[ref]-> fin
        self._fin = State:new()
        self._ini:pushMatching(
            self._fin,
            m.BackrefMatcher:new(node.ref, reverse))

    elseif ast.Class:made(node) then
        -- ini -[class]-> fin
        self._fin = State:new()
        self._ini:pushMatching(
            self._fin,
            m.ClassMatcher:new(node, flags:has(ast.Modifier.IgnoreCase), reverse))

    elseif ast.Wildcard:made(node) then
        -- ini -[wild]-> fin
        self._fin = State:new()
        self._ini:pushMatching(
            self._fin,
            m.WildcardMatcher:new(flags:has(ast.Modifier.DotAll), reverse))

    elseif ast.Lookaround:made(node) then
        -- ini -[la]-> fin
        self._fin = State:new()

        -- Consider a case of nested lookbehinds /(?<=(?<=B)A)$/. This
        -- regexp should match any strings which doesn't end with (?<=B)A,
        -- which means B should still be tested backwards.
        local subgraph = NFA:new(flags, not node.ahead, node.group)
        subgraph:optimise()

        self._ini:pushMatching(
            self._fin,
            m.LookaroundMatcher:new(node.positive, node.ahead, subgraph))

    elseif ast.WordBoundary:made(node) then
        -- ini -[wb]-> fin
        self._fin = State:new()
        self._ini:pushMatching(
            self._fin,
            m.WordBoundaryMatcher:new(node.positive))

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
        local shown = Set:new()
        local function showTransitions(s)
            if shown:has(s) then
                return
            else
                shown:add(s)
            end

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

function NFA.__getter:isReversed()
    return self._reversed
end

function NFA:clear()
    self._ini = State:new()
    self._fin = self._ini
end

-- Append another NFA at the end of this one. Return the initial state and
-- the final state of the appended part of NFA.
function NFA:append(other)
    if self.isEmpty then
        -- Special case for self being empty: overwrite self with
        -- other. This is not for correctness, but for efficiency.
        self._ini = other._ini
        self._fin = other._fin

        -- other should now be empty.
        other:clear()

        return self._ini, self._fin
    else
        local ini, fin = self:subsume(other)

        -- Concatenate with ε.
        self._fin:pushEpsilon(ini)
        self._fin = fin

        return ini, fin
    end
end

function NFA:subsume(other)
    local ini, fin = other._ini, other._fin

    -- other should now be empty.
    other:clear()

    return ini, fin
end

-- Remove as many ε-transitions as possible. This may also reduce the
-- number of states. Not all ε-transitions can be eliminated though, which
-- is fine. Just not optimally efficient.
function NFA:optimise()
    local seen  = Set:new() -- Set of State
    local queue = Array:of(self._ini)

    while queue.length > 0 do
        local st = queue[queue.length]

        local pushed = false
        for tr in st.trs:values() do
            if tr.to:isAliasTo(self._fin) then
                --
                -- This transition indirectly reaches the final state like
                -- this, and no other transitions are possible:
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
                pushed = true
            end
        end

        if not pushed then
            queue:pop()

            local i = 1
            while i <= st.trs.length do
                local tr = st.trs[i]
                if Epsilon:made(tr) and tr.to ~= self._fin then
                    -- This is an ε-transition to a non-final state, which
                    -- means we can replace this with all the outgoing
                    -- edges from tr.to
                    st.trs:splice(i, 1, tr.to.trs:unpack())
                    i = i - 1 + tr.to.trs.length
                else
                    i = i + 1
                end
            end

            -- Eliminate redundant ε-transitions that goes from the same
            -- state to the same destination.
            local tmp   = Array:new()
            local eSeen = Set:new() -- Set of destination states
            for tr in st.trs:values() do
                if Epsilon:made(tr) then
                    if not eSeen:has(tr.to) then
                        eSeen:add(tr.to)
                        tmp:push(tr)
                    end
                else
                    tmp:push(tr)
                end
            end
            st.trs = tmp
        end
    end
end

function NFA:exec(src, initialPos, groups)
    -- Array of {pos, i, st} where pos being the starting byte position in
    -- str, i being the next transition to try, and st being the state at
    -- which we are.
    local stack = Array:of({initialPos, 1, self._ini})

    -- Map from Transition to Set of positions. If we enter the same state
    -- with the same byte position, we know we're in an infinite loop and
    -- need to break it. But note that we only need to record these on
    -- non-consuming transitions.
    local taken = Map:new()
    local function tryEpsilon(tr, pos)
        local poss = taken:get(tr)
        if poss then
            if poss:has(pos) then
                -- Break the loop.
                return false
            else
                poss:add(pos)
            end
        else
            taken:set(tr, Set:new {pos})
        end

        stack:push({pos, 1, tr.to})
        return true
    end

    while stack.length > 0 do
        local trial      = stack:pop()
        local pos, i, st = table.unpack(trial)
        if st == self._fin then
            -- Successful match
            return initialPos, pos-1
        end

        -- Try the i-th transition of state "st" at the byte position
        -- "pos". Does it succeed?
        local tr = st.trs[i]

        -- We are going to try the next one if this transition turns out to
        -- be a wrong path.
        if i < st.trs.length then
            -- Reuse the memory (unsafe!)
            trial[2] = i + 1
            stack:push(trial)
        end

        if Epsilon:made(tr) then
            tryEpsilon(tr, pos)

        elseif Grouping:made(tr) then
            if tryEpsilon(tr, pos) then
                if tr.isOpen then
                    groups:open(tr.index, pos, self._reversed)
                else
                    groups:close(tr.index, pos, self._reversed)
                end
            end

        elseif Matching:made(tr) then
            local nConsumed = tr.matcher:matches(src, pos, groups)
            if nConsumed then
                -- It succeeded. We are going to take this route, but if it
                -- fails we will backtrack to the next transition from this
                -- state (if any).
                if nConsumed == 0 then
                    tryEpsilon(tr, pos)
                else
                    stack:push({pos + nConsumed, 1, tr.to})
                end
            end
        else
            error("Unsupported transition type: " .. tostring(tr))
        end
    end

    -- Failed match
    return
end

return NFA
