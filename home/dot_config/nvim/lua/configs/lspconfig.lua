require("nvchad.configs.lspconfig").defaults()

local servers = { "html", "cssls", "gopls", "ts_ls", "qmlls", "pyright" }

local lspconfig = require("lspconfig")

vim.env.QML_IMPORT_PATH = "/usr/lib/qt6/qml"
vim.env.QML2_IMPORT_PATH = "/usr/lib/qt6/qml"

vim.lsp.config.qmlls = {
  cmd = { "/usr/lib/qt6/bin/qmlls", "-E" },
  filetypes = { "qml", "qmljs" },
  root_dir = vim.fs.dirname(vim.fs.find({ ".qmlls.ini", ".git", ".qmlformat.ini" }, { upward = true })[1]),
  single_file_support = true,
}

vim.lsp.enable(servers)
