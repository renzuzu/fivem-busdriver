
BusStop = {}
BusStop.Models = { 'prop_busstop_05', 'prop_busstop_02', 'prop_busstop_04', 'prop_bus_stop_sign' }
BusStop.Size = { width = 3.5, length= 13.0 }

-- List of blips that have been generated.
BusStop.Blips = {}
-- List of all stops (used for debug rendering)
BusStop.Stops = {}

-- Finds the nearest bus stop model with 25m.
--  Coords is optional
BusStop.FindNearestModel = function(coords) 
    return FindClosestObject(BusStop.Models, 25, coords)
end

-- Requests a new stop to be created
BusStop.RequestCreateStop = function(identifingCoordinate, stopCoordinate, heading, name, callback)
    if queue == nil then queue = vector3(0, 0, 0) end
    
    -- Send the message to the server. Once we get a call back we will log it
    print('Requesting new bus stop', identifingCoordinate, stopCoordinate, heading, name)
    ESX.TriggerServerCallback(E.CreateBusStop, function(hash)
        BusStop.RequestAllStops()
        if callback then callback(hash) end
    end, identifingCoordinate, stopCoordinate, heading, name)
end

-- Gets a list of bus stops
BusStop.RequestAllStops = function(callback) 
    ESX.TriggerServerCallback(E.GetBusStops, function(stops)
        BusStop.Stops = stops
        
        if Config.alwaysShowBlips then
            for _, stop in pairs(stops) do
                BusStop.ShowBlip(stop)
            end
        end

        if callback then  callback(stops) end
    end)
end

-- Registers the events
BusStop.RegisterEvents = function(ESX)
    -- For debugging purposes
    BusStop.RequestAllStops()
end

-- Shows a bus stop's blip
BusStop.ShowBlip = function(stop, visible) 
    if stop == nil then print('BusStop', 'warning: stop is nil') return false end
    if visible == nil then visible = true end
    
    -- Blip is already hidden, no action required
    if visible == false and BusStop.Blips[stop.id] == nil then
        return
    end

    -- Ensure the blip exists
    if BusStop.Blips[stop.id] == nil then
        BusStop.Blips[stop.id] = CreateBlip(513, stop, "Bus Stop", 0.9, 0)
    end

    -- Set the blip's display state
    if visible then
        SetBlipDisplay(BusStop.Blips[stop.id], 4)
    else
        SetBlipDisplay(BusStop.Blips[stop.id], 0)
    end
end

-- Hides a bus stop's blip
BusStop.HideBlip = function(stop) 
    return BusStop.ShowBlip(stop, false)
end

-- Renders the stops
BusStop.RenderAll = function(color)
    for k, stop in pairs(BusStop.Stops) do
        BusStop.Render(stop, color)
    end
end

-- Gets the stop coordinates
BusStop.GetStopCoords = function(stop) 
    if stop == nil then print('BusStop', 'warning: stop is nil') return vector3(0,0,0) end
    return vector3(stop.x+.0, stop.y+.0, stop.z+.0)
end

-- Gets the queue coordinates
BusStop.GetQueueCoords = function(stop) 
    -- Prepare the queue
    if stop == nil then print('BusStop', 'warning: stop is nil') return vector3(0,0,0) end
    if stop.hasQueue then 
        return vector3(stop.qx+.0, stop.qy+.0, stop.qz+.0)
    end
    
    -- Find the default position
    local stopCoords = BusStop.GetStopCoords(stop)
    local qForward = quat(stop.heading, vector3(0, 0, 1))
    local qRight = quat(stop.heading-90, vector3(0, 0, 1))
    stopCoords = stopCoords 
                    + ((qForward * vector3(0, 1, 0)) * (BusStop.Size.length * 0.5 - 1.5)) 
                    + ((qRight * vector3(0, 1, 0)) * (BusStop.Size.width * 0.5 + 1.0))

    -- Try to find the safest coord near that
    local isStopSafe, safeCoords = GetSafeCoordForPed(stopCoords.x, stopCoords.y, stopCoords.z, true, 1)
    if isStopSafe then return safeCoords end

    -- Find a new spot based around the edge of the stop
    return stopCoords
end

-- Render a specific stop. Color is optional
BusStop.Render = function(stop, color)
    if color == nil then color = { r = 255, g = 255, b = 0 } end
    
    -- Draw the bus zone
    BusStop.DrawZone(stop, stop.heading, color)

    -- Draw the text above the bus zone
    local model = BusStop.FindNearestModel(stop)
    local textCoord = stop
    if model then textCoord = GetEntityCoords(model) end
    
    textCoord = vector3(textCoord.x+.0, textCoord.y+.0, textCoord.z+4.25)
    DrawText3D(textCoord, tostring(stop.id) .. ' | ' .. stop.name, 3)

    -- Draw some debug markers
    if Config.debug then
        local stopCoord = BusStop.GetStopCoords(stop)

        local qForward = quat(stop.heading, vector3(0, 0, 1))
        local qRight = quat(stop.heading-90, vector3(0, 0, 1))
        DrawQuaternion(stopCoord, qForward, {r=255, g=0, b=0})
        DrawQuaternion(stopCoord, qRight, {r=0, g=255, b=0})
        
        DrawHeadingMarker(stopCoord, stop.heading, Config.stopDistanceLimit or 1.0, color)

        local queueColor = { r=255, g=0, b=0 }
        if stop.hasQueue then queueColor = { r=0, g=255, b=0 } end
        DrawGroundedZoneMarker(BusStop.GetQueueCoords(stop), 1.0, queueColor)
    end
end

-- Drwas a rectangular zone marker, snapped ot the ground
BusStop.DrawZone = function(coordinate, heading, color) 
    -- Draw the rectangle
    local depth = 0.5
    local height = 1.0
    local size = { x = BusStop.Size.width, y = BusStop.Size.length, z = height }

    --Draw the position
    local rotation = { x = .0, y = .0, z = heading + .0 }
    local position = { x=coordinate.x, y=coordinate.y, z=coordinate.z }
    
    local hasGround, groundZ, normal = GetGroundZAndNormalFor_3dCoord(position.x, position.y, position.z, 0)
    if hasGround then 
        position.z = groundZ - depth
        
        -- if Config.debug and DEBUG_FindStops then
        --     local qHeading = quat(heading, vector3(0, 0, 1))
        --     DrawQuaternion(coordinate, qHeading, {r=255, g=0, b=0})
        --     
        --     local qRoad = quat(vector3(0, 1, 0), normal)
        --     DrawQuaternion(coordinate, qRoad, {r=0, g=255, b=0})
-- 
        --     -- We need to rotate qRoad 90deg in the direction of qHeading
        --     local qNew = qRoad * quat(90, vector3(1, 0, 0))
        --     DrawQuaternion(coordinate, qNew, {r=0, g=0, b=255})
        -- end
    end

    DrawMarker(43, 
        position.x + .0, position.y+ .0, position.z + .0, -- Position
        0.0, 0.0, 0.0,                               -- Direction
        rotation.x, rotation.y, rotation.z,                      -- Rotation
        size.x+ .0, size.y+ .0, size.z+ .0,          -- Scale
        color.r, color.g, color.b, 0.01,             -- Color
        0, 0, 0, 0, 0, 0, 0
    )
end

