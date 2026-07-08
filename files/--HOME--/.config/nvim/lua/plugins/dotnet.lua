-- C# / .NET support via the Roslyn LSP.
--
-- Prerequisites (install manually if missing):
--   * .NET SDK on PATH       (`brew install --cask dotnet-sdk` or `mise use dotnet@8`)
--   * Neovim >= 0.12         (roslyn.nvim requires it)
--
-- Notes:
--   * The Roslyn server isn't in the core Mason registry, so we add
--     `Crashdummyy/mason-registry` and let mason install `roslyn` from there.
--   * roslyn.nvim wires its own lspconfig and is intentionally NOT managed
--     by mason-lspconfig (don't add `roslyn` to mason-lspconfig.ensure_installed).
--   * csharpier handles formatting; the Roslyn LSP's own formatter is suppressed.

---@type LazySpec
return {
  {
    "seblyng/roslyn.nvim",
    ft = { "cs" },
    ---@module 'roslyn.config'
    ---@type RoslynNvimConfig
    opts = {},
  },

  -- Add the Crashdummyy registry and ensure the Roslyn server is installed.
  {
    "williamboman/mason.nvim",
    opts = function(_, opts)
      opts.registries = opts.registries or { "github:mason-org/mason-registry" }
      if not vim.tbl_contains(opts.registries, "github:Crashdummyy/mason-registry") then
        table.insert(opts.registries, "github:Crashdummyy/mason-registry")
      end
      opts.ensure_installed = require("astrocore").list_insert_unique(
        opts.ensure_installed or {},
        { "roslyn" }
      )
    end,
  },

  -- C# treesitter parser.
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = require("astrocore").list_insert_unique(
        opts.ensure_installed or {},
        { "c_sharp" }
      )
    end,
  },

  -- csharpier as the C# formatter (mason-null-ls auto-registers it as a null-ls source).
  {
    "jay-babu/mason-null-ls.nvim",
    opts = function(_, opts)
      opts.ensure_installed = require("astrocore").list_insert_unique(
        opts.ensure_installed or {},
        { "csharpier" }
      )
    end,
  },

  -- Let csharpier win on format-on-save by silencing the Roslyn LSP's formatter.
  {
    "AstroNvim/astrolsp",
    ---@type AstroLSPOpts
    opts = {
      formatting = {
        disabled = { "roslyn" },
      },
    },
  },
}
