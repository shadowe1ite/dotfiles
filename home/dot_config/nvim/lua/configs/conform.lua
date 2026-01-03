local options = {
  formatters = {
    qmlformat = {
      command = "/usr/lib/qt6/bin/qmlformat",
      args = {
        "-w", "2",
        "-W", "360",
        "-S",
        "--semicolon-rule", "always",
        "-i",
        "$FILENAME",
      },
      stdin = false,
    },
  },

  formatters_by_ft = {
    lua = { "stylua" },
    css = { "prettier" },
    html = { "prettier" },
    yaml = { "yamlfix" },
    python = { "black", "isort" },
    c = { "clang-format" },
    cpp = { "clang-format" },
    rust = { "rustfmt" },
    qml = { "qmlformat" },
  },

  format_on_save = {
    timeout_ms = 500,
    lsp_fallback = true,
  },
}

return options
