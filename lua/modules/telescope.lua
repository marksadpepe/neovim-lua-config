require('telescope').setup({
  pickers = {
    -- LSP-пикеры показывают куски кода, поэтому им нужен широкий превью:
    -- вертикальный layout вместо дефолтного horizontal.
    lsp_references = { layout_strategy = 'vertical', layout_config = { preview_height = 0.5 } },
    lsp_implementations = { layout_strategy = 'vertical', layout_config = { preview_height = 0.5 } },
  },
})

require('telescope').load_extension('fzf')
