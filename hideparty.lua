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
* Local modification (v1.5):
*
* The fishing mini-games stamina bar is drawn inside the main party frames
* primitive, so hiding the frames also hides the bar and leaves you reeling
* blind. That frame is now kept visible while the mini-game is running; the
* alliance and target frames stay hidden.
*
* The mini-game is detected by reading the local players entity status, which
* is the same value the client itself uses to decide what the player is doing.
--]]

addon.name      = 'hideparty';
addon.author    = 'atom0s';
addon.version   = '1.5';
addon.desc      = 'Adds slash commands to hide, show, or toggle the games party frames.';
addon.link      = 'https://ashitaxi.com/';

require 'common';

local chat = require 'chat';

-- Addon Variables
local hideparty = {
    show = 1,
    ptrs = {
      target = 0,
      party0 = 0,
      party1 = 0,
      party2 = 0,
    },
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

    -- Unhandled: Print help information..
    print_help(true);
end);

--[[
* event: d3d_present
* desc : Event called when the Direct3D device is presenting a scene.
--]]
ashita.events.register('d3d_present', 'present_cb', function ()
    -- The fishing mini-games stamina bar is drawn inside the main party frames
    -- primitive, so keep that frame visible while the mini-game is running..
    local show_party0 = hideparty.show or is_fishing();

    set_primitive_visibility(hideparty.ptrs.party0, show_party0 and 1 or 0);
    set_primitive_visibility(hideparty.ptrs.party1, hideparty.show and 1 or 0);
    set_primitive_visibility(hideparty.ptrs.party2, hideparty.show and 1 or 0);
    set_primitive_visibility(hideparty.ptrs.target, hideparty.show and 1 or 0);
end);