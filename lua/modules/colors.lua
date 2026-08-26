-- Минимальная схема: белый текст на чёрном, красным — только ключевые слова.
-- Раскраску даёт treesitter (см. modules/treesitter.lua), поэтому правила
-- пишутся на его захваты @keyword.*, единые для всех языков.

vim.opt.termguicolors = true -- без этого guifg вообще не применяется в терминале
vim.o.background = "dark"

vim.cmd("hi clear")
if vim.fn.exists("syntax_on") == 1 then
  vim.cmd("syntax reset")
end
vim.g.colors_name = "mono"

local WHITE = "#ffffff"
local RED   = "#ff6b6b" -- не чистый #ff0000: на чёрном он режет глаз
local GREY  = "#6b6b6b" -- комментарии и служебный текст
local BLACK = "#000000"
local DARK  = "#141414" -- подсветка строки, попапы

local hl = function(group, opts) vim.api.nvim_set_hl(0, group, opts) end

hl("Normal", { fg = WHITE, bg = BLACK })
hl("NormalFloat", { fg = WHITE, bg = DARK })

-- 1. Всё содержимое буфера — белое. Захваты treesitter по умолчанию
--    ссылаются на эти стандартные группы, поэтому их достаточно обнулить здесь.
for _, g in ipairs({
  "Statement", "Identifier", "Type", "Constant", "Special", "PreProc", "Function",
  "String", "Number", "Boolean", "Float", "Character", "Operator", "Delimiter",
  "Structure", "Typedef", "StorageClass", "Include", "Define", "Macro", "Label",
  "Exception", "Conditional", "Repeat", "Keyword", "Tag", "SpecialChar", "Title",
  "Underlined", "Directory", "@variable", "@variable.builtin", "@variable.member",
  "@variable.parameter", "@function", "@function.call", "@function.method",
  "@function.builtin", "@constructor", "@type", "@type.builtin", "@property",
  "@field", "@method", "@module", "@namespace", "@attribute", "@constant",
  "@constant.builtin", "@boolean", "@number", "@string", "@string.escape",
  "@operator", "@punctuation", "@punctuation.bracket", "@punctuation.delimiter",
  "@punctuation.special", "@label", "@tag", "@tag.attribute", "@tag.delimiter",
}) do
  hl(g, { fg = WHITE, bg = "NONE" })
end

-- 2. Ключевые слова — красные. if / for / while / const / let / await / async /
--    class / function / return / import / export / try / catch / throw / new /
--    typeof / public / readonly и т.д.
for _, g in ipairs({
  "@keyword", "@keyword.function", "@keyword.type", "@keyword.conditional",
  "@keyword.repeat", "@keyword.return", "@keyword.coroutine", "@keyword.import",
  "@keyword.export", "@keyword.exception", "@keyword.operator", "@keyword.modifier",
  "@keyword.directive", "@keyword.debug", "@type.qualifier",
  -- псевдонимы старых версий парсеров
  "@conditional", "@repeat", "@include", "@exception", "@storageclass",
}) do
  hl(g, { fg = RED, bg = "NONE" })
end

-- 3. Комментарии — серые.
for _, g in ipairs({ "Comment", "@comment", "@comment.documentation", "SpecialComment" }) do
  hl(g, { fg = GREY, bg = "NONE" })
end
hl("@spell", {}) -- не должен перекрашивать комментарии

-- 4. Интерфейс. Красный здесь не используется, чтобы он значил ровно одно —
--    "ключевое слово" (исключение: DiagnosticError, где красный уместен).
hl("CursorLine",   { bg = DARK })
hl("CursorLineNr", { fg = WHITE })
hl("LineNr",       { fg = GREY })
hl("Visual",       { fg = BLACK, bg = WHITE })
hl("Search",       { fg = BLACK, bg = WHITE })
hl("IncSearch",    { fg = BLACK, bg = WHITE })
hl("MatchParen",   { fg = WHITE, bg = DARK, bold = true })
hl("Pmenu",        { fg = WHITE, bg = DARK })
hl("PmenuSel",     { fg = BLACK, bg = WHITE })
hl("PmenuSbar",    { bg = DARK })
hl("PmenuThumb",   { bg = GREY })
hl("StatusLine",   { fg = WHITE, bg = DARK })
hl("StatusLineNC", { fg = GREY,  bg = DARK })
hl("WinSeparator", { fg = GREY,  bg = BLACK })
hl("VertSplit",    { fg = GREY,  bg = BLACK })
hl("SignColumn",   { bg = BLACK })
hl("FoldColumn",   { fg = GREY,  bg = BLACK })
hl("NonText",      { fg = GREY })
hl("EndOfBuffer",  { fg = BLACK })
hl("Folded",       { fg = GREY,  bg = DARK })
hl("TabLine",      { fg = GREY,  bg = DARK })
hl("TabLineSel",   { fg = BLACK, bg = WHITE })
hl("TabLineFill",  { bg = BLACK })

-- 4b. Telescope. Без этого TelescopeSelection наследует Visual, то есть жёсткую
--     инверсию — на чёрном фоне она бьёт по глазам. Здесь выбранная строка просто
--     красная, а совпавшие с запросом буквы подчёркнуты: подчёркивание видно и на
--     белых строках, и на уже красной выбранной.
hl("TelescopeSelection",      { fg = RED,   bg = "NONE", bold = true })
hl("TelescopeSelectionCaret", { fg = RED,   bg = "NONE", bold = true })
hl("TelescopeMultiSelection", { fg = RED,   bg = "NONE" })
hl("TelescopeMatching",       { fg = RED,   bg = "NONE", underline = true })
hl("TelescopePromptPrefix",   { fg = WHITE, bg = "NONE" })
hl("TelescopeBorder",         { fg = GREY,  bg = "NONE" })
hl("TelescopeTitle",          { fg = WHITE, bg = "NONE" })

-- 5. Диагностика и орфография. spell включён глобально (set.lua), поэтому
--    SpellBad делаем подчёркиванием без цвета — иначе он спорит с красным.
hl("DiagnosticError", { fg = RED })
hl("DiagnosticWarn",  { fg = WHITE })
hl("DiagnosticInfo",  { fg = WHITE })
hl("DiagnosticHint",  { fg = WHITE })
hl("SpellBad",   { undercurl = true, sp = GREY })
hl("SpellCap",   { undercurl = true, sp = GREY })
hl("SpellRare",  { undercurl = true, sp = GREY })
hl("SpellLocal", { undercurl = true, sp = GREY })

-- 6. LSP semantic tokens в Neovim 0.10 включаются сами и красят код поверх
--    treesitter группами @lsp.type.*. Выключаем, иначе схема выше "поплывёт".
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if client then
      client.server_capabilities.semanticTokensProvider = nil
    end
  end,
})
