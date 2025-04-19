-- Netrw file explorer settings
vim.g.netrw_banner = 0 -- hide banner above files
vim.g.netrw_liststyle = 3 -- tree instead of plain view
vim.g.netrw_browse_split = 3 -- vertical split window when Enter pressed on file

-- Turn on vim-sneak
vim.g["sneak#label"] = 1

-- ---- nerdcommenter ----
-- Create default mappings
vim.g.NERDCreateDefaultMappings = 1

-- Add spaces after comment delimiters by default
vim.g.NERDSpaceDelims = 1

-- Use compact syntax for prettified multi-line comments
vim.g.NERDCompactSexyComs = 1

-- Align line-wise comment delimiters flush left instead of following code indentation
vim.g.NERDDefaultAlign = "left"

-- Set a language to use its alternate delimiters by default
vim.g.NERDAltDelims_java = 1

-- Add your own custom formats or override the defaults
vim.g.NERDCustomDelimiters = { c = { left = "/**", right = "*/" } }

-- Allow commenting and inverting empty lines (useful when commenting a region)
vim.g.NERDCommentEmptyLines = 1

-- Enable trimming of trailing whitespace when uncommenting
vim.g.NERDTrimTrailingWhitespace = 1

-- Enable NERDCommenterToggle to check all selected lines is commented or not
vim.g.NERDToggleCheckAllLines = 1