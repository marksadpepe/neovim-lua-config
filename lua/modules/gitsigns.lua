-- Git в буфере: знаки изменений слева, blame текущей строки виртуальным
-- текстом справа (аналог GitLens) и разворот старых строк по ,h.
-- Заменил mini.diff: тот показывал только дифф с индексом и blame не умел.
local gs = require("gitsigns")

gs.setup({
  -- Обычный юникод: Nerd Font в терминале нет. Формой различаем тип
  -- изменения, цветом — нет (см. modules/colors.lua, красный занят
  -- ключевыми словами).
  signs = {
    add          = { text = "+" },
    change       = { text = "~" },
    delete       = { text = "_" },
    topdelete    = { text = "‾" },
    changedelete = { text = "~" },
    untracked    = { text = "|" },
  },
  -- Застейдженные ханки — тем же набором: отдельная палитра тут ничего не
  -- добавляет, а знаков в колонке становится вдвое больше.
  signs_staged_enable = false,

  -- Только колонка знаков. numhl красил бы номера строк (number включён в
  -- set.lua), linehl — фон всей строки; и то и другое включается по ,h.
  numhl = false,
  linehl = false,
  word_diff = false,

  -- Собственно GitLens: " автор, 3 days ago - сообщение коммита" в конце
  -- текущей строки. delay меньше дефолтного (1000) — на глаз оно тормозит.
  current_line_blame = true,
  current_line_blame_opts = {
    virt_text = true,
    virt_text_pos = "eol",
    delay = 300,
    ignore_whitespace = false,
  },
  current_line_blame_formatter = " <author>, <author_time:%R> - <summary>",

  on_attach = function(bufnr)
    local map = function(mode, lhs, rhs, desc)
      vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, noremap = true, silent = true, desc = desc })
    end

    -- Навигация и стейджинг — те же клавиши, что раздавал mini.diff.
    map("n", "]h", function() gs.nav_hunk("next") end, "Следующий ханк")
    map("n", "[h", function() gs.nav_hunk("prev") end, "Предыдущий ханк")
    map("n", "]H", function() gs.nav_hunk("last") end, "Последний ханк")
    map("n", "[H", function() gs.nav_hunk("first") end, "Первый ханк")

    map("n", "gh", gs.stage_hunk, "Застейджить ханк")
    map("n", "gH", gs.reset_hunk, "Сбросить ханк")
    -- В visual gitsigns стейджит только выделенные строки, поэтому нужен диапазон.
    map("v", "gh", function() gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") }) end, "Застейджить выделение")
    map("v", "gH", function() gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") }) end, "Сбросить выделение")

    -- Текстобъект: ханк под курсором (dih, vih).
    map({ "o", "x" }, "ih", gs.select_hunk, "Ханк")

    -- Blame конкретной строки: попап с коммитом целиком и его диффом —
    -- это то, чего в виртуальном тексте не помещается.
    map("n", ",b", function() gs.blame_line({ full = true }) end, "Blame строки")
    -- Blame всего файла отдельной панелью слева.
    map("n", ",B", gs.blame, "Blame файла")
  end,
})

-- ,h — оверлей на весь буфер, как было у mini.diff: удалённые строки
-- разворачиваются виртуальными строками на месте, изменённые подсвечиваются
-- фоном, внутри строки видно посимвольную разницу. Повторное нажатие убирает.
--
-- Три отдельных тумблера, потому что цельного «оверлея» у gitsigns нет.
-- toggle_deleted помечен deprecated в пользу preview_hunk_inline, но тот
-- показывает один ханк и гаснет на CursorMoved — для чтения диффа не годится.
-- Сам show_deleted не deprecated и живёт в конфиге, так что при выпиливании
-- тумблера достаточно будет писать в config напрямую.
local overlay = false
vim.keymap.set("n", ",h", function()
  overlay = not overlay
  gs.toggle_deleted(overlay)
  gs.toggle_linehl(overlay)
  gs.toggle_word_diff(overlay)
  -- Тумблеры только пишут в конфиг, перерисовку надо просить самому.
  gs.refresh()
end, { noremap = true, silent = true, desc = "Оверлей диффа" })
