-- Duo plugin for Neovim
-- This file provides the plugin entry point for modern Neovim plugin managers

local M = {}

function M.setup(opts)
    opts = opts or {}

    -- Set up autocommands for Duo filetype
    vim.api.nvim_create_autocmd("FileType", {
        pattern = "duo",
        callback = function()
            vim.opt_local.commentstring = "--%s"
            vim.opt_local.tabstop = 4
            vim.opt_local.shiftwidth = 4
            vim.opt_local.expandtab = true
        end,
    })

    -- Optional: custom configuration
    if opts.tabstop then
        vim.api.nvim_create_autocmd("FileType", {
            pattern = "duo",
            callback = function()
                vim.opt_local.tabstop = opts.tabstop
            end,
        })
    end

    if opts.shiftwidth then
        vim.api.nvim_create_autocmd("FileType", {
            pattern = "duo",
            callback = function()
                vim.opt_local.shiftwidth = opts.shiftwidth
            end,
        })
    end
end

return M