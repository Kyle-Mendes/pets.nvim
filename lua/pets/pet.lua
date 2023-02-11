local M = {}

M.Pet = {}
M.Pet.__index = M.Pet

local popup_opts = {
    position = {
        row = "100%",
        col = "100%",
    },
    size = {
        width = "30%",
        height = 10,
    },
    focusable = false,
    enter = false,
    win_options = {
        winblend = 100,
    },
}
-- @param name the actual name for the pet
-- @param type the species of the pet e.g. cat
-- @param style the color/style of the pet e.g. brown
-- @return a new Pet instance
function M.Pet.new(name, type, style, user_opts)
    local instance = setmetatable({}, M.Pet)
    instance.name = name
    instance.type = type
    instance.style = style

    local wd = debug.getinfo(1).source:sub(2):match("(.*nvim/)") .. "media/"
    instance.sourcedir = wd .. type .. "/" .. style .. "/"

    instance.popup = require("nui.popup")(popup_opts)
    instance.animation = require("pets.animations").Animation.new(
        instance.sourcedir,
        type,
        style,
        instance.popup.win_config.width,
        user_opts
    )
    return instance
end

function M.Pet:animate()
    self.popup:mount()
    self.animation:start(self.popup.bufnr)
end

function M.Pet:kill()
    self.popup:unmount()
    self.animation:stop()
end

return M
