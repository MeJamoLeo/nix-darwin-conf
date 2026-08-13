-- CP Python snippets. Trigger with `<prefix><Tab>` in insert mode.
-- Edit this file and restart nvim to pick up changes (no rebuild needed:
-- ~/cp/snippets is an out-of-store symlink to this repo path).
local ls = require("luasnip")
local s = ls.snippet
local i = ls.insert_node
local fmt = require("luasnip.extras.fmt").fmt

-- luasnip の from_lua ローダーは filetype 単位なので、このファイルの snippet は
-- ~/cp の外の .py でも展開されてしまう。長い定型（phaseb）だけは誤爆が痛いので
-- バッファのパスで縛る。
local function in_cp_dir()
  return vim.startswith(vim.fn.expand("%:p"), vim.fn.expand("~/cp/"))
end

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

  -- Phase B thinking log ------------------------------------------------
  -- 1-8 は phase-b-rubric.md の Part B（ムーブ点）の8項目そのもの。埋めた
  -- main.py がそのまま採点入力になる。~/cp 配下でのみ展開する。
  -- start/end/judgement 行は rubric v0.3 で追加。ムーブ#8「戦略転換の判断」は
  -- 詰まらずに解き切った回だと観測材料が無く採点者が割れた（試行3で ±12.5）ので、
  -- 自己統制を直接記録させる。phase-b-trials の「打ち切り（予定/実際）」列の一次データも兼ねる。
  s("phaseb", fmt([[
# ============================================================
# Phase B thinking log   problem: {}   cutoff: {}
# start: {}   end: {}   judgement: submittable / stopped / still going
# Write as you think. A step left empty is scored 0.
# ------------------------------------------------------------
# 1. RESTATE
#    Input / output / constraints, in my own words:
#
# 2. SMALL CASE
#    One small input worked out by hand:
#
# 3. BRUTE FORCE
#    The naive method, and its complexity:
#
# 4. BUDGET
#    From the constraints (N <= ___), I need O(____) or better.
#    Can brute force already fit inside this budget?  yes / no
#
# 5. BOTTLENECK
#    In one sentence: I need a faster way to ____
#
# 6. CANDIDATES
#    Typical tools I thought about, and why each one fits or not:
#
# 7. TEST
#    I ran the idea on an example or a counterexample. Result:
#
# 8. SWITCH
#    When I got stuck I moved to ____ / I stopped because ____
#
# FINAL
#    Chosen approach and its complexity, checked against step 4:
# ============================================================
]], { i(1, "abcXXX_c"), i(2, "30min"), i(3, "HH:MM"), i(4, "HH:MM") }),
    { condition = in_cp_dir, show_condition = in_cp_dir }),
}
