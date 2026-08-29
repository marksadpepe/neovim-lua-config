require('telescope').setup({
  defaults = {
    -- Обязательно false. При включённом check_mime_type превьюер зовёт
    -- `file --mime-type -b "<путь>"` через io.popen со строкой для шелла
    -- (buffer_previewer.lua:195), не экранируя путь. Файл с именем вида
    -- notes$(команда)txt выполняет эту команду при обычном ,f — проверено.
    -- В upstream не исправлено, обновление telescope не помогает.
    -- Цена: бинарные файлы теперь открываются в превью как текст.
    preview = { check_mime_type = false },
  },
  pickers = {
    -- LSP-пикеры показывают куски кода, поэтому им нужен широкий превью:
    -- вертикальный layout вместо дефолтного horizontal.
    lsp_references = { layout_strategy = 'vertical', layout_config = { preview_height = 0.5 } },
    lsp_implementations = { layout_strategy = 'vertical', layout_config = { preview_height = 0.5 } },
  },
})

require('telescope').load_extension('fzf')
