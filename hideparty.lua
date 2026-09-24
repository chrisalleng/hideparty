--[[
* Addons - Copyright (c) 2025 Ashita Development Team
* Contact: https://www.ashitaxi.com/
* Contact: https://discord.gg/Ashita
*
* This file is part of Ashita.
*
* Ashita is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* Ashita is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with Ashita.  If not, see <https://www.gnu.org/licenses/>.
--]]

--[[
* Local modification (v1.4):
*
* The fishing mini-games stamina bar is drawn inside one of the same game
* primitives this addon hides, so hiding the frames also hides the bar. The
* addon now tracks whether the fishing mini-game is running and temporarily
* restores the affected frames for its duration.
*
* Which frames get restored is controlled by '/hideparty fishing <mode>':
*
*   party0 - Restores only the main party frame. (default)
*   party1 - Restores only the first alliance frame.
*   party2 - Restores only the second alliance frame.
*   party  - Restores the party and both alliance frames.
*   target - Restores only the target frame.
*   all    - Restores every frame this addon hides.
*   off    - Original behaviour; nothing is restored while fishing.
*
* The stamina bar was confirmed in-game to live in the main party frame
* (party0), which is why that is the default. The other modes are kept so the
* behaviour can be adjusted without editing this file.
*
* The mini-game is detected by reading the local players entity status each
* frame and testing it against the clients fishing status ids. This is a direct
* read of the state the client itself uses, so it cannot drift out of sync and
* needs no packet tracking.
--]]

addon.name      = 'hideparty';
addon.author    = 'atom0s';
addon.version   = '1.4';
addon.desc      = 'Adds slash commands to hide, show, or toggle the games party frames.';
addon.link      = 'https://ashitaxi.com/';

require 'common';

local chat      = require 'chat';
local settings  = require 'settings';

-- Addon Default Settings
local default_settings = T{
    -- The frames to restore while the fishing mini-game is active.
    -- Valid values: 'party0', 'party1', 'party2', 'party', 'target', 'all', 'off'
    fishing_mode = 'party0',
};

-- Addon Variables
local hideparty = {
    show = 1,
    settings = settings.load(default_settings),
    ptrs = {
      target = 0,
      party0 = 0,
      party1 = 0,
      party2 = 0,
    },
};

-- The valid fishing modes, in display order..
local fishing_mode_names = T{ 'party0', 'party1', 'party2', 'party', 'target', 'all', 'off' };

-- The frame visibility each fishing mode restores..
local fishing_mode_frames = T{
    ['party']   = T{ party0 = 1, party1 = 1, party2 = 1, target = 0 },
    ['party0']  = T{ party0 = 1, party1 = 0, party2 = 0, target = 0 },
    ['party1']  = T{ party0 = 0, party1 = 1, party2 = 0, target = 0 },
    ['party2']  = T{ party0 = 0, party1 = 0, party2 = 1, target = 0 },
    ['target']  = T{ party0 = 0, party1 = 0, party2 = 0, target = 1 },
    ['all']     = T{ party0 = 1, party1 = 1, party2 = 1, target = 1 },
    ['off']     = T{ party0 = 0, party1 = 0, party2 = 0, target = 0 },
};

--[[
* The entity status ids the client uses while fishing.
*
* The client keeps a 16-byte-per-entry table of status names in FFXiMain.dll,
* indexed by the entity status value. The fishing entries are:
*
*    6 (FISHING)               Rod cast; line in the water.
*   38 - 43 (FISHING1..6)      Mini-game reeling states.
*   50 (FISH_2), 56 (FISH_3)   Catch / result states.
*   51 - 53 (FISHF/R/L)        Directional reeling states.
*   57 - 62 (FISH_31..36)      Catch / result states.
*
* Verified against the known ids in the same table: 1 (B_IDLE) is engaged,
* 33 (CAMP) is resting, and 85 (MOUNT) is mounted.
--]]
local fishing_statuses = T{
    [6]  = true,
    [38] = true, [39] = true, [40] = true, [41] = true, [42] = true, [43] = true,
    [50] = true, [51] = true, [52] = true, [53] = true,
    [56] = true, [57] = true, [58] = true, [59] = true, [60] = true, [61] = true, [62] = true,
};

--[[
* Prints the addon help information.
*
* @param {boolean} isError - Flag if this function was invoked due to an error.
--]]
local function print_help(isError)
    -- Print the help header..
    if (isError) then
        print(chat.header(addon.name):append(chat.error('Invalid command syntax for command: ')):append(chat.success('/' .. addon.name)));
    else
        print(chat.header(addon.name):append(chat.message('Available commands:')));
    end

    local cmds = T{
        { '/hideparty', 'Toggles the party frames visibility.' },
        { '/hideparty help', 'Displays the addons help information.' },
        { '/hideparty (hide | h)', 'Sets the party frames to be hidden.' },
        { '/hideparty (show | s)', 'Sets the party frames to be visible.' },
        { '/hideparty fishing', 'Displays the current fishing mini-game mode.' },
        { '/hideparty fishing (party0 | party1 | party2 | party)', 'Restores the given party frame(s) while the fishing mini-game is active.' },
        { '/hideparty fishing (target | all | off)', 'Restores the target frame, everything, or nothing while the fishing mini-game is active.' },
    };

    -- Print the command list..
    cmds:ieach(function (v)
        print(chat.header(addon.name):append(chat.error('Usage: ')):append(chat.message(v[1]):append(' - ')):append(chat.color1(6, v[2])));
    end);
end

--[[
* Sets a game primitives visibility.
*
* @param {number} p - The pointer of the primitive object.
* @param {boolean} v - The visibility status to set.
--]]
local function set_primitive_visibility(p, v)
    local ptr = ashita.memory.read_uint32(p);
    if (ptr ~= 0) then
        ptr = ashita.memory.read_uint32(ptr + 0x08);
        if (ptr ~= 0) then
            ashita.memory.write_uint8(ptr + 0x69, v);
            ashita.memory.write_uint8(ptr + 0x6A, v);
        end
    end
end

-- Every frame hidden; used when nothing needs restoring..
local frames_hidden = T{ party0 = 0, party1 = 0, party2 = 0, target = 0 };

-- Every frame visible; used when the addon is not hiding anything..
local frames_visible = T{ party0 = 1, party1 = 1, party2 = 1, target = 1 };

--[[
* Returns true if the local player is currently fishing.
*
* @return {boolean} True if the fishing mini-game is active, false otherwise.
--]]
local function is_fishing()
    local player = GetPlayerEntity();
    if (player == nil) then
        return false;
    end

    return fishing_statuses[player.Status] == true;
end

--[[
* Returns the visibility to apply to each frame this frame.
*
* @return {table} Table of per-frame visibility values.
--]]
local function get_visibility()
    -- Frames are not being hidden at all..
    if (hideparty.show) then
        return frames_visible;
    end

    -- Temporarily restore frames while the fishing mini-game is running so its
    -- stamina bar is not hidden along with them..
    if (is_fishing()) then
        return fishing_mode_frames[hideparty.settings.fishing_mode] or frames_hidden;
    end

    return frames_hidden;
end

--[[
* event: settings
* desc : Event called when the addon settings are updated.
--]]
settings.register('settings', 'settings_update', function (s)
    if (s ~= nil) then
        hideparty.settings = s;
    end

    -- Guard against a hand-edited configuration file..
    if (fishing_mode_frames[hideparty.settings.fishing_mode] == nil) then
        hideparty.settings.fishing_mode = default_settings.fishing_mode;
    end

    settings.save();
end);

--[[
* event: load
* desc : Event called when the addon is being loaded.
--]]
ashita.events.register('load', 'load_cb', function ()
    -- Find the needed pointers for the main party and target frames..
    local ptr1 = ashita.memory.find(0, 0, '66C78182000000????C7818C000000????????C781900000', 0, 0);
    if (ptr1 == 0) then
        error(chat.header(addon.name):append(chat.error('Error: Failed to locate required pointer. (1)')));
    end

    -- Find the needed pointers for the alliance party frames..
    local ptr2 = ashita.memory.find(0, 0, 'A1????????8B0D????????89442424A1????????33DB89', 0, 0);
    if (ptr2 == 0) then
        error(chat.header(addon.name):append(chat.error('Error: Failed to locate required pointer. (2)')));
    end

    -- Read the base object pointers..
    hideparty.ptrs.party0 = ashita.memory.read_uint32(ptr1 + 0x19);
    hideparty.ptrs.target = ashita.memory.read_uint32(ptr1 + 0x23);
    hideparty.ptrs.party1 = ashita.memory.read_uint32(ptr2 + 0x01);
    hideparty.ptrs.party2 = ashita.memory.read_uint32(ptr2 + 0x07);

    set_primitive_visibility(hideparty.ptrs.party0, 1);
end);

--[[
* event: command
* desc : Event called when the addon is processing a command.
--]]
ashita.events.register('command', 'command_cb', function (e)
    -- Parse the command arguments..
    local args = e.command:args();
    if (#args == 0 or not args[1]:any('/hideparty')) then
        return;
    end

    -- Block all related commands..
    e.blocked = true;

    -- Handle: /hideparty - Toggles the party frames visibility.
    if (#args == 1) then
        hideparty.show = not hideparty.show;
        return;
    end

    -- Handle: /hideparty help - Shows the addon help.
    if (#args == 2 and args[2]:any('help')) then
        print_help(false);
        return;
    end

    -- Handle: /hideparty hide - Hides the party frames.
    if (#args == 2 and args[2]:any('hide', 'h')) then
        hideparty.show = false;
        return;
    end

    -- Handle: /hideparty show - Shows the party frames.
    if (#args == 2 and args[2]:any('show', 's')) then
        hideparty.show = true;
        return;
    end

    -- Handle: /hideparty fishing - Shows the current fishing mini-game mode.
    if (#args == 2 and args[2]:any('fishing')) then
        print(chat.header(addon.name):append(chat.message('Fishing mini-game mode: ')):append(chat.success(hideparty.settings.fishing_mode)));
        return;
    end

    -- Handle: /hideparty fishing <mode> - Sets the fishing mini-game mode.
    if (#args == 3 and args[2]:any('fishing')) then
        local mode = args[3]:lower();
        if (fishing_mode_frames[mode] == nil) then
            print(chat.header(addon.name):append(chat.error('Invalid fishing mode: ')):append(chat.message(args[3])));
            print(chat.header(addon.name):append(chat.message('Valid modes: ')):append(chat.success(fishing_mode_names:join(', '))));
            return;
        end

        hideparty.settings.fishing_mode = mode;
        settings.save();

        print(chat.header(addon.name):append(chat.message('Fishing mini-game mode set to: ')):append(chat.success(mode)));
        return;
    end

    -- Unhandled: Print help information..
    print_help(true);
end);

--[[
* event: d3d_present
* desc : Event called when the Direct3D device is presenting a scene.
--]]
ashita.events.register('d3d_present', 'present_cb', function ()
    local frames = get_visibility();

    set_primitive_visibility(hideparty.ptrs.party0, frames.party0);
    set_primitive_visibility(hideparty.ptrs.party1, frames.party1);
    set_primitive_visibility(hideparty.ptrs.party2, frames.party2);
    set_primitive_visibility(hideparty.ptrs.target, frames.target);
end);
