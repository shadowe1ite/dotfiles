return {
  {
    "stevearc/conform.nvim",
    event = 'BufWritePre', -- uncomment for format on save
    opts = require "configs.conform",
  },

  -- These are some examples, uncomment them if you want to see them work!
  {
    "neovim/nvim-lspconfig",
    config = function()
      require "configs.lspconfig"
    end,
  },
  { 
    "CRAG666/code_runner.nvim",
    cmd = { "RunCode", "RunFile", "RunProject", "CRFiletype", "CRProjects" },
    config = function()
      require "configs.code_runner"
    end,
  },
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    cmd = { "CopilotChatToggle" },
    dependencies = {
      { 
        "github/copilot.vim",
        config = function()
          vim.g.copilot_enabled = true
          vim.g.copilot_no_tab_map = true
        end
      },
      { "nvim-lua/plenary.nvim", branch = "master" },
    },
    build = "make tiktoken",
    event = 'BufWritePre',
    opts = require "configs.copilot",
  },
  {
    "hrsh7th/nvim-cmp",
    opts = function(_, opts)
      local cmp = require "cmp"

      -- "Smart Enter"
      -- If menu is visible and an item is selected, confirm it
      -- Otherwise, just insert a newline
      opts.mapping["<CR>"] = cmp.mapping(function(fallback)
        if cmp.visible() and cmp.get_selected_entry() then
          cmp.confirm { select = true }
        else
          fallback()
        end
      end, { "i", "s" })

      -- Your requested Ctrl+Enter to always insert a newline
      opts.mapping["<C-CR>"] = cmp.mapping(function(fallback)
        fallback()
      end, { "i", "s" })
    end,
  },

  -- test new blink
  -- { import = "nvchad.blink.lazyspec" },

   {
   	"nvim-treesitter/nvim-treesitter",
   	opts = {
   		ensure_installed = {
   			"vim", "lua", "vimdoc",
        "html", "css", "qmljs",
        "markdown"
   		},
   	},
   },
}
