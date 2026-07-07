-- CP Python snippets. Trigger with `<prefix><Tab>` in insert mode.
-- Edit this file and restart nvim to pick up changes (no rebuild needed:
-- ~/cp/snippets is an out-of-store symlink to this repo path).
local ls = require("luasnip")
local s = ls.snippet
local i = ls.insert_node
local fmt = require("luasnip.extras.fmt").fmt

return {
  -- I/O ----------------------------------------------------------------
  s("ii",  fmt("{} = int(input())",                      { i(1, "n") })),
  s("is",  fmt("{} = input()",                           { i(1, "s") })),
  s("il",  fmt("{} = list(map(int, input().split()))",   { i(1, "a") })),
  s("im",  fmt("{}, {} = map(int, input().split())",     { i(1, "n"), i(2, "m") })),
  s("ig",  fmt("{} = [list(map(int, input().split())) for _ in range({})]",
               { i(1, "g"), i(2, "n") })),

  -- Loops --------------------------------------------------------------
  s("fr",  fmt("for {} in range({}):\n    {}",           { i(1, "i"), i(2, "n"), i(3) })),

  -- Boilerplate --------------------------------------------------------
  s("main", fmt([[
import sys
input = sys.stdin.readline

def solve():
    {}

solve()
]], { i(1) })),
}
