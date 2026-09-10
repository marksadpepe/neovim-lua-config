-- Leader bind to space
vim.g.mapleader = ","

-- Netrw выключен целиком: каталоги открывает своя панель (modules/explorer.lua),
-- а живой netrw перехватывал бы `nvim .` и `:e src/` раньше неё. Флаги стоят
-- здесь, а не в modules/*: plugin/netrwPlugin.vim успевает загрузиться внутри
-- require("config.lazy") ниже, то есть до modules/.
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- nvim-lspconfig на 0.10 зовёт vim.deprecate прямо при сорсинге своего plugin/,
-- то есть внутри require("config.lazy") ниже — поэтому глушилка стоит здесь, до
-- него. Две строки предупреждения не влезают в cmdheight, и каждый старт
-- упирался в "Press ENTER". Гасим ровно это сообщение: остальные vim.deprecate,
-- в том числе про настоящие устаревшие вызовы в этом конфиге, по-прежнему видны.
local deprecate = vim.deprecate
---@diagnostic disable-next-line: duplicate-set-field
vim.deprecate = function(name, ...)
  if type(name) == "string" and name:find("^nvim%-lspconfig support") then
    return
  end
  return deprecate(name, ...)
end

require("config.lazy")
require("plugins")
require("modules")
