--
-- A shim for the standard utf8 module for Lua interpreters that lack
-- it. These function doesn't support the so-called lax mode: the lax flag
-- is ignored.
--
-- luacheck: globals utf8
if utf8 == nil then
    require("shim/table")

    -- Assume we are on LuaJIT and the BitOp-compatible API is
    -- available. At least it must be externally installed. Bundlers would have to ignore this.
    local bit    = require("bit")
    local band   = bit.band
    local bor    = bit.bor
    local lshift = bit.lshift
    local rshift = bit.rshift
    local tobit  = bit.tobit

    utf8 = {}

    function utf8.char(...)
        local ret = {}
        local len = select("#", ...)
        for i = 1, len do
            local code = select(i, ...)

            assert(
                type(code) == "number" and tobit(code) == code,
                "utf8.char() expects positive integers")
            assert(
                code >= 0 and code <= 0x10FFFF,
                "utf8.char() only supports code points in [U+0000, U+10FFFF]")

            if code <= 0x7F then
                -- 1 octet
                ret[i] = string.char(code)
            elseif code <= 0x7FF then
                -- 2 octets
                ret[i] = string.char(
                    bor(band(rshift(code, 6), 0x1F), 0xC0),
                    bor(band(       code    , 0x3F), 0x80)
                )
            elseif code <= 0xFFFF then
                -- 3 octets
                ret[i] = string.char(
                    bor(band(rshift(code, 12), 0x0F), 0xE0),
                    bor(band(rshift(code,  6), 0x3F), 0x80),
                    bor(band(       code     , 0x3F), 0x80)
                )
            else
                -- 4 octets
                ret[i] = string.char(
                    bor(band(rshift(code, 18), 0x07), 0xF0),
                    bor(band(rshift(code, 12), 0x3F), 0x80),
                    bor(band(rshift(code,  6), 0x3F), 0x80),
                    bor(band(       code     , 0x3F), 0x80)
                )
            end
        end
        return table.concat(ret)
    end

    -- %z is for Lua 5.1 / LuaJIT compatibility.
    utf8.charpattern = "[%z\x01-\x7F\xC2-\xFD][\x80-\xBF]*"

    local function _decode(str, idx)
        local b    = string.byte(str, idx)
        local code = 0

        if b <= 0x7F then
            -- 1 octet
            code = b
        elseif band(b, 0xC0) == 0x80 then
            -- Orphaned continuation.
            return
        else
            local nConts = 0 -- the number of continuation octets
            while band(b, 0x40) > 0 do -- 7th bit is on
                -- Read the next octet.
                nConts = nConts + 1
                if nConts > 3 then
                    -- Too many continuations.
                    return
                end

                local nextB = string.byte(str, idx + nConts)
                if nextB == nil or band(nextB, 0xC0) ~= 0x80 then
                    -- Premature end of sequence, or the next octet is not
                    -- a continuation.
                    return
                end

                -- Add lower 6 bits from the continuation.
                code = bor(lshift(code, 6), band(nextB, 0x3F))
                b    = lshift(b, 1)
            end
            -- Add bits from the first octet.
            code = bor(code, lshift(band(b, 0x7F), nConts * 5))
            -- Skip continuation octets read.
            idx = idx + nConts
        end

        if 0xD800 <= code and code <= 0xDFFF then
            -- Surrogate pairs are disallowed.
            return
        else
            return code, idx + 1
        end
    end

    local function _codes(str, skip)
        local len = #str
        local idx = skip + 1

        if idx <= len then
            local b = string.byte(str, idx)
            while b and band(b, 0xC0) == 0x80 do
                -- This is a continuation octet.
                idx = idx + 1
                b   = string.byte(str, idx)
            end
        end

        if idx > len then
            return
        end

        local code, nextIdx = _decode(str, idx)
        if code == nil then
            error("Invalid UTF-8 octet sequence at byte position " .. tostring(idx), 2)
        end

        local nextB = string.byte(str, nextIdx)
        if nextB ~= nil and band(nextB, 0xC0) == 0x80 then
            -- Orphaned continuation
            error("Invalid UTF-8 octet sequence at byte position " .. tostring(nextIdx), 2)
        end

        return idx, code
    end

    function utf8.codes(str)
        assert(type(str) == "string", "utf8.codes() expects a UTF-8 string")
        return _codes, str, 0
    end

    function utf8.codepoint(str, from, to)
        assert(type(str) == "string", "utf8.codepoint() expects a UTF-8 string as its 1st argument")
        assert(from == nil or type(from) == "number", "utf8.codepoint() expects an optional number as its 2nd argument")
        assert(to   == nil or type(to  ) == "number", "utf8.codepoint() expects an optional number as its 3rd argument")

        from = from or 1
        to   = to   or from

        if from < 0 then
            from = from + #str + 1
        end
        if to < 0 then
            to = to + #str + 1
        end
        assert(from >= 1 and to <= #str, "utf8.codepoint(): indices out of bounds")

        local codes = {}
        while from <= to do
            local code, nextIdx = _decode(str, from)
            if code == nil then
                error("Invalid UTF-8 octet sequence at byte position " .. tostring(from), 2)
            end

            table.insert(codes, code)
            from = nextIdx
        end
        -- luacheck: read_globals table.unpack
        return table.unpack(codes)
    end

    function utf8.len(str, from, to)
        assert(type(str) == "string", "utf8.len() expects a UTF-8 string as its 1st argument")
        assert(from == nil or type(from) == "number", "utf8.len() expects an optional number as its 2nd argument")
        assert(to   == nil or type(to  ) == "number", "utf8.len() expects an optional number as its 3rd argument")

        from = from or 1
        to   = to or -1

        if from < 0 then
            from = from + #str + 1
        end
        if to < 0 then
            to = to + #str + 1
        end
        assert(from >= 1 and to <= #str, "utf8.len(): indices out of bounds")

        local numCodes = 0
        while from <= to do
            local code, nextIdx = _decode(str, from)
            if code == nil then
                return nil, from
            end

            numCodes = numCodes + 1
            from     = nextIdx
        end
        return numCodes
    end

    function utf8.offset(str, num, from, to)
        assert(type(str) == "string", "utf8.offset() expects a UTF-8 string as its 1st argument")
        assert(type(num) == "number", "utf8.offset() expects a number as its 2nd argument")
        assert(to == nil or type(to) == "number", "utf8.len() expects an optional number as its 3rd argument")

        from = from or ((num >= 0 and 1) or #str + 1)
        if from < 0 then
            from = from + #str + 1
        end
        assert(from >= 1 and from <= #str + 1, "utf8.offset(): indices out of bounds")

        if num == 0 then
            -- A special case: find the beginning of the octet sequence
            -- containing "from".
            while from > 1 do
                local b = string.byte(str, from)
                if band(b, 0xC0) == 0x80 then
                    from = from - 1
                else
                    break
                end
            end
        else
            local b = string.byte(str, from)
            if band(b, 0xC0) == 0x80 then
                error("utf8.offset(): Initial position is at a continuation octet", 2)
            end

            if num < 0 then
                -- Move back
                while num < 0 and from > 1 do
                    -- Find the beginning of the previous octet sequence.
                    repeat
                        from = from - 1
                        b    = string.byte(str, from)
                    until from <= 1 or band(b, 0xC0) ~= 0x80
                    num = num + 1
                end
            else
                num = num - 1
                while num > 0 and from < #str do
                    -- Find the beginning of the next octet sequence.
                    repeat
                        from = from + 1
                        b    = string.byte(str, from)
                    until from >= #str or band(b, 0xC0) ~= 0x80
                    num = num - 1
                end
            end
        end

        if num ~= 0 then
            return nil
        else
            return from
        end
    end
end
