-- Полоска открытых файлов сверху — аналог вкладок VS Code — и навигация по ним.
--
-- Табы vim здесь не используются вообще. Панель дерева живёт внутри раскладки
-- окон одной табы, и одной на все табы она быть не может: каждая таба — своя
-- раскладка, поэтому <C-t> раньше плодил табу с собственной копией дерева.
-- Модель как в VS Code: одна таба, одна панель, "вкладка" — это буфер.
--
-- Модуль возвращает M: его функции переиспользуют remap.lua, help.lua и tree.lua.

local M = {}

-- ── Навигация ───────────────────────────────────────────────────────────────
-- :bnext / :bprevious / :Bclose, нажатые внутри панели, подменили бы буфер
-- в самой панели, а не в редакторе. Поэтому все они сначала уходят из дерева.

-- Пустое окно редактора справа от панели. Ширину панели после split возвращает
-- сам плагин: resize() без аргумента ставит ей настроенные 34 колонки, иначе
-- split делит экран пополам.
function M.open_editor_win()
  vim.cmd("botright vnew")
  pcall(function() require("nvim-tree.api").tree.resize() end)
end

---@return boolean всегда true: окно редактора при необходимости создаётся
function M.goto_editor()
  if vim.bo.filetype ~= "NvimTree" then
    return true
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    -- relative == "" отсекает плавающие окна (попапы cmp, telescope, blame)
    if vim.api.nvim_win_get_config(win).relative == "" and vim.bo[buf].filetype ~= "NvimTree" then
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
  if M.goto_editor() then vim.cmd("bnext") end
end

function M.prev()
  if M.goto_editor() then vim.cmd("bprevious") end
end

---@param bufnr integer|nil текущий буфер, если не задан
function M.close(bufnr)
  if not M.goto_editor() then return end
  -- :Bclose (modules/help.lua) удаляет буфер, не трогая раскладку окон, —
  -- именно это нужно, чтобы панель осталась на месте.
  vim.cmd("Bclose" .. (bufnr and (" " .. bufnr) or ""))
end

-- ── Отрисовка ───────────────────────────────────────────────────────────────
-- tabline пересчитывается на каждую перерисовку экрана, то есть десятки раз
-- в секунду при обычном скролле. Поэтому строку собираем один раз и держим
-- в кеше, а сбрасываем его только по событиям, которые реально её меняют.

local cache = nil
-- Последний "настоящий" буфер: пока фокус в панели, подсвеченной должна
-- оставаться вкладка редактора (так же ведёт себя VS Code).
local current = vim.api.nvim_get_current_buf()

local function build()
  local infos = vim.fn.getbufinfo({ buflisted = 1 })
  if #infos == 0 then
    return "%#TabLineFill#"
  end

  -- Одинаковые basename (в NestJS это сплошь index.ts) различаем именем
  -- родительской папки — user/index.ts.
  -- Пустой безымянный буфер (стартовое окно редактора, :enew) вкладкой не
  -- считается, пока в него не написали, — иначе на старте висит [No Name].
  local shown = {}
  for _, b in ipairs(infos) do
    if b.name ~= "" or b.changed == 1 then
      shown[#shown + 1] = b
    end
  end
  infos = shown
  if #infos == 0 then
    return "%#TabLineFill#"
  end

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

    local width = vim.fn.strwidth(label)
    items[i] = { bufnr = b.bufnr, label = label, width = width }
    total = total + width
    if b.bufnr == current then cur = i end
  end

  -- Вкладок больше, чем ширины экрана: показываем окно вокруг текущей,
  -- обрезанные края помечаем ‹ и ›.
  local first, last = 1, #items
  if total > vim.o.columns then
    local avail = vim.o.columns - 2 -- место под оба маркера
    first, last = cur, cur
    local used = items[cur].width
    while true do
      local grew = false
      if last < #items and used + items[last + 1].width <= avail then
        last = last + 1
        used = used + items[last].width
        grew = true
      end
      if first > 1 and used + items[first - 1].width <= avail then
        first = first - 1
        used = used + items[first].width
        grew = true
      end
      if not grew then break end
    end
  end

  local out = {}
  if first > 1 then
    out[#out + 1] = "%#TabLine#‹"
  end
  for i = first, last do
    local it = items[i]
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

vim.api.nvim_create_autocmd(
  { "BufAdd", "BufDelete", "BufWipeout", "BufFilePost", "BufModifiedSet", "BufWritePost", "VimResized" },
  { group = group, callback = function() cache = nil end }
)

vim.api.nvim_create_autocmd("BufEnter", {
  group = group,
  callback = function(args)
    -- Буфер дерева nolisted, поэтому вход в панель не сбивает подсветку.
    if vim.bo[args.buf].buflisted then
      current = args.buf
    end
    cache = nil
  end,
})

vim.opt.showtabline = 2 -- полоска всегда видна, даже когда открыт один файл
vim.o.tabline = "%!v:lua.__tabline_render()"

return M
