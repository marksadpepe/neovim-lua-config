local nvim_lsp = require('lspconfig')

-- Форматирование через LSP отключено намеренно: маппинга <space>f нет, а у
-- серверов, умеющих форматировать, возможность гасится в on_attach ниже.
local function disable_formatting(client)
  client.server_capabilities.documentFormattingProvider = false
  client.server_capabilities.documentRangeFormattingProvider = false
end

-- Use an on_attach function to only map the following keys
-- after the language server attaches to the current buffer
local on_attach = function(client, bufnr)

    local function buf_set_keymap(...) vim.api.nvim_buf_set_keymap(bufnr, ...) end
    local function buf_set_option(...) vim.api.nvim_buf_set_option(bufnr, ...) end

    -- Enable completion triggered by <c-x><c-o>
    buf_set_option('omnifunc', 'v:lua.vim.lsp.omnifunc')

    -- Mappings
    local opts = { noremap=true, silent=true }

    -- See `:help vim.lsp.*` for documentation on any of the below functions
    buf_set_keymap('n', 'gD', '<cmd>tab split | lua vim.lsp.buf.declaration()<CR>', opts)
    buf_set_keymap('n', 'gd', '<cmd>tab split | lua vim.lsp.buf.definition()<CR>', opts)
    buf_set_keymap('n', 'K', '<cmd>lua vim.lsp.buf.hover()<CR>', opts)
    -- Где используется: список всех ссылок с превью и fuzzy-фильтром.
    -- include_declaration=false — само объявление в список не попадает,
    -- только реальные использования.
    buf_set_keymap('n', 'gr', '<cmd>Telescope lsp_references include_declaration=false<CR>', opts)
    -- Кто реализует интерфейс / абстрактный класс
    buf_set_keymap('n', 'gi', '<cmd>Telescope lsp_implementations<CR>', opts)
    buf_set_keymap('n', '<C-k>', '<cmd>lua vim.lsp.buf.signature_help()<CR>', opts)
    buf_set_keymap('n', '<space>wa', '<cmd>lua vim.lsp.buf.add_workspace_folder()<CR>', opts)
    buf_set_keymap('n', '<space>wr', '<cmd>lua vim.lsp.buf.remove_workspace_folder()<CR>', opts)
    buf_set_keymap('n', '<space>wl', '<cmd>lua print(vim.inspect(vim.lsp.buf.list_workspace_folders()))<CR>', opts)
    buf_set_keymap('n', '<space>rn', '<cmd>lua vim.lsp.buf.rename()<CR>', opts)
    buf_set_keymap('n', '<space>ca', '<cmd>lua vim.lsp.buf.code_action()<CR>', opts)
    buf_set_keymap('n', '<space>e', '<cmd>lua vim.diagnostic.open_float()<CR>', opts)
    buf_set_keymap('n', '[d', '<cmd>lua vim.diagnostic.goto_prev()<CR>', opts)
    buf_set_keymap('n', ']d', '<cmd>lua vim.diagnostic.goto_next()<CR>', opts)
    buf_set_keymap('n', '<space>q', '<cmd>lua vim.diagnostic.setloclist()<CR>', opts)

    require "lsp_signature".on_attach({
        bind = true, -- This is mandatory, otherwise border config won't get registered.
        floating_window = true,
        floating_window_above_cur_line = true,
        floating_window_off_x = 20,
        doc_lines = 10,
        hint_prefix = '🤡 '
      }, bufnr)  -- Note: add in lsp client on-attach
  end

-- Golang
nvim_lsp.gopls.setup({})

-- TS
local buf_map = function(bufnr, mode, lhs, rhs, opts)
    vim.api.nvim_buf_set_keymap(bufnr, mode, lhs, rhs, opts or {
        silent = true,
    })
end

-- Заменяет nvim-lsp-ts-utils: те же действия делает сам ts_ls через code actions.
-- Ключи обязательно с суффиксом ".ts" — без него сервер их не отдаёт.
local function ts_code_action(kind)
  return function()
    vim.lsp.buf.code_action({
      context = { only = { kind }, diagnostics = {} },
      apply = true,
    })
  end
end

nvim_lsp.ts_ls.setup({
    on_attach = function(client, bufnr)
        disable_formatting(client)

        buf_map(bufnr, "n", "<C-i>", "", {
          noremap = true,
          silent = true,
          callback = function()
            inlay_enabled = not inlay_enabled
            if inlay_enabled then
              vim.lsp.inlay_hint.enable(true)
            else
              vim.lsp.inlay_hint.enable(false)
            end
          end

        })

        -- gs — отсортировать импорты, go — дописать недостающие,
        -- gu — выкинуть неиспользуемые (раньше этого не было)
        vim.keymap.set("n", "gs", ts_code_action("source.organizeImports.ts"),
          { buffer = bufnr, noremap = true, silent = true })
        vim.keymap.set("n", "go", ts_code_action("source.addMissingImports.ts"),
          { buffer = bufnr, noremap = true, silent = true })
        vim.keymap.set("n", "gu", ts_code_action("source.removeUnusedImports.ts"),
          { buffer = bufnr, noremap = true, silent = true })

        on_attach(client, bufnr)
    end,
    init_options = {
      preferences = {
        includeInlayParameterNameHints = "all",  -- Показывать все подсказки
        includeInlayParameterNameHintsWhenArgumentMatchesName = true,
        includeInlayFunctionParameterTypeHints = true,
        includeInlayVariableTypeHints = true,
        includeInlayVariableTypeHintsWhenTypeMatchesName = true,
        includeInlayPropertyDeclarationTypeHints = true,
        includeInlayFunctionLikeReturnTypeHints = true,
        includeInlayEnumMemberValueHints = true,
      },
    },
})

local servers = { 'rust_analyzer' }
for _, lsp in ipairs(servers) do
  nvim_lsp[lsp].setup {
    on_attach = function(client, bufnr)
      disable_formatting(client)
      on_attach(client, bufnr)
    end,
    flags = {
      debounce_text_changes = 150,
    }
  }
end
