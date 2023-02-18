local utils = require("pets.utils")

local M = {}
M.Animation = {}
M.Animation.__index = M.Animation

-- lines to insert in the buffer to avoid image stretching
local lines = {}

local listdir = require("pets.utils").listdir
local sleeping_animations = { "idle", "sit", "liedown" }

local function get_sleeping_animation()
    return sleeping_animations[math.random(#sleeping_animations)]
end

-- @param sourcedir the full path for the media directory
-- @param type,style type and style of the pet
-- @param popup the popup where the pet is displayed
-- @param user_opts table with user options
-- @return a new animation instance
function M.Animation.new(sourcedir, type, style, popup, user_opts, state)
    local instance = setmetatable({}, M.Animation)
    instance.type = type
    instance.style = style
    instance.sourcedir = sourcedir
    instance.frame_counter = 1
    instance.actions = listdir(sourcedir)
    instance.frames = {}
    instance.popup = popup
    instance.state = state

    for _ = 1, instance.popup._.layout.size.height do
        table.insert(lines, " ")
    end

    -- user options
    instance.row, instance.col = user_opts.row, user_opts.col
    instance.speed_multiplier = user_opts.speed_multiplier
    if user_opts.col > popup.win_config.width - 8 then
        M.base_col = popup.win_config.width - 8
    else
        M.base_col = user_opts.col
    end

    -- setup frames
    for _, action in pairs(instance.actions) do
        local current_actions = {}
        for _, file in pairs(listdir(sourcedir .. action)) do
            local image = require("hologram.image"):new(sourcedir .. action .. "/" .. file)
            table.insert(current_actions, image)
        end
        instance.frames[action] = current_actions
    end
    return instance
end

function M.Animation:start_timer()
    if self.timer ~= nil then
        self:stop_timer()
    end
    self.timer = vim.loop.new_timer()
    self.timer:start(0, 1000 / (self.speed_multiplier * 8), function()
        vim.schedule(function()
            M.Animation.next_frame(self)
        end)
    end)
end

function M.Animation:stop_timer()
    print()
    if self.timer == nil then
        return
    end
    self.timer:stop()
    self.timer:close()
    self.timer = nil
end

-- @param bufnr buffer number of the popup
-- @function start the animation
function M.Animation:start()
    if self.timer ~= nil then -- reset timer
        self.timer = nil
    end

    if self.state.sleeping then
        self.current_action = get_sleeping_animation()
    else
        self.current_action = self.current_action or "idle"
    end

    if not self.state.paused and not self.state.hidden then
        M.Animation.start_timer(self)
    elseif self.state.paused and not self.state.hidden then
        vim.schedule(function()
            M.Animation.next_frame(self)
        end)
    end
end

-- @function called on every tick from the timer, go to the next frame
function M.Animation:next_frame()
    self.frame_counter = self.frame_counter + 1

    -- pouplate the buffer with spaces to avoid image distortion
    if self.popup.bufnr == nil or not vim.api.nvim_buf_is_valid(self.popup.bufnr) then
        return
    end
    vim.api.nvim_buf_set_lines(self.popup.bufnr, 0, -1, false, lines)
    if not self.current_image then
        self.frame_counter = 1
    else
        self.current_image:delete(0, { free = false })
    end
    if self.frame_counter > #self.frames[self.current_action] then -- true every 8 frames
        M.Animation.set_next_action(self)
        if self.dead then
            M.Animation.stop_timer(self)
            return
        end
        self.frame_counter = 1
    end
    -- frames contains the images for every action
    local image = self.frames[self.current_action][self.frame_counter]
    M.Animation.set_next_col(self)
    image:display(self.row, self.col, self.popup.bufnr, {})
    self.current_image = image
end

-- @function decide which action comes after the following
function M.Animation:set_next_action()
    if self.dying then
        if self.current_action == "die" then
            self.dead = true
            M.Animation.stop(self)
            self.popup:unmount()
        end
        self.current_action = "die"
        return
    end
    local next_actions = {
        crouch = { "liedown", "sneak", "sit" },
        idle = { "idle_blink", "walk", "sit" },
        idle_blink = { "idle", "walk", "sit" },
        liedown = { "sneak", "crouch" },
        sit = { "idle", "idle_blink", "crouch", "liedown" },
        sneak = { "crouch", "walk", "liedown" },
        walk = { "idle", "idle_blink" },
    }
    if self.state.sleeping then
        -- If the animation isn't currently a sleeping animtion, put the pet in it, otherwise loop the animation
        if not utils.table_includes(sleeping_animations, self.current_action) then
            self.current_action = get_sleeping_animation()
        end
    else
        if math.random() < 0.5 then
            self.current_action = next_actions[self.current_action][math.random(#next_actions[self.current_action])]
        end
    end
end

-- @function set horizontal movement per frame based on current action
function M.Animation:set_next_col()
    if self.current_action == "walk" then
        if self.col < self.popup.win_config.width - 8 then
            self.col = self.col + 1
        else
            self.col = M.base_col
        end
    elseif self.current_action == "sneak" or self.current_action == "crouch" then
        if self.col < self.popup.win_config.width - 8 then
            if self.frame_counter % 2 == 0 then
                self.col = self.col + 1
            end
        else
            self.col = M.base_col
        end
    end
end

function M.Animation:stop()
    if self.current_image then
        self.current_image:delete(0, { free = false })
    end
    if self.timer then
        self.timer:stop()
        self.timer:close()
        self.timer = nil
    end
end

function M.Animation:set_state(new_state)
    for key, value in pairs(new_state) do
        self.state[key] = value
    end

    if new_state.hidden ~= nil then
        if self.state.hidden then
            self:stop_timer()
            if self.current_image then
                self.current_image:delete(0, { free = false })
            end
            self.popup:unmount()
        else
            self.popup:mount()
            self:start()
        end
    elseif new_state.paused ~= nil then
        if self.state.paused then
            self:stop_timer()
        else
            if self.current_image then
                self.current_image:delete(0, { free = false })
            end
            self:start()
        end
    end
end

return M
