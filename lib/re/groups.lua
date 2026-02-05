local Array = require("collection/array")
local class = require("class")

--
-- Captured groups
--
local Groups = class("Groups")

function Groups:__init(src, numGroups, names)
    self._src    = src
    -- Indices of captured groups: {{{from0, from1}, to}, ...}. The reason
    -- why we record two starting positions is that captures will not be
    -- fixed until they are closed. "from0" is the fixed/committed position
    -- and "from1" is the trying position.
    self._groups = Array:new(numGroups) -- {{{from0, from1}, to}, ...}
    self._names  = names -- Map from string name to index
end

function Groups.__getter:length()
    return self._groups.length
end

function Groups.__getter:hasNames()
    return self._names.size > 0
end

-- "pos" should be inclusive.
function Groups:open(index, pos, reversed)
    local range = self._groups[index]
    if not range then
        range = {{nil, nil}, nil}
        self._groups[index] = range
    end
    if reversed then
        pos = pos - 1
    end
    range[1][2] = pos
end

-- "pos" should be exclusive.
function Groups:close(index, pos, reversed)
    local range = self._groups[index]
    assert(range)
    assert(range[1][2])
    if reversed then
        range[1][1] = pos
        range[2]    = range[1][2]
    else
        range[1][1] = range[1][2]
        range[2]    = pos-1
    end
end

function Groups:names()
    return self._names:keys()
end

function Groups:substringFor(which)
    local range = self:rangeFor(which)
    if range then
        return string.sub(self._src, range[1], range[2])
    end
end

function Groups:rangeFor(which)
    local index
    if type(which) == "number" then
        index = which
    else
        index = self._names:get(which)
        if not index then
            return
        end
    end

    local range = self._groups[index]
    if range and range[1][1] then
        return {range[1][1], range[2]}
    end
end

return Groups
