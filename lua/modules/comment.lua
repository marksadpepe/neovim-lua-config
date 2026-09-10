-- Комментирование — встроенное в Neovim 0.10: gcc на строку, gc на motion/выделение.
-- Встроенный вариант берёт commentstring как есть, а он идёт без пробела ("//%s"),
-- поэтому нормализуем его — это то, что раньше делал NERDSpaceDelims = 1.
local function normalize(cs)
  if type(cs) ~= "string" then
    return nil
  end
  local left, right = cs:match("^(.*)%%s(.*)$")
  if not left then
    return nil
  end
  left, right = vim.trim(left), vim.trim(right)
  if left ~= "" then
    left = left .. " "
  end
  if right ~= "" then
    right = " " .. right
  end
  return left .. "%s" .. right
end

vim.api.nvim_create_autocmd("FileType", {
  desc = "Пробел после делимитера комментария",
  callback = function(args)
    local cs = normalize(vim.bo[args.buf].commentstring)
    if cs then
      vim.bo[args.buf].commentstring = cs
    end
  end,
})

-- Починка commentstring прямо перед комментированием. Значение живёт в опциях
-- буфера, и его сносит любой повторный прогон ftplugin, пришедшийся на чужой
-- буфер: `:doautocmd FileType python` и nvim_exec_autocmds{event="FileType",
-- buffer=…} выполняются в текущем буфере, поэтому в открытом .ts commentstring
-- молча становится "# %s" (или пустым) — и gcc комментирует решёткой. Здесь
-- значение берётся заново из filetype; vim.filetype.get_option кэширует его,
-- так что на каждое нажатие приходится только чтение кэша.
local ok_comment, builtin = pcall(require, "vim._comment")
if not ok_comment then
  return
end

local function ensure()
  local ft = vim.bo.filetype
  if ft == "" then
    return
  end
  local ok, cs = pcall(vim.filetype.get_option, ft, "commentstring")
  if not ok or type(cs) ~= "string" or cs == "" then
    cs = vim.bo.commentstring
  end
  local fixed = normalize(cs)
  if fixed and fixed ~= vim.bo.commentstring then
    vim.bo.commentstring = fixed
  end
end

vim.keymap.set({ "n", "x" }, "gc", function()
  ensure()
  return builtin.operator()
end, { expr = true, desc = "Toggle comment" })

vim.keymap.set("n", "gcc", function()
  ensure()
  return builtin.operator() .. "_"
end, { expr = true, desc = "Toggle comment line" })

vim.keymap.set("o", "gc", function()
  ensure()
  builtin.textobject()
end, { desc = "Comment textobject" })
