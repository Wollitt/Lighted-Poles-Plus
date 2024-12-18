--[[ Copyright (c) 2017 Optera
* Part of Lighted Electric Poles +
*
* See LICENSE.md in the project directory for license information.
--]]

-- local logger = require("__OpteraLib__.script.logger")
local Filter_Poles = {{filter="type", type="electric-pole"}}
local Filter_Lamps = {{filter="type", type="lamp"}}

local function table_to_string(tbl)
  local result = ""
  for i, v in pairs(tbl) do
    result = result .. tostring(i) .. ": " .. tostring(v) .. ", "
  end
  return result
end

local function Pole_Created(event)
  local entity = event.created_entity or event.entity
  if entity and entity.valid and entity.type == "electric-pole" then
    -- upgrade planner only raises create events; find and destroy hidden lamps; also prevents multiple lamps on top of another
    local lamps = entity.surface.find_entities_filtered {name = storage.lamp_namelist, position = entity.position}
    for _, lamp in pairs(lamps) do
      -- log("removing hidden lamp "..lamp.name.." at "..entity.position.x..","..entity.position.y )
      lamp.destroy()
    end

    if storage.pole_lamp_dict[entity.name] then
      -- log("placing hidden lamp for "..entity.name.." at "..entity.position.x..","..entity.position.y )
      local lamp = entity.surface.create_entity{name = storage.pole_lamp_dict[entity.name], position = entity.position, force = entity.force}
      lamp.destructible = false
      lamp.minable = false
    end
  end
end

local function Pole_Removed(event)
  local entity = event.entity
  if entity and entity.valid and storage.pole_lamp_dict[entity.name] then
    local lamps = entity.surface.find_entities_filtered {name = storage.pole_lamp_dict[entity.name], position = entity.position}
    for _, lamp in pairs(lamps) do
      -- log("removing hidden lamp for "..entity.name.." at "..entity.position.x..","..entity.position.y )
      lamp.destroy()
    end
  end
end


--[[
Event table returned with the event
    player_index = player_index, --The index of the player who moved the entity
    moved_entity = entity, --The entity that was moved
    start_pos = position --The position that the entity was moved from
]]--
function EntityMoved(event)
  -- log(tostring(event.player_index)..", entity: "..tostring(event.moved_entity.name)..", new pos: "..event.moved_entity.position.x..","..event.moved_entity.position.y..", old pos: "..event.start_pos.x..","..event.start_pos.y)
  local entity = event.moved_entity

  if entity and entity.type == "electric-pole" and storage.pole_lamp_dict[entity.name] then
    local lamps = entity.surface.find_entities_filtered{name = storage.pole_lamp_dict[entity.name], position = event.start_pos}
    for _, lamp in pairs(lamps) do
      lamp.teleport(entity.position)
    end
  end

end

local function register_events()
  -- register creation events
  script.on_event( defines.events.on_built_entity, Pole_Created, Filter_Poles )
  script.on_event( defines.events.on_robot_built_entity, Pole_Created, Filter_Poles )
  script.on_event( {defines.events.script_raised_built, defines.events.script_raised_revive}, Pole_Created )

  -- register removal events
  script.on_event( defines.events.on_pre_player_mined_item, Pole_Removed, Filter_Poles )
  script.on_event( defines.events.on_entity_died, Pole_Removed, Filter_Poles )
  script.on_event( defines.events.on_robot_pre_mined, Pole_Removed, Filter_Poles )
  script.on_event( defines.events.script_raised_destroy, Pole_Removed )

  --register to PickerExtended
  if remote.interfaces["picker"] and remote.interfaces["picker"]["dolly_moved_entity_id"] then
    script.on_event(remote.call("picker", "dolly_moved_entity_id"), EntityMoved)
  end
  --register to PickerDollies
  if remote.interfaces["PickerDollies"] and remote.interfaces["PickerDollies"]["dolly_moved_entity_id"] then
    script.on_event(remote.call("PickerDollies", "dolly_moved_entity_id"), EntityMoved)
  end
end

local function initialize(event)
  -- Enable researched recipes
  for _, force in pairs(game.forces) do
    for _, tech in pairs(force.technologies) do
      if tech.researched then
        for _, effect in pairs(tech.prototype.effects) do
          if effect.type == "unlock-recipe" then
            local recipe = force.recipes[effect.recipe]
            if recipe then
              recipe.enabled = true
            end
          end
        end
      end
    end
  end

  -- build name lists for lighted poles and lamps
  local prototype_poles = prototypes.get_entity_filtered(Filter_Poles)
  local prototype_lamps = prototypes.get_entity_filtered(Filter_Lamps)
  storage.pole_lamp_dict = {}
  for _, pole in pairs(prototype_poles) do
    if string.find(pole.name, "lighted%-") and prototype_lamps[pole.name.."-lamp"] then
      storage.pole_lamp_dict[pole.name] = pole.name.."-lamp"
    end
  end
  -- log("[LEP+] DEBUG: pole names:"..serpent.block(storage.pole_lamp_dict))

  storage.pole_namelist = {}
  storage.lamp_namelist = {}
  for pole_name, lamp_name in pairs(storage.pole_lamp_dict) do
    table.insert(storage.pole_namelist, pole_name)
    table.insert(storage.lamp_namelist, lamp_name)
  end
end

-- take care of orphaned lamps and poles
-- removing all hidden lamps and placing them at lighted poles should be faster than checking for lamps without poles and poles without lamps
local function rebuild_lamps()
  -- replace existing lamps
  for _, surface in pairs(game.surfaces) do
    local lamps = surface.find_entities_filtered {name = storage.lamp_namelist}
    for _, lamp in pairs(lamps) do
      lamp.destroy()
    end

    local poles = surface.find_entities_filtered {name = storage.pole_namelist}
    for _, pole in pairs(poles) do
      local lamp = pole.surface.create_entity{name = pole.name.."-lamp", position = pole.position, force = pole.force}
      if lamp then
        lamp.destructible = false
        lamp.minable = false
      else
        game.print("[LEP+] Error creating lamp for pole "..tostring(pole.name).." on surface "..tostring(surface.name) )
      end
    end
  end
end


script.on_load(function()
  register_events()
end)

script.on_init(function()
  register_events()
  initialize()
end)

script.on_configuration_changed(function(event)
  register_events()
  initialize()
  rebuild_lamps()
end)