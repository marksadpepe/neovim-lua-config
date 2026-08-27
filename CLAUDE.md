# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A personal Neovim configuration (`~/.config/nvim`), rewritten from a vimrc to Lua. `old_init.vim` is the gitignored legacy vimrc kept as a reference for behavior that has not been ported yet — check it before assuming a setting was never configured.

There is no build, no test suite, and no linter. "Running" the code means starting Neovim.

## Verifying changes

Because everything executes at Neovim startup, a config error is a startup error. After editing:

To check what the colour scheme actually paints, walk the buffer and resolve each character's capture — eyeballing a screenshot is not reliable:

```lua
-- for each position: vim.treesitter.get_captures_at_pos(0, line, col)
-- then vim.api.nvim_get_hl(0, { name = "@"..capture, link = false }).fg
```

```sh
# Does the config load cleanly? Errors print to stderr.
nvim --headless "+lua print('ok')" +qa

# Install/sync plugins after touching lua/plugins/*.lua (also updates lazy-lock.json)
nvim --headless "+Lazy! sync" +qa

# Inspect a specific module's effect without a real session
nvim --headless -c 'lua print(vim.inspect(vim.opt.shiftwidth:get()))' +qa
```

Note that `nvim-lspconfig` prints a deprecation warning on Nvim 0.10 (the version in use here); that line is expected noise, not a failure.

For anything interactive (nvim-tree layout, completion popups, colors), drive a real headless session with a deferred `qa!` and a fixed `columns`/`lines` rather than trying to assert it in Lua — see the pre-approved commands in `.claude/settings.local.json` for the shape.

## Architecture

`init.lua` sets `mapleader` and then pulls in two directories that play very different roles:

- **`lua/plugins/*.lua` — declarative.** Each file returns a list of lazy.nvim specs, and `lua/config/lazy.lua` imports the whole directory via `{ import = "plugins" }`. These specs are deliberately bare (name, occasional `tag`/`build`/`branch`) and carry **no** `config`/`opts`/lazy-loading keys. Grouped by purpose: `main.lua` (LSP, completion, telescope, git), `code.lua` (language/editing plugins, treesitter), `ui.lua` (nvim-tree). `plugins/init.lua` returns `{}` and exists only so `require("plugins")` in `init.lua` resolves.
- **`lua/modules/*.lua` — imperative.** Every plugin's actual configuration lives here as a top-level `require(...).setup{}` call, plus the pure-vim settings. `lua/modules/init.lua` is an explicit ordered list of `require` calls and is the single place new modules get registered.

The consequence: **nothing is lazy-loaded.** `modules/*` calls `require("gitsigns")`, `require("cmp")`, etc. at startup, which forces every plugin to load immediately regardless of what lazy.nvim would otherwise defer. This is why the specs are bare. If you add a `lazy = true` or `event = ...` key to a spec whose module is required in `modules/init.lua`, startup will break with a module-not-found error.

**Adding a plugin is therefore a three-step change:** add the spec to the right `lua/plugins/*.lua`, create `lua/modules/<name>.lua` with its setup, and append `require("modules.<name>")` to `lua/modules/init.lua`. Order in that list matters — `set.lua` first so options exist before plugins read them, `lsp.lua` after `cmp.lua`, and `colors.lua` **last** so its highlight groups override anything a plugin defines.

`lazy-lock.json` is committed; treat its churn as a real change and mention it when a sync updates plugins.

## Conventions in this config

- **Leader is `,`**, set in *both* `init.lua` and `lua/config/lazy.lua`. lazy.nvim requires it before `setup()`, so keep both in sync if it ever changes.
- Many mappings hardcode the literal `,` prefix (`,f`, `,g`, `,e`, `,<space>`) instead of `<leader>`, while fold mappings use `<leader>`. Match whichever style the surrounding file already uses rather than normalizing.
- `set.lua` sets `tabstop`/`shiftwidth` twice — the 4-space block is dead, the later 2-space block wins. Edit the second block.
- **Folding is stock** (`foldmethod=manual`). The old `syntax` folding and the `<leader>m`/`mo`/`mc` mappings were removed; `foldmethod=syntax` also cost real time on large files.
- **Colors live only in `modules/colors.lua`.** There is no colorscheme plugin: `hi clear` plus an explicit palette (`#ffffff` on `#000000`, keywords `#ff6b6b`, comments `#6b6b6b`). Rules are written against **treesitter captures** (`@keyword.*`), not vim syntax groups, so JS and TS behave identically. `termguicolors` is set here — without it every `guifg` in the config is silently ignored.
- **Do not colour by `Statement`/`Keyword`.** The bundled TypeScript syntax links stdlib methods (`.map`, `JSON.stringify`, `Math.floor`, `Promise.all`) to `Statement`, and puts `const`/`let` under `Identifier` — colouring those groups paints exactly the wrong tokens. This is why highlighting is driven by treesitter.
- **nvim-treesitter is pinned to `branch = "master"`.** The `main` branch is the rewrite and requires Neovim 0.11+; this machine runs 0.10.3. `additional_vim_regex_highlighting = false` matters too — otherwise the old regex syntax runs on top and reintroduces the JS/TS inconsistencies.
- **LSP semantic tokens are disabled** by an `LspAttach` autocmd in `colors.lua`. Neovim 0.10 turns them on automatically and `ts_ls` repaints identifiers via `@lsp.type.*` on top of treesitter, which breaks the two-colour scheme.
- **No Nerd Font in the terminal.** `tree.lua` explicitly disables file/folder icons and uses plain unicode glyphs. Do not introduce Nerd Font codepoints anywhere in the UI.
- **nvim-tree is the file browser** (`,e` opens the panel *and* moves the cursor into it, `,e` from inside closes it, `,E` reveals the current file), configured in `tree.lua`. `,e` is a Lua function rather than `NvimTreeToggle` on purpose: the plain toggle closes the panel from any window, so there is no way to step into an already-open tree with the same key. The panel is window-global, not per-tab: `tab.sync.open`/`tab.sync.close` make it appear in every tab and disappear from all of them at once, so `<C-t>` from the tree lands in a new tab that already has the sidebar. Its `on_attach` runs `default_on_attach` and then restores `H`/`J` to `gT`/`gt` (the global tab mappings from `remap.lua`, which nvim-tree otherwise shadows with dotfile/sibling actions); the dotfile toggle moves to `gh`. It keeps `hijack_netrw = true` (the default), so netrw stays loaded but nvim-tree takes over directory opening — `:Ex` and `nvim .` land in the tree. The netrw settings in `global.lua` are therefore mostly inert; they only matter if the plugin is ever removed again. Two things the plugin does not handle on its own: `spell` is on globally, so `tree.lua` clears it for the `NvimTree` filetype, and the plugin hardcodes a blue `#8094b4` in `NvimTreeFolderIcon` — which arrows and indent markers link to — so the `NvimTree*` groups are listed explicitly in `colors.lua`, which loads last.
- **Commenting is Neovim's built-in `gc`/`gcc`**, not a plugin. `modules/comment.lua` normalises `commentstring` on `FileType` so the delimiter gets a trailing space (`// %s`, `/* %s */`) — the built-in comments verbatim from `commentstring`, which ships without one. It must load *after* `cmds.lua` runs `filetype plugin indent on`, or the ftplugin overwrites it.
- **Gatekeeper and treesitter on macOS.** Neovim here is an extracted download at `~/nvim-macos-arm64`, so its bundled parsers in `lib/nvim/parser/` carry `com.apple.quarantine`. Loading a parser for the first time pops a "Not Opened" dialog — **Done** dismisses it, **Move to Trash** deletes the parser. Parsers built locally under `nvim-treesitter/parser/` are unaffected.
- LSP servers are configured in `lsp.lua` with a shared `on_attach` that installs the buffer-local keymaps and `lsp_signature`. `ts_ls` has a bespoke setup that calls `on_attach` itself; simple servers go in the `servers` loop at the bottom. **There is deliberately no C/C++ server** — the clangd block was removed, so `.c` files get no LSP and no treesitter parser. **pyright is configured but not installed** — lspconfig starts nothing and reports no error, so a missing binary looks identical to a working setup.
- **LSP formatting is off by design.** There is no `<space>f` mapping, and `disable_formatting()` clears `documentFormattingProvider` for every server that would offer it. Note the field name: the old `client.server_capabilities.document_formatting` does **nothing** on this Neovim — it is not a real capability key, so code using it silently leaves formatting enabled.
- **TS import actions are native, not a plugin.** `gs` (organize), `go` (add missing), `gu` (remove unused) call `vim.lsp.buf.code_action` directly. The action kinds **must** carry the `.ts` suffix — `source.organizeImports.ts`, not `source.organizeImports` — or `typescript-language-server` returns nothing.
- `help.lua` is a hand-ported Lua version of the classic `:Bclose` vimscript, and is the only module that returns a table (`M`) — it is required by the `Bclose` user command it defines.
- Filetype-specific behavior goes in an `nvim_create_autocmd("FileType", ...)` next to the feature it belongs to (see `tree.lua`, `cmds.lua`), not in a central autocmd file.
