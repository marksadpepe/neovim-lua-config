-- Файловая панель слева — сайдбар в духе VS Code, без сторонних плагинов.
--
-- Модель: одна панель на весь редактор, открытые файлы — буферы (полоску вкладок
-- рисует modules/tabline.lua), табы vim не используются вообще. Отсюда два
-- свойства, которых не было раньше: панель не может продублироваться на файл
-- (сайдбар живёт внутри раскладки одной табы, а таба здесь всегда одна), и её
-- состояние "открыта/закрыта" не зависит от того, какой файл активен — ничто
-- не открывает её само, кроме VimEnter и явного ,e.
--
-- Иконок нет намеренно: Nerd Font в терминале не стоит. Папку от файла отличает
-- стрелка ▸/▾, git-статус — однобуквенный значок.

local M = {}

M.width = 34

-- Оконные опции панели. Таблицей, а не набором присваиваний, потому что список
-- нужен ещё и tabline.open_editor_win(): `vnew` наследует опции текущего окна,
-- а окно редактора там заводится как раз из панели — без сброса оно уезжало бы
-- без номеров строк, без signcolumn и с фоном панели.
M.window_options = {
  winfixwidth = true, -- сплиты редактора не должны сжимать панель
  number = false,
  relativenumber = false,
  signcolumn = "no",
  foldcolumn = "0",
  wrap = false,
  list = false,
  spell = false, -- spell включён глобально (set.lua) и подчёркивал бы половину имён
  cursorline = true,
  winhighlight = "Normal:ExplorerNormal,CursorLine:ExplorerCursorLine",
}

-- Те же опции, но как они выглядят в окне редактора. Снимок, а не копия набора
-- из set.lua: `:set number` оконную опцию глобально не выставляет (vim.go.number
-- так и остаётся false), поэтому `setlocal number<` вернул бы не то, что настроено,
-- а встроенный дефолт. Снимок берётся при загрузке модуля (текущее окно на старте
-- — редактор, set.lua к этому моменту отработал) и обновляется каждым открытием
-- панели. Читает его tabline.open_editor_win().
M.editor_window_options = {}

---@param w integer окно, с которого снимаем эталон
local function snapshot_editor(w)
  if not vim.api.nvim_win_is_valid(w) then
    return
  end
  -- Эталон снимаем только с обычного окна с файлом: ,e, нажатый из :help,
  -- quickfix или терминала, иначе записал бы в снимок их nonumber, и с ним
  -- открывались бы уже все следующие окна редактора.
  local b = vim.api.nvim_win_get_buf(w)
  if vim.bo[b].buftype ~= "" or vim.api.nvim_win_get_config(w).relative ~= "" then
    return
  end
  local t = {}
  for name in pairs(M.window_options) do
    t[name] = vim.wo[w][name]
  end
  M.editor_window_options = t
end

snapshot_editor(vim.api.nvim_get_current_win())

---Вернуть окну эталонные опции редактора. Нужно везде, где окно могло набраться
---опций панели: новое окно из `vnew` (tabline.open_editor_win) и буфер, побывавший
---в самой панели (автокоманда BufWinEnter ниже).
---@param w integer
function M.restore_editor_window(w)
  if not vim.api.nvim_win_is_valid(w) then
    return
  end
  for name, value in pairs(M.editor_window_options) do
    vim.wo[w][name] = value
  end
end

local uv = vim.uv or vim.loop
local ns = vim.api.nvim_create_namespace("explorer")

local root = vim.fn.getcwd()
local expanded = {} -- [абсолютный путь каталога] = true
local show_hidden = true -- точки видны, как и в прежнем конфиге; переключение — gh
local rows = {} -- строка N буфера описывается rows[N]
local git = {} -- [абсолютный путь] = значок статуса
local git_top -- корень репозитория: пути в git status относительны ему, не cwd
local git_busy, git_pending = false, false
local buf, win -- хендлы панели
local current -- путь файла, который подсвечен как текущий

-- .git прячем всегда (как VS Code через files.exclude), .DS_Store — мусор macOS.
-- Всё остальное видно: gitignored не фильтруется, тяжёлые каталоги вроде
-- node_modules не мешают, потому что читаются только при разворачивании.
local ALWAYS_HIDDEN = { [".git"] = true, [".DS_Store"] = true }

-- ── Утилиты путей ───────────────────────────────────────────────────────────

local function abs(path)
  return (vim.fn.fnamemodify(path, ":p"):gsub("/+$", ""))
end

local function join(dir, name)
  return (dir:gsub("/+$", "")) .. "/" .. name
end

local function parent(path)
  return vim.fn.fnamemodify(path, ":h")
end

---@return boolean лежит ли path внутри dir
local function inside(path, dir)
  return path == dir or path:sub(1, #dir + 1) == dir .. "/"
end

-- ── Чтение файловой системы ─────────────────────────────────────────────────

local function scan(dir)
  local fd = uv.fs_scandir(dir)
  if not fd then
    return {}
  end
  local items = {}
  while true do
    local name, kind = uv.fs_scandir_next(fd)
    if not name then
      break
    end
    if not ALWAYS_HIDDEN[name] and (show_hidden or name:sub(1, 1) ~= ".") then
      local path = join(dir, name)
      local link = kind == "link"
      if link then
        -- Тип симлинка отдаёт только stat: без него папка-симлинк не разворачивается.
        local st = uv.fs_stat(path)
        kind = st and st.type or "file"
      end
      items[#items + 1] = { name = name, path = path, type = kind, link = link }
    end
  end
  table.sort(items, function(a, b)
    local ad, bd = a.type == "directory", b.type == "directory"
    if ad ~= bd then
      return ad
    end
    local al, bl = a.name:lower(), b.name:lower()
    if al == bl then
      return a.name < b.name
    end
    return al < bl
  end)
  return items
end

local function collect(dir, depth, out)
  for _, item in ipairs(scan(dir)) do
    out[#out + 1] = { path = item.path, name = item.name, type = item.type, depth = depth, link = item.link }
    if item.type == "directory" and expanded[item.path] then
      collect(item.path, depth + 1, out)
    end
  end
end

-- ── Отрисовка ───────────────────────────────────────────────────────────────

local function valid()
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

local function render()
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end

  rows = { { path = root, name = vim.fn.fnamemodify(root, ":t"), type = "root", depth = 0 } }
  collect(root, 1, rows)

  local lines, marks = {}, {}
  for i, node in ipairs(rows) do
    local text, prefix, name_hl
    if node.type == "root" then
      prefix, text, name_hl = "", node.name, "ExplorerRoot"
    elseif node.type == "directory" then
      prefix = ("  "):rep(node.depth - 1) .. (expanded[node.path] and "▾ " or "▸ ")
      text = prefix .. node.name .. "/"
      name_hl = "ExplorerDir"
    else
      -- Файлы выравниваются под именами папок: две колонки вместо стрелки.
      prefix = ("  "):rep(node.depth - 1) .. "  "
      text = prefix .. node.name
      name_hl = node.link and "ExplorerLink" or "ExplorerFile"
    end

    local name_to = #text
    local mark = git[node.path]
    if mark then
      text = text .. " " .. mark
    end

    lines[i] = text
    marks[i] = { indent = #(("  "):rep(math.max(node.depth - 1, 0))), name_from = #prefix, name_to = name_to, hl = name_hl }
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for i, m in ipairs(marks) do
    local line = i - 1
    if m.indent < m.name_from then
      vim.api.nvim_buf_set_extmark(buf, ns, line, m.indent, { end_col = m.name_from, hl_group = "ExplorerArrow" })
    end
    vim.api.nvim_buf_set_extmark(buf, ns, line, m.name_from, { end_col = m.name_to, hl_group = m.hl })
    if #lines[i] > m.name_to then
      vim.api.nvim_buf_set_extmark(buf, ns, line, m.name_to, { end_col = #lines[i], hl_group = "ExplorerGit" })
    end
    -- Текущий файл — фоном на всю строку: заметно, но не инверсия (красный в этом
    -- конфиге значит "ключевое слово", см. modules/colors.lua).
    if current and rows[i].path == current then
      vim.api.nvim_buf_set_extmark(buf, ns, line, 0, { line_hl_group = "ExplorerCurrent", hl_eol = true })
    end
  end
end

---@return integer|nil номер строки с этим путём
local function row_of(path)
  for i, node in ipairs(rows) do
    if node.path == path then
      return i
    end
  end
end

local function focus_row(path)
  local i = path and row_of(path)
  if i and valid() then
    pcall(vim.api.nvim_win_set_cursor, win, { i, 0 })
  end
end

-- ── Git-статус ──────────────────────────────────────────────────────────────

-- Статус различает форма значка, а не цвет — тем же принципом, что и знаки
-- gitsigns в этом конфиге (см. modules/colors.lua).
local WORKTREE = { M = "~", D = "-", T = "~", A = "+" }
local INDEX = { M = "+", A = "+", D = "-", R = "»", C = "»", T = "+" }

local function status_mark(x, y)
  if x == "?" then
    return "?"
  end
  if x == "U" or y == "U" or (x == "A" and y == "A") or (x == "D" and y == "D") then
    return "!"
  end
  if y ~= " " and y ~= "" then
    return WORKTREE[y] or "~"
  end
  return INDEX[x] or "~"
end

local function parse_status(out)
  local new = {}
  local fields = vim.split(out, "\0", { plain = true })
  local i = 1
  while i <= #fields do
    local entry = fields[i]
    i = i + 1
    if #entry >= 4 then
      local x, y, rel = entry:sub(1, 1), entry:sub(2, 2), entry:sub(4)
      if x == "R" or x == "C" then
        i = i + 1 -- за переименованием идёт вторым полем старый путь
      end
      local path = abs(join(git_top, rel))
      new[path] = status_mark(x, y)
      -- Родительские каталоги помечаем "грязными", чтобы изменение было видно,
      -- когда папка свёрнута.
      local dir = parent(path)
      while #dir > #git_top and not new[dir] do
        new[dir] = "~"
        dir = parent(dir)
      end
    end
  end
  return new
end

local function git_refresh()
  if git_busy then
    git_pending = true -- запрос во время выполнения не теряем, иначе значки останутся старыми
    return
  end
  git_busy = true
  vim.system({ "git", "-C", root, "rev-parse", "--show-toplevel" }, { text = true }, function(top)
    vim.schedule(function()
      if top.code ~= 0 then -- не репозиторий: значков просто нет
        git_busy, git_pending, git, git_top = false, false, {}, nil
        render()
        return
      end
      git_top = abs(vim.trim(top.stdout or ""))
      vim.system(
        { "git", "-C", root, "status", "--porcelain=v1", "-z", "--untracked-files=normal" },
        { text = true },
        function(st)
          vim.schedule(function()
            git_busy = false
            git = st.code == 0 and parse_status(st.stdout or "") or {}
            render()
            if git_pending then
              git_pending = false
              git_refresh()
            end
          end)
        end
      )
    end)
  end)
end

-- ── Открытие файлов ─────────────────────────────────────────────────────────

-- Единственное место, где ищется окно редактора, — tabline.goto_editor():
-- он же уводит из панели H/J и gn/gp/gw.
local function open_path(path, cmd)
  require("modules.tabline").goto_editor()
  vim.cmd((cmd or "edit") .. " " .. vim.fn.fnameescape(path))
end

-- ── Действия в панели ───────────────────────────────────────────────────────

local function node_at_cursor()
  if not valid() then
    return nil
  end
  return rows[vim.api.nvim_win_get_cursor(win)[1]]
end

---Каталог, относительно которого работают a/r/d для данной ноды.
local function dir_of(node)
  if not node then
    return root
  end
  if node.type == "root" then
    return root
  end
  if node.type == "directory" then
    return node.path
  end
  return parent(node.path)
end

local function enter(node)
  node = node or node_at_cursor()
  if not node then
    return
  end
  if node.type == "root" then
    expanded = {} -- свернуть всё
    render()
  elseif node.type == "directory" then
    expanded[node.path] = not expanded[node.path] or nil
    render()
    focus_row(node.path)
  else
    open_path(node.path)
  end
end

local function collapse(node)
  node = node or node_at_cursor()
  if not node or node.type == "root" then
    return
  end
  if node.type == "directory" and expanded[node.path] then
    expanded[node.path] = nil
    render()
    focus_row(node.path)
    return
  end
  local up = parent(node.path)
  if up == root then
    focus_row(root)
    return
  end
  expanded[up] = nil
  render()
  focus_row(up)
end

local function expand_to(path)
  local dir = parent(path)
  while #dir > #root and inside(dir, root) do
    expanded[dir] = true
    dir = parent(dir)
  end
end

-- Буферы, открытые из переименованного файла или каталога, должны переехать
-- вместе с ним: имя на диске уже другое, содержимое то же.
local function rebind_buffers(old, new)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(b)
    if name ~= "" and inside(name, old) then
      vim.api.nvim_buf_set_name(b, new .. name:sub(#old + 1))
      vim.api.nvim_buf_call(b, function()
        vim.cmd("silent! edit!")
      end)
    end
  end
end

local function wipe_buffers(path)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(b)
    if name ~= "" and inside(name, path) then
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
  end
end

local function create()
  local base = dir_of(node_at_cursor())
  local input = vim.fn.input("Создать (путь с / на конце — каталог): ", vim.fn.fnamemodify(base, ":~") .. "/")
  if input == "" then
    return
  end
  local path = abs(vim.fn.expand(input))
  local isdir = input:sub(-1) == "/"
  vim.fn.mkdir(isdir and path or parent(path), "p")
  if not isdir then
    local fd = uv.fs_open(path, "a", 420) -- 0644; "a" не затирает существующий файл
    if fd then
      uv.fs_close(fd)
    end
  end
  expand_to(path)
  if isdir then
    expanded[path] = true
  end
  render()
  focus_row(path)
  git_refresh()
end

local function rename()
  local node = node_at_cursor()
  if not node or node.type == "root" then
    return
  end
  local input = vim.fn.input("Переименовать: ", vim.fn.fnamemodify(node.path, ":~"))
  if input == "" then
    return
  end
  local new = abs(vim.fn.expand(input))
  if new == node.path then
    return
  end
  vim.fn.mkdir(parent(new), "p")
  local ok, err = uv.fs_rename(node.path, new)
  if not ok then
    vim.notify("explorer: не переименовать — " .. tostring(err), vim.log.levels.ERROR)
    return
  end
  if expanded[node.path] then
    expanded[node.path], expanded[new] = nil, true
  end
  rebind_buffers(node.path, new)
  expand_to(new)
  render()
  focus_row(new)
  git_refresh()
end

local function remove()
  local node = node_at_cursor()
  if not node or node.type == "root" then
    return
  end
  local what = node.type == "directory" and "каталог" or "файл"
  -- input, а не confirm(): у confirm горячей буквой стала бы кириллическая "Д",
  -- которую на латинской раскладке не набрать.
  local answer = vim.fn.input("Удалить " .. what .. " " .. node.name .. "? [y/N]: ")
  if answer:lower() ~= "y" then
    return
  end
  local ok
  if node.type == "directory" then
    ok = vim.fn.delete(node.path, "rf") == 0
  else
    ok = uv.fs_unlink(node.path) and true or false
  end
  if not ok then
    vim.notify("explorer: не удалить " .. node.path, vim.log.levels.ERROR)
    return
  end
  wipe_buffers(node.path)
  expanded[node.path] = nil
  render()
  git_refresh()
end

local function yank(absolute)
  local node = node_at_cursor()
  if not node then
    return
  end
  local text = absolute and node.path or vim.fn.fnamemodify(node.path, ":.")
  vim.fn.setreg("+", text)
  vim.notify(text)
end

-- ── Окно и буфер ────────────────────────────────────────────────────────────

local function keymaps(b)
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = b, silent = true, nowait = true, desc = "explorer: " .. desc })
  end

  map("<CR>", enter, "открыть файл / развернуть папку")
  map("l", enter, "открыть файл / развернуть папку")
  map("o", enter, "открыть файл / развернуть папку")
  map("<2-LeftMouse>", enter, "открыть файл / развернуть папку")
  map("h", collapse, "свернуть папку / к родителю")
  map("<C-v>", function()
    local node = node_at_cursor()
    if node and node.type == "file" then
      open_path(node.path, "vsplit")
    end
  end, "открыть в вертикальном сплите")
  map("R", function()
    render()
    git_refresh()
  end, "перечитать дерево")
  map("gh", function()
    show_hidden = not show_hidden
    render()
  end, "точки: показать/скрыть")
  map("a", create, "создать файл/каталог")
  map("r", rename, "переименовать")
  map("d", remove, "удалить")
  map("y", function()
    yank(false)
  end, "путь от корня проекта в +")
  map("Y", function()
    yank(true)
  end, "абсолютный путь в +")
  map("q", function()
    M.close()
  end, "закрыть панель")
end

local function ensure_buf()
  if buf and vim.api.nvim_buf_is_valid(buf) then
    return buf
  end
  buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].buflisted = false -- панель не должна попадать в полоску вкладок
  vim.bo[buf].filetype = "explorer"
  vim.bo[buf].modifiable = false
  keymaps(buf)
  return buf
end

---@param focus boolean|nil встать в панель после открытия
function M.open(focus)
  if valid() then
    if focus then
      vim.api.nvim_set_current_win(win)
    end
    return
  end
  local prev = vim.api.nvim_get_current_win()
  if vim.bo[vim.api.nvim_win_get_buf(prev)].filetype ~= "explorer" then
    snapshot_editor(prev)
  end
  vim.cmd("topleft " .. M.width .. "vsplit")
  win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, ensure_buf())

  for name, value in pairs(M.window_options) do
    vim.wo[win][name] = value
  end
  vim.api.nvim_win_set_width(win, M.width)

  if not current then
    local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(prev))
    if name ~= "" then
      current = abs(name)
    end
  end
  if current and inside(current, root) then
    expand_to(current)
  end
  render()
  focus_row(current)
  git_refresh()

  if not focus and vim.api.nvim_win_is_valid(prev) then
    vim.api.nvim_set_current_win(prev)
  end
end

function M.close()
  if valid() then
    pcall(vim.api.nvim_win_close, win, true)
  end
  win = nil
end

function M.resize()
  if valid() then
    vim.api.nvim_win_set_width(win, M.width)
  end
end

---@return integer 0, если панель закрыта — на столько полоска вкладок сдвигается вправо
function M.offset()
  return valid() and vim.api.nvim_win_get_width(win) + 1 or 0
end

function M.set_root(dir)
  root = abs(dir)
  expanded = {}
  git, git_top = {}, nil
  if valid() then -- открытую панель надо перечитать, иначе в ней останется старый корень
    if current and inside(current, root) then
      expand_to(current)
    end
    render()
    focus_row(current)
    git_refresh()
  end
end

-- ,e — честный toggle, как Ctrl+B в VS Code: закрывает панель откуда угодно,
-- в том числе из редактируемого файла, и открывает её сразу с курсором внутри.
-- Раньше ,e снаружи переводил фокус в дерево, и закрытие "с файла" стоило двух
-- нажатий. Войти в уже открытую панель — ,E (или <C-w>h).
function M.toggle()
  if valid() then
    M.close()
  else
    M.open(true)
  end
end

-- ,E: раскрыть путь до текущего файла и встать на него.
function M.reveal()
  local name = vim.api.nvim_buf_get_name(0)
  if name ~= "" and vim.bo.buftype == "" then
    current = abs(name)
  end
  M.open(true)
  if current and inside(current, root) then
    expand_to(current)
    render()
    focus_row(current)
  end
  if valid() then
    vim.api.nvim_set_current_win(win)
  end
end

vim.keymap.set("n", ",e", M.toggle, { silent = true, desc = "explorer: открыть/закрыть панель" })
vim.keymap.set("n", ",E", M.reveal, { silent = true, desc = "explorer: показать текущий файл" })

-- ── Автокоманды ─────────────────────────────────────────────────────────────

local group = vim.api.nvim_create_augroup("explorer", { clear = true })

-- Подсветка текущего файла и авто-раскрытие пути до него. Закрытую панель это
-- не открывает — иначе сломался бы главный пункт: закрыл на одном файле,
-- перешёл на другой, панель по-прежнему закрыта.
local function track()
  local b = vim.api.nvim_get_current_buf()
  if not vim.bo[b].buflisted or vim.bo[b].buftype ~= "" then
    return -- панель, попапы и quickfix подсветку не сбивают
  end
  local name = vim.api.nvim_buf_get_name(b)
  if name == "" then
    return
  end
  if vim.fn.isdirectory(name) == 1 then
    return -- буфер каталога разбирает hijack_dir, подсветку файла он не значит
  end
  local path = abs(name)
  if path == current then
    return
  end
  current = path
  if not valid() then
    return
  end
  if inside(path, root) then
    expand_to(path)
  end
  render()
  focus_row(path)
end

vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, { group = group, callback = track })

vim.api.nvim_create_autocmd("BufWritePost", {
  group = group,
  callback = function()
    if valid() then
      git_refresh()
    end
  end,
})

vim.api.nvim_create_autocmd("DirChanged", {
  group = group,
  callback = function()
    M.set_root(vim.fn.getcwd())
    if valid() then
      render()
      git_refresh()
    end
  end,
})

-- Каталог как буфер: netrw отключён (global.lua), поэтому `:e src/` и
-- `nvim .` иначе оставили бы пустой буфер с именем каталога.
local function hijack_dir(bufnr, cd)
  local dir = abs(vim.api.nvim_buf_get_name(bufnr))
  if cd then
    vim.cmd.cd(dir)
  end
  M.set_root(dir)
  vim.cmd.enew()
  pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  M.open(true)
end

vim.api.nvim_create_autocmd("VimEnter", {
  group = group,
  callback = function()
    local b = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(b)
    if name ~= "" and vim.fn.isdirectory(name) == 1 then
      hijack_dir(b, true) -- `nvim .` / `nvim ~/proj`: каталог становится корнем
    else
      -- Без аргументов встаём в дерево, с файлом — оставляем курсор в файле.
      M.open(vim.fn.argc() == 0)
    end
  end,
})

vim.api.nvim_create_autocmd("BufEnter", {
  group = group,
  callback = function(args)
    if vim.v.vim_did_enter == 0 then
      return -- старт разбирает VimEnter выше
    end
    local name = vim.api.nvim_buf_get_name(args.buf)
    if name ~= "" and vim.bo[args.buf].buftype == "" and vim.fn.isdirectory(name) == 1 then
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(args.buf) then
          hijack_dir(args.buf, false)
        end
      end)
    end
  end,
})

-- Обычный буфер, попавший в окно панели (Telescope, запущенный из дерева, gf,
-- :e), — возвращаем панель на место, а файл открываем в редакторе.
vim.api.nvim_create_autocmd("BufWinEnter", {
  group = group,
  callback = function(args)
    if not valid() or vim.api.nvim_get_current_win() ~= win or args.buf == buf then
      return
    end
    if not vim.bo[args.buf].buflisted then
      return
    end
    vim.api.nvim_win_set_buf(win, ensure_buf())
    require("modules.tabline").goto_editor()
    vim.api.nvim_set_current_buf(args.buf)
    -- Побывав в окне панели, буфер запомнил её оконные опции (nvim держит их
    -- per-buffer: `:h wininfo`), и в редакторе они восстанавливались поверх
    -- нормальных — файл открывался без нумерации строк, без signcolumn и с фоном
    -- панели. Возвращаем эталон явно.
    M.restore_editor_window(vim.api.nvim_get_current_win())
  end,
})

-- :q в последнем окне с файлом оставил бы панель на весь экран, и Neovim не вышел
-- бы. Обычный :q сюда уже не доходит — он закрывает файл (tabline.M.quit), —
-- но настоящий выход (последняя вкладка, :qa, <C-w>c) идёт через этот QuitPre.
vim.api.nvim_create_autocmd("QuitPre", {
  group = group,
  callback = function()
    if vim.bo.filetype == "explorer" then
      return
    end
    local editors, panels = 0, {}
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_win_get_config(w).relative == "" then
        if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "explorer" then
          panels[#panels + 1] = w
        else
          editors = editors + 1
        end
      end
    end
    if editors == 1 then
      for _, w in ipairs(panels) do
        pcall(vim.api.nvim_win_close, w, true)
      end
      win = nil
    end
  end,
})

-- Страховка для всех остальных путей в то же состояние (<C-w>c и прочее):
-- панель не должна оставаться единственным окном.
vim.api.nvim_create_autocmd("WinClosed", {
  group = group,
  callback = function()
    vim.schedule(function()
      local wins = {}
      for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_config(w).relative == "" then
          wins[#wins + 1] = w
        end
      end
      if #wins ~= 1 or vim.bo[vim.api.nvim_win_get_buf(wins[1])].filetype ~= "explorer" then
        return
      end
      require("modules.tabline").open_editor_win()
    end)
  end,
})

return M
