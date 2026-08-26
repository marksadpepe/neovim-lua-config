require("nvim-treesitter.configs").setup({
  ensure_installed = { "javascript", "typescript", "tsx", "lua", "json" },
  auto_install = false,
  highlight = {
    enable = true,
    -- Обязательно false: иначе поверх treesitter доработает старый regex-синтаксис
    -- и вернёт разнобой групп между .js и .ts
    additional_vim_regex_highlighting = false,
  },
  indent = { enable = false },
})
