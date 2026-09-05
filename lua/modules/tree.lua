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
  -- tab.sync намеренно не выставлен (дефолт — выключено): табы vim в этом
  -- конфиге не используются, открытые файлы живут буферами в одной табе
  -- (см. modules/tabline.lua). Синхронизация только плодила бы копии панели.
  --
  -- Дефолтные бинды дерева + правки: <C-t>, H и J внутри панели должны означать
  -- то же, что и везде, иначе панель ведёт себя не как остальной редактор.
  -- Освободившийся toggle точек переезжает на gh.
  on_attach = function(bufnr)
    local api = require("nvim-tree.api")
    api.config.mappings.default_on_attach(bufnr)

    local function opts(desc)
      return { desc = "nvim-tree: " .. desc, buffer = bufnr, noremap = true, silent = true, nowait = true }
    end

    local files = require("modules.tabline")

    -- <C-t> раньше был api.node.open.tab, то есть :tabnew: новая таба + своя
    -- копия дерева на каждый файл. Теперь открывает файл в окне редактора,
    -- ровно как Enter, — мышечная память сохраняется, таб не появляется.
    vim.keymap.set("n", "<C-t>", api.node.open.edit, opts("открыть файл в редакторе"))
    -- H/J переключают файлы (см. remap.lua). Через files.prev/next, а не
    -- :bprevious напрямую: иначе буфер подменился бы в самой панели.
    vim.keymap.set("n", "H", files.prev, opts("предыдущий файл"))
    vim.keymap.set("n", "J", files.next, opts("следующий файл"))
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

-- `nvim .` перехватывает hijack_directories и открывает дерево ВМЕСТО буфера,
-- то есть на весь экран и без окна редактора. Разворачиваем это в привычную
-- раскладку "панель слева | пустой редактор справа".
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    -- Проверяем не имя аргумента, а состояние: перехват к этому моменту уже
    -- подменил буфер каталога на NvimTree_1 — и <afile>, и argv(0) отдают
    -- именно его, так что isdirectory по ним не срабатывает.
    local wins = vim.api.nvim_tabpage_list_wins(0)
    if #wins ~= 1 or vim.bo[vim.api.nvim_win_get_buf(wins[1])].filetype ~= "NvimTree" then
      return
    end
    local api = require("nvim-tree.api")
    api.tree.close() -- свернуть перехваченное полноэкранное дерево
    vim.cmd.enew() -- пустое окно редактора
    api.tree.open() -- панель слева на свои 34 колонки
  end,
})

-- :q в последнем окне с файлом оставил бы одну панель на весь экран. Закрываем
-- её вместе с ним, чтобы Neovim нормально вышел. Файлы при этом закрываются не
-- через :q, а через gw (:Bclose) — он удаляет буфер, не трогая раскладку.
vim.api.nvim_create_autocmd("QuitPre", {
  callback = function()
    if vim.bo.filetype == "NvimTree" then
      return
    end
    local editors, trees = 0, {}
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_win_get_config(win).relative == "" then
        if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "NvimTree" then
          trees[#trees + 1] = win
        else
          editors = editors + 1
        end
      end
    end
    if editors == 1 then
      for _, win in ipairs(trees) do
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end,
})

-- Страховка: панель не должна оставаться единственным окном. В этом состоянии
-- она разъезжается на весь экран, и закрытие файла выглядит как "вместо файла
-- открылось дерево". Сюда можно прийти не только через :q (его ловит QuitPre
-- выше), но и через <C-w>c, закрытие последней табы и т.п.
vim.api.nvim_create_autocmd("WinClosed", {
  callback = function()
    vim.schedule(function()
      local wins = {}
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_config(win).relative == "" then
          wins[#wins + 1] = win
        end
      end
      if #wins ~= 1 or vim.bo[vim.api.nvim_win_get_buf(wins[1])].filetype ~= "NvimTree" then
        return
      end
      require("modules.tabline").open_editor_win()
    end)
  end,
})

-- spell включён глобально (set.lua) и в дереве подчёркивает половину имён.
vim.api.nvim_create_autocmd("FileType", {
  pattern = "NvimTree",
  callback = function()
    vim.opt_local.spell = false
  end,
})
