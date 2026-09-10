-- Полоска открытых файлов сверху — аналог вкладок VS Code — и навигация по ним.
--
-- Табы vim здесь не используются вообще. Панель дерева живёт внутри раскладки
-- окон одной табы, и одной на все табы она быть не может: каждая таба — своя
-- раскладка. Модель как в VS Code: одна таба, одна панель, "вкладка" — это буфер.
--
-- Модуль возвращает M: его функции переиспользуют remap.lua, help.lua и
-- explorer.lua. explorer тянется отсюда только внутри функций — так модули
-- требуют друг друга без цикла (в modules/init.lua tabline идёт первым).

local M = {}

local EXPLORER = "explorer"

local function explorer()
  local ok, mod = pcall(require, "modules.explorer")
  return ok and mod or nil
end

-- ── Навигация ───────────────────────────────────────────────────────────────
-- :bnext / :bprevious / :Bclose, нажатые внутри панели, подменили бы буфер
-- в самой панели, а не в редакторе. Поэтому все они сначала уходят из дерева.

-- Пустое окно редактора справа от панели. Ширину панели после split возвращает
-- сама панель: иначе split делит экран пополам.
function M.open_editor_win()
  vim.cmd("botright vnew")
  local mod = explorer()
  -- `vnew` копирует оконные опции текущего окна, а зовут эту функцию из панели:
  -- без восстановления новое окно редактора получало бы её nonumber, signcolumn=no,
  -- nospell и её же winhighlight (фон панели). Эталон держит сама панель.
  if mod then
    mod.restore_editor_window(vim.api.nvim_get_current_win())
    mod.resize()
  end
end

---@return boolean всегда true: окно редактора при необходимости создаётся
function M.goto_editor()
  if vim.bo.filetype ~= EXPLORER then
    return true
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    -- relative == "" отсекает плавающие окна (попапы cmp, telescope, blame)
    if vim.api.nvim_win_get_config(win).relative == "" and vim.bo[buf].filetype ~= EXPLORER then
      vim.api.nvim_set_current_win(win)
      return true
    end
  end
  -- Панель осталась единственным окном: заводим редактор справа, иначе H/J и
  -- gn/gp/gw молча ничего не делали бы.
  M.open_editor_win()
  return true
end

function M.next()
  if M.goto_editor() then
    vim.cmd("bnext")
  end
end

function M.prev()
  if M.goto_editor() then
    vim.cmd("bprevious")
  end
end

-- Буферы, которые видны вкладками. Пустой безымянный буфер (стартовое окно
-- редактора, :enew) вкладкой не считается, пока в него не написали, — иначе на
-- старте висит [No Name]. Отсюда же берёт список :q, чтобы "последний файл"
-- значило то же самое, что видно в полоске.
local function tabs()
  local out = {}
  for _, b in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    if b.name ~= "" or b.changed == 1 then
      out[#out + 1] = b
    end
  end
  return out
end

---@param bufnr integer|nil текущий буфер, если не задан
---@param bang string|nil "!" — закрыть, не сохраняя
function M.close(bufnr, bang)
  if not M.goto_editor() then
    return
  end
  -- :Bclose (modules/help.lua) удаляет буфер, не трогая раскладку окон, —
  -- именно это нужно, чтобы панель осталась на месте, а закрытие файла было
  -- одним действием.
  vim.cmd("Bclose" .. (bang or "") .. (bufnr and (" " .. bufnr) or ""))
end

-- ── :q закрывает файл, а не окно ────────────────────────────────────────────
-- В vim :q закрывает окно, и при открытой панели (или любом втором окне) это
-- выглядит как "меня перекинуло на другой файл, а вкладка осталась". В VS Code
-- Ctrl+W закрывает вкладку — здесь то же самое: :q убирает файл из полоски,
-- раскладку не трогает. Окно-сплит (<C-v> из дерева) закрывается <C-w>c.

---Однострочная ошибка вместо lua-трейсбека: :q живёт в колбэке команды, и
---упавший vim.cmd печатает стек на пол-экрана с "Press ENTER", после которого
---сессия выглядит зависшей.
local function fail(err)
  local msg = tostring(err):gsub("\n.*", ""):gsub("^Vim%b():", "")
  vim.api.nvim_echo({ { msg, "ErrorMsg" } }, true, {})
end

local function try(cmd)
  local ok, err = pcall(vim.cmd, cmd)
  if not ok then
    fail(err)
  end
  return ok
end

---@param bang string "!" — не сохранять изменения
---@param write boolean|nil сначала записать буфер (:wq, :x)
function M.quit(bang, write)
  if write and not try("update" .. bang) then -- :x — пишет только изменённый буфер
    return
  end
  -- Панель, help, quickfix, terminal, плавающие окна: :q остаётся :q.
  if
    vim.bo.buftype ~= ""
    or not vim.bo.buflisted
    or vim.api.nvim_win_get_config(0).relative ~= ""
  then
    try("quit" .. bang)
    return
  end
  -- Проверяем сами и до всего остального: :qa на изменённом буфере кинул бы
  -- ошибку из колбэка, а Bclose посоветовал бы :Bclose! — пользователь набрал
  -- :q, подсказывать ему надо про :q!.
  if bang == "" and vim.bo.modified then
    vim.api.nvim_echo(
      { { "E37: No write since last change (add ! to override)", "ErrorMsg" } },
      true,
      {}
    )
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  local others = 0
  for _, b in ipairs(tabs()) do
    if b.bufnr ~= buf then
      others = others + 1
    end
  end
  if others == 0 then
    -- Вкладок больше нет — выходим из Neovim, и именно :qa, а не :quit.
    -- :quit закрывает окно, то есть зависит от раскладки: при лишнем окне
    -- редактора он схлопывал сплит ("файл не закрылся"), а оставшись
    -- единственным — ронял управление в QuitPre/WinClosed, где панель
    -- закрывалась, снова открывалось пустое окно, и на один файл уходило
    -- четыре :q. :qa от раскладки не зависит и делает то же самое с первого раза.
    try("quitall" .. bang)
    return
  end
  M.close(buf, bang)
  -- Bclose возвращает курсор по номеру окна, а номера после закрытия могли
  -- съехать: если он оказался в панели, следующий :q закрыл бы панель вместо
  -- файла — ровно то, что выглядит как "нажал :q, а закрылся сайдбар".
  M.goto_editor()
end

vim.api.nvim_create_user_command("Q", function(a)
  M.quit(a.bang and "!" or "")
end, { bang = true, desc = "закрыть файл (вкладку), как Ctrl+W в VS Code" })

vim.api.nvim_create_user_command("Wq", function(a)
  M.quit(a.bang and "!" or "", true)
end, { bang = true, desc = "записать и закрыть файл (вкладку)" })

-- Сокращение срабатывает, только когда набранная строка — ровно `q`/`wq`/`x`:
-- `:qa`, `:1,5q`, `:g/x/q`, `:copen`-подобные остаются собой. `!` набирается
-- уже после раскрытия, поэтому `:q!` превращается в `:Q!`.
local function cabbrev(lhs, rhs)
  vim.cmd(
    string.format(
      "cnoreabbrev <expr> %s (getcmdtype() ==# ':' && getcmdline() ==# '%s') ? '%s' : '%s'",
      lhs,
      lhs,
      rhs,
      lhs
    )
  )
end

cabbrev("q", "Q")
cabbrev("wq", "Wq")
cabbrev("x", "Wq")

-- ── Отрисовка ───────────────────────────────────────────────────────────────
-- tabline пересчитывается на каждую перерисовку экрана, то есть десятки раз
-- в секунду при обычном скролле. Поэтому строку собираем один раз и держим
-- в кеше, а сбрасываем его только по событиям, которые реально её меняют.

local cache = nil
-- Последний "настоящий" буфер: пока фокус в панели, подсвеченной должна
-- оставаться вкладка редактора (так же ведёт себя VS Code).
local current = vim.api.nvim_get_current_buf()

---Шапка панели в левом краю полоски. Надпись постоянная — как заголовок секции
---в VS Code; имя проекта сюда не пишем, оно и так первой строкой в самой панели.
---Вкладки идут сразу за ней, а не с колонки редактора: добивать шапку пробелами
---на всю ширину панели (34 колонки) значило держать между надписью и первой
---вкладкой два десятка пустых клеток.
local TITLE = " EXPLORER"

local function build()
  -- Шапка есть, только пока открыта панель: это её заголовок.
  local mod = explorer()
  local title = (mod and mod.offset() > 0) and TITLE or nil
  local title_w = title and (vim.fn.strwidth(title) + 1) or 0 -- +1 на разделитель

  local infos = tabs()
  if #infos == 0 then
    return title and ("%#TabLineTitle#" .. title .. "%#TabLineFill#") or "%#TabLineFill#"
  end

  -- Одинаковые basename (в NestJS это сплошь index.ts) различаем именем
  -- родительской папки — user/index.ts.
  local seen = {}
  for _, b in ipairs(infos) do
    local tail = vim.fn.fnamemodify(b.name, ":t")
    seen[tail] = (seen[tail] or 0) + 1
  end

  local items, cur, total = {}, 1, 0
  for i, b in ipairs(infos) do
    local label
    if b.name == "" then
      label = "[No Name]"
    else
      local tail = vim.fn.fnamemodify(b.name, ":t")
      label = seen[tail] > 1 and (vim.fn.fnamemodify(b.name, ":h:t") .. "/" .. tail) or tail
    end
    if b.changed == 1 then
      label = label .. " +" -- Nerd Font в терминале нет, метка текстовая
    end
    label = " " .. label .. " "

    -- Между вкладками одна колонка: разделитель │ либо пустое место у активной.
    local width = vim.fn.strwidth(label) + (i > 1 and 1 or 0)
    items[i] = { bufnr = b.bufnr, label = label, width = width }
    total = total + width
    if b.bufnr == current then
      cur = i
    end
  end

  local avail = vim.o.columns - title_w

  -- Вкладок больше, чем ширины экрана: показываем окно вокруг текущей,
  -- обрезанные края помечаем ‹ и ›.
  local first, last = 1, #items
  if total > avail then
    local room = avail - 2 -- место под оба маркера
    first, last = cur, cur
    local used = items[cur].width
    while true do
      local grew = false
      if last < #items and used + items[last + 1].width <= room then
        last = last + 1
        used = used + items[last].width
        grew = true
      end
      if first > 1 and used + items[first - 1].width <= room then
        first = first - 1
        used = used + items[first].width
        grew = true
      end
      if not grew then
        break
      end
    end
  end

  local out = { "%#TabLineFill#" }
  if title then
    out[#out + 1] = "%#TabLineTitle#" .. title .. "%#TabLineSep#│"
  end
  if first > 1 then
    out[#out + 1] = "%#TabLine#‹"
  end
  for i = first, last do
    local it = items[i]
    if i > first then
      -- Разделитель только между двумя неактивными вкладками: у активной края
      -- и так видно по фону.
      if it.bufnr == current or items[i - 1].bufnr == current then
        out[#out + 1] = "%#TabLineFill# "
      else
        out[#out + 1] = "%#TabLineSep#│"
      end
    end
    -- %N@func@ ... %X — кликабельная область (mouse=a включён в set.lua)
    out[#out + 1] = string.format("%%%d@v:lua.__tabline_click@", it.bufnr)
    out[#out + 1] = it.bufnr == current and "%#TabLineSel#" or "%#TabLine#"
    out[#out + 1] = it.label:gsub("%%", "%%%%") -- % в имени файла не должен стать форматом
    out[#out + 1] = "%X"
  end
  if last < #items then
    out[#out + 1] = "%#TabLine#›"
  end
  out[#out + 1] = "%#TabLineFill#"

  return table.concat(out)
end

function M.render()
  cache = cache or build()
  return cache
end

-- v:lua умеет звать только глобальные функции: v:lua.require'...'.render()
-- в выражении tabline не разбирается.
_G.__tabline_render = M.render

---@param bufnr integer из %N@...@ — minwid
function _G.__tabline_click(bufnr, _, button, _)
  if button == "m" then
    M.close(bufnr) -- средняя кнопка — закрыть вкладку, как в браузере
  elseif M.goto_editor() then
    vim.cmd("buffer " .. bufnr)
  end
end

local group = vim.api.nvim_create_augroup("tabline", { clear = true })

vim.api.nvim_create_autocmd({
  "BufAdd",
  "BufDelete",
  "BufWipeout",
  "BufFilePost",
  "BufModifiedSet",
  "BufWritePost",
  "VimResized",
  -- Открытие/закрытие панели меняет отступ полоски слева.
  "WinNew",
  "WinClosed",
  "WinResized",
}, {
  group = group,
  callback = function()
    cache = nil
  end,
})

vim.api.nvim_create_autocmd("BufEnter", {
  group = group,
  callback = function(args)
    -- Буфер панели nolisted, поэтому вход в неё не сбивает подсветку.
    if vim.bo[args.buf].buflisted then
      current = args.buf
    end
    cache = nil
  end,
})

vim.opt.showtabline = 2 -- полоска всегда видна, даже когда открыт один файл
vim.o.tabline = "%!v:lua.__tabline_render()"

return M
