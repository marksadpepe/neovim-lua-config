-- Комментирование — встроенное в Neovim 0.10: gcc на строку, gc на motion/выделение.
-- Встроенный вариант берёт commentstring как есть, а он идёт без пробела ("//%s"),
-- поэтому нормализуем его — это то, что раньше делал NERDSpaceDelims = 1.
vim.api.nvim_create_autocmd("FileType", {
  desc = "Пробел после делимитера комментария",
  callback = function()
    local cs = vim.bo.commentstring
    if cs == "" then
      return
    end
    local left, right = cs:match("^(.*)%%s(.*)$")
    if not left then
      return
    end
    left, right = vim.trim(left), vim.trim(right)
    if left ~= "" then
      left = left .. " "
    end
    if right ~= "" then
      right = " " .. right
    end
    vim.bo.commentstring = left .. "%s" .. right
  end,
})
