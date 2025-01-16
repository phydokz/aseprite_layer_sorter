local plugin_key = "phydokz/layers_sorter"
local dlg
local sitechange
local last_sprite = app.activeSprite
local sorted_layers = {}

function init(plugin)
    if plugin.preferences.dialog_x == nil then plugin.preferences.dialog_x = 0 end

    if plugin.preferences.dialog_y == nil then plugin.preferences.dialog_y = 0 end

    local visible = false
    local last_sorted_layers = {}

    -- save last dialog position on dialog close
    local function on_dialog_close()
        plugin.preferences.dialog_x = dlg.bounds.x
        plugin.preferences.dialog_y = dlg.bounds.y
        visible = false
    end
    
      -- Function to iterate layers recursively
    local function iterate_layers(layers, callback)
        for i = #layers, 1, -1 do  -- Loop from the end to the beginning
            local layer = layers[i]

            if layer.isGroup then
                callback(layer) -- Apply the callback to the group itself
                -- Recursively iterate the layers within the group, also from back to front
                iterate_layers(layer.layers, callback)
            else
                callback(layer) -- Apply the callback to non-group layers
            end
         end
    end
    
    -- collect layers recursively
    local function get_layers()
        if not app.activeSprite then return {} end
    
        local layers = {}
    
        local function get_layer(layer)
            table.insert(layers,layer)
        end
    
        iterate_layers(app.activeSprite.layers, get_layer)
        
        return layers
    end

    -- get position of a item on a table object
    local function index_of(t,v)
        for index, value in ipairs(t) do
            if value == v then
                return index
            end
        end
    
        return -1
    end
    
    -- get / set default value of sorting property on layer 
    local function get_layer_sort_property(layer, frame, layers)
        local properties = layer.properties(plugin_key).sort or {}
        if properties[frame] == nil then
            properties[frame] = index_of(layers, layer)

            layer.properties(plugin_key, { sort = properties })
        end
        return properties[frame]
    end

    -- update sorted layers
    local function update_sorted_layers()
        if not app.activeSprite then return {} end

        local frame = tostring(app.activeFrame.frameNumber)
        local layers = get_layers()

        sorted_layers = get_layers()
        

        -- sort layers by layer sort config
        table.sort(sorted_layers,
            function(layer1,layer2)
                local indexA = get_layer_sort_property(layer1, frame, layers)
                local indexB = get_layer_sort_property(layer2, frame, layers)
                
                return indexA < indexB
            end
        )

        for index,layer in ipairs(sorted_layers) do
            local sort = layer.properties(plugin_key).sort
            sort[frame] = index

            --remove deleted frames from layers sorting data
            for key, _ in pairs(sort) do
                local num = tonumber(key)
                if num > #app.activeSprite.frames then
                    sort[key] = nil
                end
            end

            layer.properties(plugin_key,{sort=sort})
        end
    end
    
    -- check if object is a layer
    local function is_layer(layer)
        return string.find(tostring(layer),"Layer:") ~= nil
    end
    

    -- get full layer name
    local function get_layer_name(layer)
        local name = layer.name
    
        if is_layer(layer.parent) then
            name = get_layer_name(layer.parent) .. '/' .. name
        end
    
        return name
    end

    -- update cells zindexes
    local function update_cell_zindexes()
        local layers = get_layers()
    
        local frame = app.activeFrame.frameNumber
    
        local function processLayer(layer)
            local cell = layer:cel(frame)
    
            if cell then
                local realIndex = index_of(layers,layer)
                local sortedIndex = index_of(sorted_layers,layer)
        
                local zIndex = realIndex - sortedIndex
    
                cell.zIndex = zIndex
            end
        end
    
        if app.activeSprite then iterate_layers(app.activeSprite.layers, processLayer) end
    
        app.refresh()
    end


    -- switch two layers 
    local function switch_layers(i,j)
        local layers = get_layers()
        local layer1 = sorted_layers[i]
        local layer2 = sorted_layers[j]

        if index_of(layers,layer1) ~= -1 and index_of(layers,layer2) ~= -1 then
            local frame = tostring(app.activeFrame.frameNumber)
            local sortA = layer1.properties(plugin_key).sort
            local sortB = layer2.properties(plugin_key).sort
            local tmp = sortA[frame]
            sortA[frame] = sortB[frame]
            sortB[frame] = tmp
            layer1.properties(plugin_key,{sort=sortA})
            layer2.properties(plugin_key,{sort=sortB})
        end
    
        
        refresh_dialog()
    end

    -- update dialog ui list of layers
    function refresh_dialog()
        local currentFrame = app.activeFrame.frameNumber
        if dlg == nil then
            dlg = Dialog { 
                title = "Layer Order for Frame #" .. tostring(currentFrame),
                onclose=on_dialog_close
            }
        else
            dlg:modify{
                title = "Layer Order for Frame #" .. tostring(currentFrame)
            }
        end

        dlg:close()
        visible = true

        last_sorted_layers = sorted_layers
       
        update_sorted_layers()
        update_cell_zindexes()

        -- compute changed, added and hidden layers
        local changed = {}
        local added = {}
        local hidden = {}
        
        for index, layer in ipairs(sorted_layers) do
            if index <= #last_sorted_layers then
                local layer2 = last_sorted_layers[index]
                if layer ~= layer2 then
                    table.insert(changed,{
                        layer=layer,
                        index=index
                    })
                end
            else
                table.insert(added,{
                    layer=layer,
                    index=index
                })
            end
        end

        for i = #sorted_layers + 1, #last_sorted_layers do
            table.insert(hidden,{
                layer=last_sorted_layers[i],
                index=i
            })
        end


        -- modify dialog with changed data
        for _, data in ipairs(changed) do
            local index = data.index
            local layer = data.layer
            local id = tostring(index)

            dlg:modify{
                id="separator_"..id,
                text=get_layer_name(layer),
                visible=true
            }

            local function move_up()
                if index > 1 then
                   switch_layers(index - 1, index)
                end
            end
            
            local function move_down()
                if index < #sorted_layers then
                    switch_layers(index, index+1)
                end
            end
    
            dlg:modify{
                id="move_up_"..id,
                text="▲",
                onclick=move_up,
                visible=true
            }
    
            dlg:modify{
                id="move_down_"..id,
                text="▼",
                onclick=move_down,
                visible=true
            }
        end

        for _, data in ipairs(added) do
            local index = data.index
            local layer = data.layer
            local id = tostring(index)

            dlg:separator{
                id="separator_"..id,
                text=get_layer_name(layer)
            }

            local function move_up()
                if index > 1 then
                   switch_layers(index - 1, index)
                end
            end
            
            local function move_down()
                if index < #sorted_layers then
                    switch_layers(index, index+1)
                end
            end
    
            dlg:button{
                id="move_up_"..id,
                text="▲",
                onclick=move_up
            }
    
            dlg:button{
                id="move_down_"..id,
                text="▼",
                onclick=move_down
            }
        end


        for _, data in ipairs(hidden) do
            local index = data.index
            local id = tostring(index)

            dlg:modify{
                id="separator_"..id,
                visible=false
            }

    
            dlg:modify{
                id="move_up_"..id,
                visible=false
            }
    
            dlg:modify{
                id="move_down_"..id,
                visible=false
            }
        end


        dlg:show{
            wait = false,
            autoscrollbars=true,
            bounds=Rectangle(plugin.preferences.dialog_x,plugin.preferences.dialog_y,300,300)
        }
    end


    -- refresh dialog when something changes
    sitechange = function()
        if app.activeSprite ~= nil and  app.activeFrame ~= nil and app.activeSprite == last_sprite then
            if visible then
                refresh_dialog()
            end
        elseif dlg ~= nil then
            dlg:close()
        end

        last_sprite = app.activeSprite
    end
    
    plugin:newCommand{
        id="sort_layers",
        title="Sort Layers",
        group="frame_popup_properties",
        onclick=function()
            visible = true
            refresh_dialog()
        end,
        onenabled=function()
            return app.activeSprite ~= nil and  app.activeFrame ~= nil
        end
    }

    app.events:on('sitechange',sitechange)
end

function exit(plugin)
    if dlg ~= nil then
        dlg:close()
        dlg = nil
    end

    if sitechange ~= nil then
        app.events:off('sitechange',sitechange)
        sitechange = nil
    end
end
