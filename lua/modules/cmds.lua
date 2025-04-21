vim.cmd('filetype plugin indent on')
vim.cmd('colorscheme OceanicNext')
vim.cmd([[
  hi DiagnosticError guifg=Red
  hi DiagnosticWarn  guifg=White
  hi DiagnosticInfo  guifg=White
  hi DiagnosticHint  guifg=White
]])
vim.api.nvim_create_autocmd("FileType", {
  pattern = "qf",
  callback = function()
    vim.api.nvim_buf_set_keymap(0, 'n', 'T', '<C-W><CR><C-W>T', { noremap = true })
  end
})
