--
-- A shim for the standard table functions that may be missing.
--
if table.unpack == nil then
    table.unpack = unpack
end
