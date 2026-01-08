--
-- A shim for the standard table functions that may be missing.
--
-- luacheck: globals table.unpack unpack
if table.unpack == nil then
    table.unpack = unpack
end
