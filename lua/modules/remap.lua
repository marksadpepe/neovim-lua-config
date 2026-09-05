vim.keymap.set('i', 'jk', '<Esc>', { noremap = true, silent = true })
vim.keymap.set('n', ',<space>', ':nohlsearch<CR>', { noremap = true, silent = true })
vim.keymap.set('n', ',f', '<cmd>Telescope find_files<cr>', { noremap = true, silent = true })
vim.keymap.set('n', ',g', '<cmd>Telescope live_grep<cr>', { noremap = true, silent = true })
vim.keymap.set('t', '<Esc>', '<C-\\><C-n>', { noremap = true })

-- ,l — список открытых файлов с поиском, когда их больше, чем влезает
-- в полоску вкладок. ,b занят blame-попапом gitsigns.
vim.keymap.set('n', ',l', '<cmd>Telescope buffers<cr>', { noremap = true, silent = true })

-- H/J переключают открытые файлы, а не табы: табы в этом конфиге не
-- используются, файлы живут буферами в одной табе (см. modules/tabline.lua).
vim.keymap.set('n', 'J', function() require('modules.tabline').next() end, { noremap = true, silent = true })
vim.keymap.set('n', 'H', function() require('modules.tabline').prev() end, { noremap = true, silent = true })
