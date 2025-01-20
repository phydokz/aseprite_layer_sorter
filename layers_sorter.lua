
--[[
MIT License

Copyright (c) 2025 Pablo Henrick Diniz

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

Author: Pablo Henrick Diniz
Last Modified: January 17, 2025
Version: 1.0.1
]]

-- The plugin key is a unique identifier for the plugin
local plugin_key = "phydokz/layers_sorter"
-- Initialize variables for the dialog, site change event, last active sprite, and the sorted layers list
local dlg
local sitechange
local aftercommand
local last_sprite = app.sprite
local sprites = {}
local rows = 0
local ui_state = {}
local refreshing = false


-- Initialization function for the plugin

function init(plugin)
     -- Set default position for the dialog if not set
     if plugin.preferences.dialog_x == nil then plugin.preferences.dialog_x = 0 end
     if plugin.preferences.dialog_y == nil then plugin.preferences.dialog_y = 0 end
 
     -- Flag to check if the dialog is visible
     local visible = false
     -- Store the last sorted layers for comparison
 
     -- Function that saves the dialog's position when closed
     local function on_dialog_close()
         -- Save the dialog's current position to plugin preferences
         plugin.preferences.dialog_x = dlg.bounds.x
         plugin.preferences.dialog_y = dlg.bounds.y
         visible = false
     end
     
     -- Function to iterate through the layers recursively
     -- It processes each layer and its child layers (if any) in reverse order
     local function iterate_layers(layers, callback)
         -- Looping backwards through the layers
         for i = #layers, 1, -1 do
             local layer = layers[i]
             
             -- Check if the layer is a group
             if layer.isGroup then
                 -- Apply the callback to the group itself
                if callback(layer) == false then break end
                
                 -- Recursively iterate the layers within the group
                 iterate_layers(layer.layers, callback)
             else
                 -- Apply the callback to non-group layers
                 if callback(layer) == false then break end
             end
         end
     end

     -- hash function
     local function hash(str)
        local h = 5381;
    
        for c in str:gmatch"." do
            h = ((h << 5) + h) + string.byte(c)
        end
        return h
    end

    -- generate sprite id for control
    local function getSpriteId(sprite)
        local id = sprite.properties(plugin_key).id
        if id == nil then
            id = os.time() .. "_" .. tostring(math.random(1000, 9999))
            sprite.properties(plugin_key).id = id
        end

        return id
    end

   -- Function to check if an object is a layer (using its string representation)
    local function is_layer(layer)
        -- Check if the string representation of the object contains "Layer:"
        return string.find(tostring(layer), "Layer:") ~= nil
    end
    
    -- Function to get the full name of a layer, including parent layers if any
    local function get_layer_name(layer)
        local name = layer.name
        
        -- If the layer has a parent and the parent is a layer, append the parent's name to the current layer's name
        if is_layer(layer.parent) then
            name = get_layer_name(layer.parent) .. '/' .. name
        end
        
        -- Return the full name of the layer
        return name
    end
    
    --Retrieve layer by name
    local function get_layer_by_name(name)
        local l = nil
        iterate_layers(app.sprite.layers,function(layer)
            if get_layer_name(layer) == name then
                l = layer
                return false
            end
        end)
        return l
    end

   -- Function to collect layers recursively from the active sprite
    local function get_layers()
        -- If no active sprite exists, return an empty table
        if not app.sprite then return {} end

        local layers = {}

        -- Inner function to add a layer to the layers table
        local function get_layer(layer)
            table.insert(layers, layer)
        end

        -- Use the iterate_layers function to gather layers from the active sprite
        iterate_layers(app.sprite.layers, get_layer)
        
        return layers
    end

    -- get layers names
    local function get_layers_names(layers)
        local names = {}
        for _,layer in ipairs(layers) do
            table.insert(names,get_layer_name(layer))
        end
        return names
    end

    -- Function to get the position (index) of an item in a table
    local function index_of(t, v)
        -- Iterate over the table and return the index of the value if found
        for index, value in ipairs(t) do
            if value == v then
                return index
            end
        end

        -- Return -1 if the value was not found
        return -1
    end

    -- get sprite id
    function getSpriteId(sprite)
        local index = index_of(sprites,sprite)
        if index == -1 then
            table.insert(sprites,sprite)
            index = #sprites
        end
        return tostring(index)
    end


    -- Function to get or set the default value of the sorting property on a layer
    local function get_layer_sort_property(layer, frame, layers)
        -- Retrieve the sorting properties for the given layer and frame
        local properties = layer.properties(plugin_key).sort or {}

        -- If the layer does not have a sort value for this frame, set it
        if properties[frame] == nil then
            -- Set the sort value to the layer's index in the layers table
            properties[frame] = index_of(layers, layer)

            -- Update the layer's properties with the new sort value
            layer.properties(plugin_key, { sort = properties })
        end
        -- Return the sort value for the current frame
        return properties[frame]
    end

    function clone_table(t)
        local cloned = {}

        for _,item in ipairs(t) do
            table.insert(cloned,item)            
        end

        return cloned
    end

    -- Function to update the sorted layers based on the sort properties
    local function update_sorted_layers()
        -- If no active sprite exists, return an empty table
        if not app.sprite then return {} end

        -- Get the current frame number as a string
        local frame = tostring(app.frame.frameNumber)

        -- Retrieve all layers
        local layers = get_layers()

        -- Copy the layers into the sorted_layers table
        local sorted_layers = get_layers()

        -- Sort the layers based on their sort properties for the current frame
        table.sort(sorted_layers,
            function(layer1, layer2)
                -- Retrieve the sort property for both layers
                local indexA = get_layer_sort_property(layer1, frame, layers)
                local indexB = get_layer_sort_property(layer2, frame, layers)

                -- Compare the sort properties and return true if layer1 should come before layer2
                return indexA < indexB
            end
        )

        local names =  get_layers_names(sorted_layers)

        app.sprite.properties(plugin_key).sorted_layers = names

        -- Update the layers' sort properties with the new sorted order
        for index, layer in ipairs(sorted_layers) do
            local sort = layer.properties(plugin_key).sort or {}
            sort[frame] = index

            -- Remove deleted frames from the layer's sorting data
            for key, _ in pairs(sort) do
                local num = tonumber(key)
                -- If the frame number is greater than the total number of frames, remove it
                if num > #app.sprite.frames then
                    sort[key] = nil
                end
            end

            -- Update the layer's properties with the modified sort data
            layer.properties(plugin_key, { sort = sort })
        end
    end



    -- Function to update the z-index of each cell in the layers based on their sorted order
    local function update_cell_zindexes()
        -- Retrieve all layers from the active sprite
        local layers_names = get_layers_names(get_layers())
        local sorted_layers_names = app.sprite.properties(plugin_key).sorted_layers or {}
        
        -- Get the current frame number
        local frame = app.frame.frameNumber
        
        -- Inner function to process each layer and update the z-index of its cells
        local function processLayer(layer)
            -- Get the cell of the layer for the current frame
            local cell = layer:cel(frame)
            
            -- If the layer has a cell for the current frame, calculate the z-index
            if cell then
                local layer_name = get_layer_name(layer)
                local realIndex = index_of(layers_names, layer_name)  -- Get the real index of the layer
                local sortedIndex = index_of(sorted_layers_names, layer_name)  -- Get the sorted index of the layer
                
                -- Calculate the z-index based on the difference between the real and sorted indices
                local zIndex = realIndex - sortedIndex
                
                -- Update the z-index of the cell
                cell.zIndex = zIndex
            end
        end
        
        -- If there's an active sprite, process its layers
        if app.sprite then 
            iterate_layers(app.sprite.layers, processLayer) 
        end
        
        -- Refresh the app to apply the changes
        app.refresh()
    end

    -- Function to swap two layers by their indices in the sorted layers list
    local function swap_layers(i, j)
        app.transaction('swap layers',function()
            local sorted_layers_names = app.sprite.properties(plugin_key).sorted_layers or {}

           -- Retrieve all layers
           local layers_names = get_layers_names(get_layers())
           local layer1_name = sorted_layers_names[i]  -- Get the first layer to be swapped
           local layer2_name = sorted_layers_names[j]  -- Get the second layer to be swapped
   
           -- If both layers are valid (i.e., exist in the layers list)
           if index_of(layers_names, layer1_name) ~= -1 and index_of(layers_names, layer2_name) ~= -1 then
               -- Get the current frame number as a string
               local frame = tostring(app.frame.frameNumber)


               local layer1 = get_layer_by_name(layer1_name)
               local layer2 = get_layer_by_name(layer2_name)
               
               -- Retrieve the sorting properties for both layers
               local sortA = layer1.properties(plugin_key).sort
               local sortB = layer2.properties(plugin_key).sort
               
               -- Swap the sort values for the current frame between the two layers
               local tmp = sortA[frame]
               sortA[frame] = sortB[frame]
               sortB[frame] = tmp
               
               -- Update the layers' sorting properties with the swapped values
               layer1.properties(plugin_key, {sort = sortA})
               layer2.properties(plugin_key, {sort = sortB})
           end

           -- update sorted layers
            update_sorted_layers()
            -- Update the sorted layers and cell zIndexes
            update_cell_zindexes()
        end)

       
         -- Refresh the dialog to reflect the changes
         refresh_dialog()
    end

    --update dialog
    function refresh_dialog()
        if refreshing then return end
        refreshing = true

        local currentFrame = app.frame.frameNumber  -- Get the current frame number

        if dlg == nil then
            dlg = Dialog { 
                title = "Layer Order for Frame #" .. tostring(currentFrame),
                onclose = on_dialog_close  -- Set the onclose event to save the position when the dialog closes
            }
        else
            dlg:close()
            visible = true

            dlg:modify{
                title = "Layer Order for Frame #" .. tostring(currentFrame),
            }
        end


        local sorted_layers_names = app.sprite.properties(plugin_key).sorted_layers or {}
        local sprite_id = getSpriteId(app.sprite)

         -- Modify the dialog with the added layers
         for index, name in ipairs(sorted_layers_names) do
            local id = tostring(index)
            local state_hash = hash(id..'_'..name..'_'..sprite_id)

            -- Define functions for moving the new layer up or down
            local function move_up()
                if index > 1 then
                    swap_layers(index - 1, index)
                end
            end
            
            local function move_down()
                if index < #sorted_layers_names then
                    swap_layers(index, index + 1)
                end
            end

            if index <= rows then
                if ui_state[id] ~= state_hash then
                     -- modify layers
                    dlg:modify{
                        id = "move_up_" .. id,
                        label=name,
                        onclick = move_up,
                        visible=true
                    }

                    dlg:modify{
                        id = "move_down_" .. id,
                        onclick = move_down,
                        visible=true
                    }
                end
            else
                -- Add buttons for moving the new layer up or down
                dlg:button{
                    label=name,
                    id = "move_up_" .. id,
                    text = "▲",
                    onclick = move_up
                }

                dlg:button{
                    id = "move_down_" .. id,
                    text = "▼",
                    onclick = move_down
                }
                dlg:newrow({always = false})
                rows = math.max(rows,index)
            end

            ui_state[id] = state_hash
        end

        for index=#sorted_layers_names+1, rows do
            local id = tostring(index)

            dlg:modify{
                id = "move_up_" .. id,
                visible=false
            }

            dlg:modify{
                id = "move_down_" .. id,
                visible=false
            }

            ui_state[id] = nil
        end

        dlg:show{
            wait = false,
            autoscrollbars = true,
            bounds = Rectangle(plugin.preferences.dialog_x, plugin.preferences.dialog_y, 300, 300)
        }
       
        refreshing = false
    end


    -- Function to refresh the dialog when something changes (e.g., sprite or frame changes)
    sitechange = function(ev)
        -- If there is an active sprite and frame, and it's the same as the last sprite, refresh the dialog
        if app.sprite and app.frame and app.sprite == last_sprite then
            if visible then
                if ev.fromUndo == false then
                    app.transaction('sort layers',function()
                        update_sorted_layers()
                        update_cell_zindexes()
                    end)
                end
                refresh_dialog()
            end
        else
            if dlg ~= nil then
                dlg:close()
            end
        end

        -- Update the last sprite to the current one
        last_sprite = app.sprite
    end

    aftercommand = function(ev)
        if ev.name == "Undo" or ev.name == "Redo" then
            if visible  then
                refresh_dialog()
            end         
        end
    end

    -- Define the plugin command for sorting layers
    plugin:newCommand{
        id = "sort_layers",
        title = "Sort Layers",
        group = "frame_popup_properties",
        onclick = function()
            app.transaction('sort layers',function()
                update_sorted_layers()
                update_cell_zindexes()
            end)
          
            visible = true
            refresh_dialog()  -- Open the dialog when the command is triggered
        end,
        onenabled = function()
            return app.sprite ~= nil and app.frame ~= nil  -- Enable the command if there is an active sprite and frame
        end
    }

    -- Bind the sitechange function to the 'sitechange' event
    app.events:on('sitechange', sitechange)
    app.events:on("aftercommand",aftercommand)
end

-- Function to exit and clean up the plugin resources
function exit(plugin)
    -- If the dialog exists, close it and set it to nil
    if dlg ~= nil then
        dlg:close()  -- Close the dialog
    end

    -- If the 'sitechange' event listener is active, remove it and set it to nil
    if sitechange then
        app.events:off(sitechange)  -- Remove the event listener
    end

    if aftercommand then
        app.events.off(aftercommand)
    end
end
