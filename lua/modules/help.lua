local M = {}

if vim.g.loaded_bclose then
  return M
end
vim.g.loaded_bclose = 1

if vim.g.bclose_multiple == nil then
  vim.g.bclose_multiple = 1
end

local function warn(msg)
  vim.cmd('echohl ErrorMsg')
  vim.cmd(string.format('echomsg "%s"', msg:gsub('"', '\\"')))
  vim.cmd('echohl NONE')
end

function M.bclose(bang, buffer)
  local btarget
  
  if buffer == nil or buffer == "" then
    btarget = vim.fn.bufnr('%')
  elseif string.match(buffer, "^%d+$") then
    btarget = vim.fn.bufnr(tonumber(buffer))
  else
    btarget = vim.fn.bufnr(buffer)
  end
  
  if btarget < 0 then
    warn('No matching buffer for ' .. (buffer or ''))
    return
  end
  
  if (bang == nil or bang == "") and vim.fn.getbufvar(btarget, '&modified') == 1 then
    warn('No write since last change for buffer ' .. btarget .. ' (use :Bclose!)')
    return
  end
  
  local wnums = {}
  for i = 1, vim.fn.winnr('$') do
    if vim.fn.winbufnr(i) == btarget then
      table.insert(wnums, i)
    end
  end
  
  if not vim.g.bclose_multiple and #wnums > 1 then
    warn('Buffer is in multiple windows (use ":let bclose_multiple=1")')
    return
  end
  
  local wcurrent = vim.fn.winnr()
  
  for _, w in ipairs(wnums) do
    vim.cmd(w .. 'wincmd w')
    local prevbuf = vim.fn.bufnr('#')
    
    if prevbuf > 0 and vim.fn.buflisted(prevbuf) == 1 and prevbuf ~= btarget then
      vim.cmd('buffer #')
    else
      vim.cmd('bprevious')
    end
    
    if btarget == vim.fn.bufnr('%') then
      local blisted = {}
      for i = 1, vim.fn.bufnr('$') do
        if vim.fn.buflisted(i) == 1 and i ~= btarget then
          table.insert(blisted, i)
        end
      end
      
      local bhidden = {}
      for _, v in ipairs(blisted) do
        if vim.fn.bufwinnr(v) < 0 then
          table.insert(bhidden, v)
        end
      end
      
      local bjump = -1
      if #bhidden > 0 then
        bjump = bhidden[1]
      elseif #blisted > 0 then
        bjump = blisted[1]
      end
      
      if bjump > 0 then
        vim.cmd('buffer ' .. bjump)
      else
        vim.cmd('enew' .. (bang or ''))
      end
    end
  end
  
  vim.cmd('bdelete' .. (bang or '') .. ' ' .. btarget)
  vim.cmd(wcurrent .. 'wincmd w')
end

vim.cmd([[
  command! -bang -complete=buffer -nargs=? Bclose lua require('modules.help').bclose('<bang>', '<args>')
]])

vim.keymap.set('n', 'gn', ':bn<CR>', { noremap = false, silent = true })

vim.keymap.set('n', 'gp', ':bp<CR>', { noremap = false, silent = true })

vim.keymap.set('n', 'gw', ':Bclose<CR>', { noremap = false, silent = true })

vim.keymap.set('n', '<Leader>bd', function() 
  require('modules.help').bclose('', '') 
end, { noremap = true, silent = true })

return M