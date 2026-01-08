-- -*- lua -*-
codes = true
std   = "min" -- or should this be "luajit"?

-- Assignments to globals should count as defining them.
allow_defined     = true
allow_defined_top = true

-- Warnings to ignore.
ignore = {
    "113/super", -- Accessing "super" without defining it is okay.
    "211/_.*",   -- Unused local variables starting with "_" are okay.
    "212/self",  -- Not using argument "self" is okay.
    "213/_.*",   -- Unused loop variables starting with "_" are okay.
    "411",       -- Redefining local variables is okay.
    "412",       -- Redefining arguments is okay.
    "421/_.*",   -- Shadowing unused local variables is okay.
    "432",       -- Shadowing upvalue arguments is okay.
    "542",       -- Empty blocks (such as "if" branches) are okay.
}

-- Per-file permissions on using non-standard globals.
files["lib/fs.lua"].read_globals = {"bmd"}
