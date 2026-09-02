-- Минимальная схема: белый текст на чёрном, красным — ключевые слова и базовые
-- типы TS. Раскраску даёт treesitter (см. modules/treesitter.lua), поэтому
-- правила пишутся на его захваты @keyword.* / @type.builtin, единые для языков.

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
  "@function.builtin", "@constructor", "@type", "@property",
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

-- 2b. Базовые типы TS — тоже красные: string / number / boolean / any / void /
--     never / unknown / symbol / object / unique. Тип аннотации видно сразу,
--     не вчитываясь. Пользовательские типы (@type: User, Promise, Record,
--     дженерики T) остаются белыми — красный держим за "встроенным словом".
--     Оговорки парсера: bigint помечен как @type, а не @type.builtin, поэтому
--     он белый; null / undefined в типах идут как @constant.builtin — одним
--     захватом со значениями, так что перекрасить их отдельно нельзя.
--     `new Date()` не краснеет: там последним применяется @constructor.
hl("@type.builtin", { fg = RED, bg = "NONE" })

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

-- 4c. gitsigns. Красный держим за ключевыми словами, поэтому сами знаки
--     серые: тип изменения различают глифы +, ~, _ (см. modules/gitsigns.lua).
--     Оверлей (,h) — фоном, а не цветом текста: там добавленное и удалённое
--     стоят рядом и одной формой уже не различаются.
hl("GitSignsAdd",    { fg = GREY, bg = BLACK })
hl("GitSignsChange", { fg = GREY, bg = BLACK })
hl("GitSignsDelete", { fg = GREY, bg = BLACK })
-- Blame текущей строки — служебный текст, тем же серым, что и комментарии:
-- он висит в каждой строке под курсором и не должен спорить с кодом.
hl("GitSignsCurrentLineBlame", { fg = GREY, bg = "NONE" })
-- Ln — подсветка строк в самом буфере, VirtLn — развёрнутые удалённые строки,
-- Inline/InLine — посимвольная разница внутри строки (ярче на тон).
hl("GitSignsAddLn",              { bg = "#12240f" })
hl("GitSignsChangeLn",           { bg = "#2a1414" })
hl("GitSignsAddInline",          { bg = "#1e3d18" })
hl("GitSignsChangeInline",       { bg = "#4a2020" })
hl("GitSignsDeleteInline",       { bg = "#4a2020" })
hl("GitSignsDeleteVirtLn",       { bg = "#2a1414" })
hl("GitSignsDeleteVirtLnInLine", { bg = "#4a2020" })
hl("GitSignsVirtLnum",           { fg = GREY,  bg = "#2a1414" })
-- Попапы blame (,b) и превью ханка идут на фоне NormalFloat.
hl("GitSignsAddPreview",    { bg = "#12240f" })
hl("GitSignsDeletePreview", { bg = "#2a1414" })

-- 4d. nvim-tree. Группы перечислены явно, потому что плагин зашивает синий
--     #8094b4 в NvimTreeFolderIcon, а к нему линкуются стрелки и направляющие;
--     ExecFile/ImageFile тянут зелёный из Question. Белое — имена, серое —
--     служебная графика. Git-значки серые по тому же принципу, что и gitsigns:
--     статус различает форма (~ + ? - » ·), а не цвет.
hl("NvimTreeNormal",            { fg = WHITE, bg = BLACK })
hl("NvimTreeWinSeparator",      { fg = GREY,  bg = BLACK })
hl("NvimTreeRootFolder",        { fg = GREY })
hl("NvimTreeFolderName",        { fg = WHITE, bold = true })
hl("NvimTreeOpenedFolderName",  { fg = WHITE, bold = true })
hl("NvimTreeSymlinkFolderName", { fg = WHITE, bold = true })
hl("NvimTreeEmptyFolderName",   { fg = GREY })
hl("NvimTreeFolderIcon",        { fg = GREY })
hl("NvimTreeIndentMarker",      { fg = GREY })
hl("NvimTreeFolderArrowClosed", { fg = GREY })
hl("NvimTreeFolderArrowOpen",   { fg = GREY })
hl("NvimTreeSpecialFile",       { fg = WHITE })
hl("NvimTreeExecFile",          { fg = WHITE })
hl("NvimTreeImageFile",         { fg = WHITE })
hl("NvimTreeSymlink",           { fg = WHITE, underline = true })
hl("NvimTreeLiveFilterPrefix",  { fg = GREY })
hl("NvimTreeLiveFilterValue",   { fg = WHITE })
for _, g in ipairs({
  "NvimTreeGitDeletedIcon", "NvimTreeGitDirtyIcon", "NvimTreeGitIgnoredIcon",
  "NvimTreeGitMergeIcon", "NvimTreeGitNewIcon", "NvimTreeGitRenamedIcon",
  "NvimTreeGitStagedIcon",
}) do
  hl(g, { fg = GREY })
end

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
