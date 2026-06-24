-- AstroCore provides a central place to modify mappings, vim options, autocommands, and more!
-- Configuration documentation can be found with `:h astrocore`
-- NOTE: We highly recommend setting up the Lua Language Server (`:LspInstall lua_ls`)
--       as this provides autocomplete and documentation while editing

---@type LazySpec
return {
  "AstroNvim/astrocore",
  ---@type AstroCoreOpts
  opts = {
    -- Configure core features of AstroNvim
    features = {
      large_buf = { size = 1024 * 256, lines = 10000 }, -- set global limits for large files for disabling features like treesitter
      autopairs = true, -- enable autopairs at start
      cmp = true, -- enable completion at start
      diagnostics_mode = 3, -- diagnostic mode on start (0 = off, 1 = no signs/virtual text, 2 = no virtual text, 3 = on)
      highlighturl = true, -- highlight URLs at start
      notifications = true, -- enable notifications at start
    },
    -- Diagnostics configuration (for vim.diagnostics.config({...})) when diagnostics are on
    diagnostics = {
      virtual_text = true,
      underline = true,
    },
    -- vim options can be configured here
    options = {
      opt = { -- vim.opt.<key>
        relativenumber = true, -- sets vim.opt.relativenumber
        number = true, -- sets vim.opt.number
        spell = false, -- sets vim.opt.spell
        signcolumn = "yes", -- sets vim.opt.signcolumn to yes
        wrap = true, -- sets vim.opt.wrap
        ignorecase = true,
        smartcase = true,
        hlsearch = false,
        incsearch = true,
        scrolloff = 40,
        updatetime = 50,
        cursorline = true,
        termguicolors = true,
        background = "dark",
        backspace = "indent,eol,start",
      },
      g = { -- vim.g.<key>
        -- configure global vim variables (vim.g)
        -- NOTE: `mapleader` and `maplocalleader` must be set in the AstroNvim opts or before `lazy.setup`
        -- This can be found in the `lua/lazy_setup.lua` file
      },
    },
    -- Mappings can be configured through AstroCore as well.
    -- NOTE: keycodes follow the casing in the vimdocs. For example, `<Leader>` must be capitalized
    mappings = {
      -- first key is the mode
      n = {
        -- second key is the lefthand side of the map

        -- navigate buffer tabs
        ["]b"] = { function() require("astrocore.buffer").nav(vim.v.count1) end, desc = "Next buffer" },
        ["[b"] = { function() require("astrocore.buffer").nav(-vim.v.count1) end, desc = "Previous buffer" },

        -- mappings seen under group name "Buffer"
        ["<Leader>bd"] = {
          function()
            require("astroui.status.heirline").buffer_picker(
              function(bufnr) require("astrocore.buffer").close(bufnr) end
            )
          end,
          desc = "Close buffer from tabline",
        },

        -- tables with just a `desc` key will be registered with which-key if it's installed
        -- this is useful for naming menus
        -- ["<Leader>b"] = { desc = "Buffers" },

        -- setting a mapping to false will disable it
        -- ["<C-S>"] = false,
        ["<Leader>sv"] = { "<C-w>v", desc = "[S]plit window [V]ertically" },
        ["<Leader>sh"] = { "<C-w>s", desc = "[S]plit window [H]orizontally" },
        ["<Leader>se"] = { "<C-w>=", desc = "Make splits [E]qual [S]ize" },
        ["<Leader>sx"] = { "<cmd>close<CR>", desc = "Close current split screen" },

        -- ["<C-h>"] = { "<cmd>TmuxNavigateLeft<CR>", desc = "window left" },
        -- ["<C-l>"] = { "<cmd>TmuxNavigateRight<CR>", desc = "window right" },
        -- ["<C-k>"] = { "<cmd>TmuxNavigateUp<CR>", desc = "window up" },
        -- ["<C-j>"] = { "<cmd>TmuxNavigateDown<CR>", desc = "window down" },
        --
        ["gh"] = { "^", desc = "Go to the beginning of the line" },
        ["gl"] = { "$", desc = "Go to the end of the line" },
        ["gj"] = { "G", desc = "Go to the end of the file" },
        ["gk"] = { "gg", desc = "Go to the beginning of the file" },

        ["<Leader>fs"] = { ":Telescope live_grep custom=multi_rg<cr>", noremap = true },
      },
      v = {
        ["gh"] = { "^", desc = "Go to the beginning of the line" },
        ["gl"] = { "$", desc = "Go to the end of the line" },
        ["gj"] = { "G", desc = "Go to the end of the file" },
        ["gk"] = { "gg", desc = "Go to the beginning of the file" },
      },
      i = {
        ["jj"] = { "<ESC>", desc = "Exit insert mode with jj" },
      },
    },
  },
}
