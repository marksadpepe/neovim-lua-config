vim.cmd('filetype plugin indent on')
vim.cmd('colorscheme gruvbox')
vim.cmd([[
  hi DiagnosticError guifg=Red
  hi DiagnosticWarn  guifg=White
  hi DiagnosticInfo  guifg=White
  hi DiagnosticHint  guifg=White
]])