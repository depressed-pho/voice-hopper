local class = require("class")

--
-- A FIFO queue, implemented as a dynamically-allocated ring
-- buffer. Elements can only be inserted at, or removed from, either the
-- front or the back of the queue. Both insertion and removal cost
-- amortised O(1).
--
local Queue = class("Queue")

--
-- Construct a queue. It optionally takes an iterator which generates the
-- initial contents of the queue, or a Lua sequence of elements.
--
function Queue:__init(iter, ...)
    self._seq      = {}
    self._capacity = 0 -- Physical length.
    self._length   = 0 -- Logical length.
    self._front    = 0 -- These indices are 0-origin.
    self._back     = 0 -- Elements exists in the range of [front, back).
    self._growth   = 1.5

    if iter ~= nil then
        if type(iter) == "table" then
            local len = 0
            for i, elem in ipairs(iter) do
                self._seq[i] = elem
            end
            self._capacity = len
            self._back     = len
        elseif type(iter) == "function" then
            for elem in iter, ... do
                self._capacity = self._capacity + 1
                self._back     = self._back   + 1
                self._seq[self._back] = elem
            end
        else
            error("Queue:new() takes an optional iterator or a sequence of initial contents: "..tostring(iter), 2)
        end
    end
end

--
-- The string representation of the queue.
--
function Queue:__tostring()
    local elems = {}
    for elem in self:values() do
        if type(elem) == "string" then
            table.insert(elems, string.format("%q", elem))
        else
            table.insert(elems, tostring(elem))
        end
    end
    return "Queue {" .. table.concat(elems, ", ") .. "}"
end

--
-- The length of the queue.
--
function Queue.__getter:length()
    return self._length
end

--
-- Queue#values() returns an iterator which iterates its elements from the
-- front to the back:
--
--   local q = Queue:new()
--   q:push(1)
--   q:push(2)
--   q:push(3)
--   for elem in q:values() do
--       print(elem)
--   end
--   -- Prints "1", "2", then "3".
--
function Queue:values()
    local i = 0
    return function()
        if i >= self._length then
            -- Reached the end of the queue.
            return nil
        elseif self._front < self._back then
            -- The queue is in a non-wrapped state.
            local ret = self._seq[self._front + i + 1]
            i = i + 1
            return ret
        else
            -- The queue is in a wrapped state. Which part does i point to?
            if i < self._capacity - self._front then
                -- It's in the second half.
                local ret = self._seq[self._front + i + 1]
                i = i + 1
                return ret
            else
                -- It's in the first half.
                local ret = self._seq[i - (self._capacity - self._front) + 1]
                i = i + 1
                return ret
            end
        end
    end
end

--
-- Convert a queue into a sequence.
--
function Queue:toSeq()
    local tmp = {}
    local idx = 1
    for elem in self:values() do
        tmp[idx] = elem
        idx = idx + 1
    end
    return tmp
end

--
-- Insert an element at the back of the queue. The element cannot be nil.
--
function Queue:push(elem)
    assert(elem ~= nil, "Queue:push() expects a non-nil element")

    if self._length == 0 then
        -- The queue is logically empty.
        if self._capacity == 0 then
            -- It's physically empty too.
            self._capacity = 1
        end
        self._front  = 0
        self._back   = 1
        self._seq[1] = elem
    elseif self._front < self._back then
        -- The queue is in a non-wrapped state.
        if self._back < self._capacity then
            -- There's a space at the physical end of the queue.
            self._back = self._back + 1
            self._seq[self._back] = elem
        else
            -- There's no space at the physical end of the queue. Can we
            -- wrap it around?
            if self._front > 0 then
                -- Yes we can.
                self._back = 1
                self._seq[self._back] = elem
            else
                -- No, there's no space at the physical beginning of the
                -- queue, but since the queue isn't wrapped we can simply
                -- extend it.
                self._capacity = math.floor(self._capacity * self._growth) + 1
                self._back     = self._back   + 1
                self._seq[self._back] = elem
            end
        end
    else
        -- The queue is in a wrapped state.
        if self._front - self._back > 0 then
            -- There's a space at the logical end of the queue.
            self._back = self._back + 1
            self._seq[self._back] = elem
        else
            -- There's no space and it's in a wrapped state. We must
            -- reallocate the entire queue.
            local tmp = {}
            local idx = 1
            for i = self._front, self._capacity - 1 do
                tmp[idx] = self._seq[i + 1]
                idx      = idx + 1
            end
            for i = 0, self._back - 1 do
                tmp[idx] = self._seq[i + 1]
                idx      = idx + 1
            end
            self._capacity = math.floor(self._capacity * self._growth) + 1
            self._front    = 0
            self._back     = idx
            self._seq      = tmp
            self._seq[idx] = elem
        end
    end
    self._length = self._length + 1
    return self
end

--
-- Insert an element at the front of the queue. The element cannot be nil.
--
function Queue:unshift(elem)
    assert(elem ~= nil, "Queue:unshift() expects a non-nil element")

    if self._length == 0 then
        -- The queue is logically empty.
        if self._capacity == 0 then
            -- It's physically empty too.
            self._capacity = 1
        end
        self._front  = 0
        self._back   = 1
        self._seq[1] = elem
    elseif self._front < self._back then
        -- The queue is in a non-wrapped state.
        if self._front > 0 then
            -- There's a space at the physical beginning of the queue.
            self._front = self._front - 1
            self._seq[self._front + 1] = elem
        else
            -- There's no space at the physical beginning of the queue. Can
            -- we wrap it around?
            if self._back < self._capacity then
                -- Yes we can.
                self._front = self._capacity - 1
                self._seq[self._front + 1] = elem
            else
                -- No, there's no space at the physical end. We must
                -- reallocate the entire queue.
                local tmp = {elem}
                local idx = 2
                for i = self._front, self._back - 1 do
                    tmp[idx] = self._seq[i + 1]
                    idx      = idx + 1
                end
                self._capacity = math.floor(self._capacity * self._growth) + 1
                self._front    = 0
                self._back     = idx
                self._seq      = tmp
            end
        end
    else
        -- The queue is in a wrapped state.
        if self._front > self._back then
            -- There's a space before the logical beginning of the queue.
            self._front = self._front - 1
            self._seq[self._front + 1] = elem
        else
            -- There's no space in the middle. we must reallocate the
            -- entire queue.
            local tmp = {elem}
            local idx = 2
            for i = self._front, self._capacity - 1 do
                tmp[idx] = self._seq[i + 1]
                idx      = idx + 1
            end
            for i = 0, self._back - 1 do
                tmp[idx] = self._seq[i + 1]
                idx      = idx + 1
            end
            self._capacity = math.floor(self._capacity * self._growth) + 1
            self._front    = 0
            self._back     = idx
            self._seq      = tmp
        end
    end
    self._length = self._length + 1
    return self
end

--
-- Remove an element from the back of the queue. If the queue is empty it
-- returns nil.
--
function Queue:pop()
    if self._length == 0 then
        -- The queue is logically empty.
        return nil
    elseif self._front < self._back then
        -- The queue is in a non-wrapped state.
        local ret = self._seq[self._back]
        self._seq[self._back] = nil
        self._back   = self._back   - 1
        self._length = self._length - 1
        return ret
    else
        -- The queue is in a wrapped state.
        assert(self._back > 0)
        local ret = self._seq[self._back]
        self._seq[self._back] = nil
        if self._back > 1 then
            -- There are still more.
            self._back = self._back - 1
        else
            -- No more elements in the first half.
            self._back = self._capacity
        end
        self._length = self._length - 1
        return ret
    end
end

--
-- Remove an element from the front of the queue. If the queue is empty it
-- returns nil.
--
function Queue:shift()
    if self._length == 0 then
        -- The queue is logically empty.
        return nil
    elseif self._front < self._back then
        -- The queue is in a non-wrapped state.
        self._front = self._front + 1
        local ret = self._seq[self._front]
        self._seq[self._front] = nil
        self._length = self._length - 1
        return ret
    else
        -- The queue is in a wrapped state.
        assert(self._front < self._capacity)
        local ret = self._seq[self._front + 1]
        self._seq[self._front + 1] = nil
        if self._front + 1 >= self._capacity then
            -- No more elements in the second half.
            self._front = 0
        else
            self._front = self._front + 1
        end
        self._length = self._length - 1
        return ret
    end
end

return Queue
