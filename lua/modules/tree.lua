-- nvim-tree: постоянная панель слева. Netrw остаётся загруженным, но открытие
-- каталогов плагин перехватывает сам (hijack_netrw включён по умолчанию),
-- поэтому :Ex и `nvim .` теперь открывают дерево, а не netrw.
--
-- Иконок нет намеренно: Nerd Font в терминале не стоит. Папку от файла отличает
-- стрелка ▸/▾, вложенность — направляющие │, git-статус — однобуквенный значок.
require("nvim-tree").setup({
  view = {
    width = 34,
    side = "left",
    preserve_window_proportions = true,
  },
  renderer = {
    group_empty = true, -- цепочка из одиночных папок схлопывается в одну строку
    root_folder_label = ":t", -- в 34 колонки полный путь не нужен, хватает имени
    indent_markers = { enable = true },
    highlight_git = "icon", -- цвет только на значке; имя файла остаётся белым
    icons = {
      show = { file = false, folder = false, folder_arrow = true, git = true },
      glyphs = {
        folder = { arrow_closed = "▸", arrow_open = "▾" },
        git = {
          unstaged = "~",
          staged = "+",
          unmerged = "!",
          renamed = "»",
          untracked = "?",
          deleted = "-",
          ignored = "·",
        },
      },
    },
  },
  -- Панель сама раскрывает путь до файла, открытого в соседнем окне.
  update_focused_file = { enable = true },
  -- Точки видно, а игнорируемое git'ом (node_modules, dist) — нет.
  -- Переключается на лету: gh — точки, I — игнорируемое. Точки не на H,
  -- потому что H отдан переключению табов (см. on_attach ниже).
  filters = { dotfiles = false, git_ignored = true },
  actions = {
    open_file = {
      -- Без этого Enter на файле сначала просит выбрать окно буквой.
      window_picker = { enable = false },
    },
  },
  git = { enable = true, timeout = 400 },
  -- Панель — одна на всё окно, а не свойство отдельной табы: открыл в одной —
  -- появилась во всех (open), закрыл в одной — исчезла везде (close). Без этого
  -- <C-t> из дерева уводил в новую табу без панели, и раскладка табов ехала.
  tab = { sync = { open = true, close = true } },
  -- Дефолтные бинды дерева + правки: H и J внутри панели должны означать то же,
  -- что и везде (remap.lua: H — gT, J — gt), иначе из дерева не выйти по табам.
  -- Освободившийся toggle точек переезжает на gh.
  on_attach = function(bufnr)
    local api = require("nvim-tree.api")
    api.config.mappings.default_on_attach(bufnr)

    local function opts(desc)
      return { desc = "nvim-tree: " .. desc, buffer = bufnr, noremap = true, silent = true, nowait = true }
    end

    vim.keymap.set("n", "H", "gT", opts("предыдущая таба"))
    vim.keymap.set("n", "J", "gt", opts("следующая таба"))
    vim.keymap.set("n", "gh", api.filter.dotfiles.toggle, opts("точки: показать/скрыть"))
  end,
})

-- ,e — открыть панель и сразу встать в неё; повторное ,e уже изнутри — закрыть.
-- Голый NvimTreeToggle для этого не годится: при открытой панели он закрывает её
-- из любого окна, то есть перейти в дерево тем же ,e не получается.
vim.keymap.set("n", ",e", function()
  local api = require("nvim-tree.api")
  if vim.bo.filetype == "NvimTree" then
    api.tree.close()
  else
    api.tree.focus()
  end
end, { silent = true, desc = "nvim-tree: открыть/закрыть панель" })

-- ,E — найти текущий файл в дереве.
vim.keymap.set("n", ",E", "<cmd>NvimTreeFindFile<cr>", { silent = true })

-- spell включён глобально (set.lua) и в дереве подчёркивает половину имён.
vim.api.nvim_create_autocmd("FileType", {
  pattern = "NvimTree",
  callback = function()
    vim.opt_local.spell = false
  end,
})
