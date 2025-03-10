--[[
    This file handles a collection of common utilities for Peds
]]

Ped = {}
Ped.maxSpawnAttempts = 100  -- How many MS we are willing to wait for it to load
Ped.defaultVehicleTimeout = Config.pedVehicleTimeout or 5.0

Ped._spawn = {}

Ped.WALK = 1.0
Ped.RUN = 2.0
Ped.TELEPORT = 999.0

-- Gets a random ped model
Ped.RandomModel = function() 
    -- TODO: Ensure we dont reuse peds
    return Ped.models[math.random(#Ped.models)]
end

--- Spawns a ped. Does it on current thread
-- @params model the name of the model
-- @params coords the coordinates
-- @params networked the optional boolean to determine if it should be networked (default) or not.
Ped.Spawn = function(model, coords, callback, networked)
    local hash = GetHashKey(model)
    local spawnAttempts = Ped.maxSpawnAttempts
    
    --Ensure the network argument
    if networked == nil then networked = true end

    print('Spawning Ped: ', model, hash, coords, networked)

    local load = function() 
        -- Load the model
        RequestModel(hash)
        while not HasModelLoaded(hash) and spawnAttempts > 0 do
            spawnAttempts = spawnAttempts - 1
            Citizen.Wait(5)
        end

        if spawnAttempts <= 0 then
            print('warning: failed to load the model', model, hash, 'max attempts: ' .. tostring(Ped.maxSpawnAttempts))
            return nil
        end

        -- Determine where to spawn the ped
        local coordHeading = EnsureCoordinateHeading(coords)

        -- Create the ped
        local ped = CreatePed(4, hash, coordHeading.x+.0, coordHeading.y+.0, coordHeading.z+.0, coordHeading.w+.0, networked, false)
        if ped == 0 then 
            print('warning: failed to create the ped', model, coordHeading)
            return nil
        end

        -- Wait a bit before the callback, to ensure the ped is ready
        return ped
    end

    if callback ~= nil then
        Citizen.CreateThread(function()
           callback(load()) 
        end)
    else
        return load()
    end
end

-- Spawns a random ped that is networked
Ped.SpawnRandom = function(coords, callback)
    local model = Ped.RandomModel()
    return Ped.Spawn(model, coords, callback, true)
end

-- Spawns a random ped that is not networked
Ped.SpawnRandomLocal = function(coords, callback) 
    local model = Ped.RandomModel()
    return Ped.Spawn(model, coords, callback, false)
end

--- Tells the ped to navigate to the specific coordinates using the navmesh
-- @params ped the ped
-- @params coords the coordinates
-- @params speed how fast. Use Ped.WALK, Ped.RUN, or Ped.TELEPORT. Default: Ped.WALK
-- @params withinRange Optional. how close the ped must be before stopping. Default: 1
-- @params timeout Optional. how long in seconds before they give up. If no timeout, set to -1. Default: 1
Ped.NavigateTo = function(ped, coords, speed, withinRange, timeout)
    if ped == nil or ped == 0 then print('error: NavigateTo: ped is empty.') return false end
    if timeout == nil then timeout = -1 end
    if withinRange == nil then withinRange = 1.0 end
    if speed == nil then speed = Ped.WALK end
    if speed >= Ped.TELEPORT then
        print('Teleport Ped:', ped, coords)
        SetEntityCoords(ped, coords.x+.0, coords.y+.0, coords.z+.0, false, false, false, false)
    else
        print('Navigate Ped:', ped, coords, speed, withinRange, timeout)
        TaskFollowNavMeshToCoord(ped, coords.x+.0, coords.y+.0, coords.z+.0, speed, timeout, withinRange+.0, false)
    end
end

--- Tells the ped to enter the vehicle
-- @params ped the ped
-- @params vehicle the vehicle
-- @params seat the seat. If the seat is occupied, this function will return false. Default: 0
-- @params speed how fast. Use Ped.WALK, Ped.RUN, or Ped.TELEPORT. Default: Ped.WALK
-- @params timeout Optional. how long in seconds before they give up. If no timeout, set to -1. Default: 1
-- @params priority Should this task override existing tasks. Default: true
Ped.EnterVehicle = function(ped, vehicle, seat, speed, timeout, priority)
    if ped == nil or ped == 0 then print('error: EnterVehicle: ped is empty.') return false end
    if seat == nil then seat = 0 end
    if speed == nil then speed = Ped.WALK end
    if timeout == nil then timeout = Ped.defaultVehicleTimeout end
    if priority == nil then priority = true end

    -- Ensure the vehicle
    if vehicle == nil or vehicle == 0 then
        print('warning: ped cannot enter nil vehicles.')
        return false
    end

    -- Ensure the seat
    if not IsVehicleSeatFree(vehicle, seat, false) then
        print('warning: ped cannot sit in seat because it is already occupied: ', seat)
        return false
    end

    -- Clear the ped's previous task
    if priority then
        ClearPedTasksImmediately(ped) 
    end

    -- Tell them to get in the damn car
    if speed >= Ped.TELEPORT then
        print('Enter Ped (TP):', ped, vehicle, seat, speed, timeout, priority)
        TaskWarpPedIntoVehicle(ped, vehicle, seat)
    else
        print('Enter Ped:', ped, vehicle, seat, speed, timeout, priority)
        TaskEnterVehicle(ped, vehicle, timeout, seat, speed+.0, 1, 0)
    end

    -- Success
    return true
end

--- Asks the ped to leave the vehicle
-- @params ped the ped
-- @params style the way to exit the vehicle. See TaskLeaveVehicle.
--              0 = normal exit and closes door.  
--              1 = normal exit and closes door.  
--              16 = teleports outside, door kept closed.  
--              64 = normal exit and closes door, maybe a bit slower animation than 0.  
--              256 = normal exit but does not close the door.  
--              4160 = ped is throwing himself out, even when the vehicle is still.  
--              262144 = ped moves to passenger seat first, then exits normally  
-- @params vehicle the vehicle to exit out of. If nil then it will be the last vehicle the ped is in.
Ped.ExitVehicle = function(ped, style, vehicle) 
    if ped == nil or ped == 0 then print('error: ExitVehicle: ped is empty.') return false end
    if style == nil then style = 1 end
    if vehicle == nil then vehicle = GetVehiclePedIsIn(ped, true) end
    if vehicle == nil or vehicle == 0 then
        print('warning: ped was never in a vehicle')
        return false
    end

    -- Clear task and get them to then leave
    print('Exit Ped:', ped)
    TaskLeaveVehicle(ped, vehicle, style)
    return true
end

--- Tells GTA they can elegantly clean up this ped
Ped.Remove = function(ped) 
    if ped == nil or ped == 0 then print('error: Remove: ped is empty.') return false end
    
    print('Remove Ped:', ped)
    RemovePedElegantly(ped)
end

--- Makes the ped wander away and eventually get deleted
Ped.WanderAway = function(ped)
    if ped == nil or ped == 0 then print('error: WanderWay: ped is empty.') return false end
    
    print('Wander Ped:', ped)
    TaskWanderStandard(ped, 10.0, 10)
    Ped.Remove(ped)
end

-- Checks if the ped is in the vehicle
Ped.InVehicle = function(ped, vehicle, asGetIn)
    if ped == nil or ped == 0 then print('error: InVehicle: ped is empty.') return false end
    if asGetIn == nil then asGetIn = true end
    if vehicle == nil then vehicle = GetVehiclePedIsIn(ped, true) end
    if vehicle == nil or vehicle == 0 then return false end
    
    return IsPedInVehicle(ped, vehicle)
end

-- Checks if the ped is dead
Ped.IsDead = function(ped) 
    if ped == nil or ped == 0 then print('error: IsDead: ped is empty.') return false end
    return IsPedDeadOrDying(ped, 1)
end

Ped.models = { 'a_f_m_beach_01', 'a_f_m_bevhills_01', 'a_f_m_bevhills_02', 'a_f_m_bodybuild_01', 'a_f_m_business_02', 'a_f_m_downtown_01', 'a_f_m_eastsa_01', 'a_f_m_eastsa_02', 'a_f_m_fatbla_01', 'a_f_m_fatwhite_01', 'a_f_m_ktown_01', 'a_f_m_ktown_02', 'a_f_m_prolhost_01', 'a_f_m_salton_01', 'a_f_m_skidrow_01', 'a_f_m_soucent_01', 'a_f_m_soucent_02', 'a_f_m_soucentmc_01', 'a_f_m_tourist_01', 'a_f_m_tramp_01', 'a_f_m_trampbeac_01', 'a_f_o_genstreet_01', 'a_f_o_indian_01', 'a_f_o_ktown_01', 'a_f_o_salton_01', 'a_f_o_soucent_01', 'a_f_o_soucent_02', 'a_f_y_beach_01', 'a_f_y_bevhills_01', 'a_f_y_bevhills_02', 'a_f_y_bevhills_03', 'a_f_y_bevhills_04', 'a_f_y_business_01', 'a_f_y_business_02', 'a_f_y_business_03', 'a_f_y_business_04', 'a_f_y_eastsa_01', 'a_f_y_eastsa_02', 'a_f_y_eastsa_03', 'a_f_y_epsilon_01', 'a_f_y_fitness_01', 'a_f_y_fitness_02', 'a_f_y_genhot_01', 'a_f_y_golfer_01', 'a_f_y_hiker_01', 'a_f_y_hippie_01', 'a_f_y_hipster_02', 'a_f_y_hipster_03', 'a_f_y_hipster_04', 'a_f_y_indian_01', 'a_f_y_juggalo_01', 'a_f_y_runner_01', 'a_f_y_rurmeth_01', 'a_f_y_scdressy_01', 'a_f_y_skater_01', 'a_f_y_soucent_01', 'a_f_y_soucent_02', 'a_f_y_soucent_03', 'a_f_y_tennis_01', 'a_f_y_tourist_01', 'a_f_y_tourist_02', 'a_f_y_vinewood_01', 'a_f_y_vinewood_02', 'a_f_y_vinewood_03', 'a_f_y_vinewood_04', 'a_f_y_yoga_01', 'a_m_m_afriamer_01', 'a_m_m_beach_01', 'a_m_m_beach_02', 'a_m_m_bevhills_01', 'a_m_m_bevhills_02', 'a_m_m_business_01', 'a_m_m_eastsa_01', 'a_m_m_eastsa_02', 'a_m_m_farmer_01', 'a_m_m_fatlatin_01', 'a_m_m_genfat_01', 'a_m_m_genfat_02', 'a_m_m_golfer_01', 'a_m_m_hasjew_01', 'a_m_m_hillbilly_01', 'a_m_m_hillbilly_02', 'a_m_m_indian_01', 'a_m_m_ktown_01', 'a_m_m_malibu_01', 'a_m_m_mexcntry_01', 'a_m_m_mexlabor_01', 'a_m_m_og_boss_01', 'a_m_m_paparazzi_01', 'a_m_m_polynesian_01', 'a_m_m_prolhost_01', 'a_m_m_rurmeth_01', 'a_m_m_salton_01', 'a_m_m_salton_02', 'a_m_m_salton_03', 'a_m_m_salton_04', 'a_m_m_skater_01', 'a_m_m_skidrow_01', 'a_m_m_socenlat_01', 'a_m_m_soucent_01', 'a_m_m_soucent_02', 'a_m_m_soucent_03', 'a_m_m_soucent_04', 'a_m_m_stlat_02', 'a_m_m_tennis_01', 'a_m_m_tourist_01', 'a_m_m_tramp_01', 'a_m_m_trampbeac_01', 'a_m_m_tranvest_01', 'a_m_m_tranvest_02', 'a_m_o_acult_02', 'a_m_o_beach_01', 'a_m_o_genstreet_01', 'a_m_o_ktown_01', 'a_m_o_salton_01', 'a_m_o_soucent_01', 'a_m_o_soucent_02', 'a_m_o_soucent_03', 'a_m_o_tramp_01', 'a_m_y_acult_01', 'a_m_y_acult_02', 'a_m_y_beach_01', 'a_m_y_beach_02', 'a_m_y_beach_03', 'a_m_y_beachvesp_01', 'a_m_y_beachvesp_02', 'a_m_y_bevhills_01', 'a_m_y_bevhills_02', 'a_m_y_breakdance_01', 'a_m_y_busicas_01', 'a_m_y_business_01', 'a_m_y_business_03', 'a_m_y_cyclist_01', 'a_m_y_dhill_01', 'a_m_y_downtown_01', 'a_m_y_eastsa_01', 'a_m_y_eastsa_02', 'a_m_y_epsilon_01', 'a_m_y_epsilon_02', 'a_m_y_gay_01', 'a_m_y_gay_02', 'a_m_y_genstreet_01', 'a_m_y_genstreet_02', 'a_m_y_golfer_01', 'a_m_y_hasjew_01', 'a_m_y_hiker_01', 'a_m_y_hippy_01', 'a_m_y_hipster_01', 'a_m_y_hipster_02', 'a_m_y_hipster_03', 'a_m_y_indian_01', 'a_m_y_jetski_01', 'a_m_y_juggalo_01', 'a_m_y_ktown_01', 'a_m_y_ktown_02', 'a_m_y_latino_01', 'a_m_y_methhead_01', 'a_m_y_mexthug_01', 'a_m_y_motox_01', 'a_m_y_motox_02', 'a_m_y_musclbeac_01', 'a_m_y_musclbeac_02', 'a_m_y_polynesian_01', 'a_m_y_roadcyc_01', 'a_m_y_runner_01', 'a_m_y_runner_02', 'a_m_y_salton_01', 'a_m_y_skater_01', 'a_m_y_skater_02', 'a_m_y_soucent_01', 'a_m_y_soucent_02', 'a_m_y_soucent_03', 'a_m_y_soucent_04', 'a_m_y_stbla_01', 'a_m_y_stbla_02', 'a_m_y_stlat_01', 'a_m_y_stwhi_01', 'a_m_y_stwhi_02', 'a_m_y_sunbathe_01', 'a_m_y_surfer_01', 'a_m_y_vindouche_01', 'a_m_y_vinewood_01', 'a_m_y_vinewood_02', 'a_m_y_vinewood_03', 'a_m_y_vinewood_04', 'a_m_y_yoga_01', 'cs_amandatownley', 'cs_andreas', 'cs_ashley', 'cs_bankman', 'cs_barry', 'cs_beverly', 'cs_brad', 'cs_carbuyer', 'cs_casey', 'cs_chengsr', 'cs_chrisformage', 'cs_clay', 'cs_dale', 'cs_davenorton', 'cs_debra', 'cs_denise', 'cs_dom', 'cs_dreyfuss', 'cs_drfriedlander', 'cs_fabien', 'cs_fbisuit_01', 'cs_floyd', 'cs_guadalope', 'cs_gurk', 'cs_hunter', 'cs_janet', 'cs_jewelass', 'cs_jimmyboston', 'cs_jimmydisanto', 'cs_joeminuteman', 'cs_johnnyklebitz', 'cs_josef', 'cs_josh', 'cs_lamardavis', 'cs_lazlow', 'cs_lestercrest', 'cs_lifeinvad_01', 'cs_magenta', 'cs_manuel', 'cs_marnie', 'cs_martinmadrazo', 'cs_maryann', 'cs_michelle', 'cs_milton', 'cs_molly', 'cs_movpremf_01', 'cs_movpremmale', 'cs_mrk', 'cs_mrs_thornhill', 'cs_mrsphillips', 'cs_natalia', 'cs_nervousron', 'cs_nigel', 'cs_old_man1a', 'cs_old_man2', 'cs_omega', 'cs_orleans', 'cs_paper', 'cs_patricia', 'cs_priest', 'cs_prolsec_02', 'cs_russiandrunk', 'cs_siemonyetarian', 'cs_solomon', 'cs_stevehains', 'cs_stretch', 'cs_tanisha', 'cs_taocheng', 'cs_taostranslator', 'cs_tenniscoach', 'cs_terry', 'cs_tom', 'cs_tomepsilon', 'cs_tracydisanto', 'cs_wade', 'cs_zimbor', 'csb_abigail', 'csb_anita', 'csb_anton', 'csb_ballasog', 'csb_bride', 'csb_burgerdrug', 'csb_car3guy1', 'csb_car3guy2', 'csb_chef', 'csb_chin_goon', 'csb_cletus', 'csb_customer', 'csb_denise_friend', 'csb_fos_rep', 'csb_g', 'csb_groom', 'csb_grove_str_dlr', 'csb_hugh', 'csb_imran', 'csb_janitor', 'csb_maude', 'csb_mweather', 'csb_ortega', 'csb_oscar', 'csb_porndudes', 'csb_prologuedriver', 'csb_prolsec', 'csb_ramp_gang', 'csb_ramp_hic', 'csb_ramp_hipster', 'csb_ramp_marine', 'csb_ramp_mex', 'csb_reporter', 'csb_roccopelosi', 'csb_screen_writer', 'csb_tonya', 'csb_trafficwarden', 'csb_vagspeak', 'g_f_y_ballas_01', 'g_f_y_families_01', 'g_f_y_lost_01', 'g_f_y_vagos_01', 'g_m_importexport_01', 'g_m_m_armboss_01', 'g_m_m_armgoon_01', 'g_m_m_armlieut_01', 'g_m_m_chemwork_01', 'g_m_m_chiboss_01', 'g_m_m_chicold_01', 'g_m_m_chigoon_01', 'g_m_m_chigoon_02', 'g_m_m_korboss_01', 'g_m_m_mexboss_01', 'g_m_m_mexboss_02', 'g_m_y_armgoon_02', 'g_m_y_azteca_01', 'g_m_y_ballaeast_01', 'g_m_y_ballaorig_01', 'g_m_y_ballasout_01', 'g_m_y_famca_01', 'g_m_y_famdnf_01', 'g_m_y_famfor_01', 'g_m_y_korean_01', 'g_m_y_korean_02', 'g_m_y_korlieut_01', 'g_m_y_lost_01', 'g_m_y_lost_02', 'g_m_y_lost_03', 'g_m_y_mexgang_01', 'g_m_y_mexgoon_01', 'g_m_y_mexgoon_02', 'g_m_y_mexgoon_03', 'g_m_y_pologoon_01', 'g_m_y_pologoon_02', 'g_m_y_salvaboss_01', 'g_m_y_salvagoon_01', 'g_m_y_salvagoon_02', 'g_m_y_salvagoon_03', 'g_m_y_strpunk_01', 'g_m_y_strpunk_02', 'hc_driver', 'hc_gunman', 'hc_hacker', 'ig_abigail', 'ig_amandatownley', 'ig_andreas', 'ig_ashley', 'ig_ballasog', 'ig_bankman', 'ig_barry', 'ig_benny', 'ig_bestmen', 'ig_beverly', 'ig_brad', 'ig_bride', 'ig_car3guy1', 'ig_car3guy2', 'ig_casey', 'ig_chef', 'ig_chengsr', 'ig_chrisformage', 'ig_clay', 'ig_claypain', 'ig_cletus', 'ig_dale', 'ig_davenorton', 'ig_denise', 'ig_devin', 'ig_dom', 'ig_dreyfuss', 'ig_drfriedlander', 'ig_fabien', 'ig_floyd', 'ig_g', 'ig_groom', 'ig_hao', 'ig_hunter', 'ig_janet', 'ig_jay_norris', 'ig_jewelass', 'ig_jimmyboston', 'ig_jimmydisanto', 'ig_josef', 'ig_josh', 'ig_kerrymcintosh', 'ig_lamardavis', 'ig_lazlow', 'ig_lestercrest', 'ig_lifeinvad_01', 'ig_lifeinvad_02', 'ig_magenta', 'ig_malc', 'ig_manuel', 'ig_marnie', 'ig_maryann', 'ig_maude', 'ig_michelle', 'ig_milton', 'ig_molly', 'ig_mrk', 'ig_mrs_thornhill', 'ig_mrsphillips', 'ig_natalia', 'ig_nervousron', 'ig_nigel', 'ig_old_man1a', 'ig_old_man2', 'ig_omega', 'ig_oneil', 'ig_orleans', 'ig_ortega', 'ig_paper', 'ig_patricia', 'ig_priest', 'ig_prolsec_02', 'ig_ramp_gang', 'ig_ramp_hic', 'ig_ramp_hipster', 'ig_ramp_mex', 'ig_roccopelosi', 'ig_russiandrunk', 'ig_screen_writer', 'ig_siemonyetarian', 'ig_solomon', 'ig_stevehains', 'ig_stretch', 'ig_talina', 'ig_tanisha', 'ig_taocheng', 'ig_taostranslator', 'ig_tenniscoach', 'ig_terry', 'ig_tomepsilon', 'ig_tonya', 'ig_tracydisanto', 'ig_trafficwarden', 'ig_tylerdix', 'ig_vagspeak', 'ig_wade', 'ig_zimbor', 'mp_f_boatstaff_01', 'mp_f_cardesign_01', 'mp_f_chbar_01', 'mp_f_cocaine_01', 'mp_f_counterfeit_01', 'mp_f_deadhooker', 'mp_f_execpa_01', 'mp_f_forgery_01', 'mp_f_freemode_01', 'mp_f_helistaff_01', 'mp_f_meth_01', 'mp_f_weed_01', 'mp_g_m_pros_01', 'mp_headtargets', 'mp_m_boatstaff_01', 'mp_m_cocaine_01', 'mp_m_exarmy_01', 'mp_m_execpa_01', 'mp_m_famdd_01', 'mp_m_fibsec_01', 'mp_m_freemode_01', 'mp_m_g_vagfun_01', 'mp_m_meth_01', 'mp_m_securoguard_01', 'mp_m_shopkeep_01', 'mp_m_waremech_01', 'mp_m_weed_01', 'mp_s_m_armoured_01', 's_f_m_fembarber', 's_f_m_shop_high', 's_f_m_sweatshop_01', 's_f_y_airhostess_01', 's_f_y_bartender_01', 's_f_y_baywatch_01', 's_f_y_factory_01', 's_f_y_hooker_01', 's_f_y_hooker_02', 's_f_y_hooker_03', 's_f_y_migrant_01', 's_f_y_movprem_01', 's_f_y_scrubs_01', 's_f_y_shop_low', 's_f_y_shop_mid', 's_f_y_sweatshop_01', 's_m_m_ammucountry', 's_m_m_armoured_01', 's_m_m_armoured_02', 's_m_m_autoshop_01', 's_m_m_autoshop_02', 's_m_m_bouncer_01', 's_m_m_chemsec_01', 's_m_m_ciasec_01', 's_m_m_cntrybar_01', 's_m_m_dockwork_01', 's_m_m_doctor_01', 's_m_m_gaffer_01', 's_m_m_gardener_01', 's_m_m_gentransport', 's_m_m_hairdress_01', 's_m_m_highsec_01', 's_m_m_highsec_02', 's_m_m_janitor', 's_m_m_lathandy_01', 's_m_m_lifeinvad_01', 's_m_m_linecook', 's_m_m_lsmetro_01', 's_m_m_mariachi_01', 's_m_m_migrant_01', 's_m_m_movalien_01', 's_m_m_movprem_01', 's_m_m_movspace_01', 's_m_m_paramedic_01', 's_m_m_pilot_01', 's_m_m_pilot_02', 's_m_m_postal_01', 's_m_m_postal_02', 's_m_m_scientist_01', 's_m_m_strperf_01', 's_m_m_strpreach_01', 's_m_m_strvend_01', 's_m_m_trucker_01', 's_m_m_ups_01', 's_m_m_ups_02', 's_m_o_busker_01', 's_m_y_airworker', 's_m_y_ammucity_01', 's_m_y_barman_01', 's_m_y_baywatch_01', 's_m_y_chef_01', 's_m_y_clown_01', 's_m_y_construct_01', 's_m_y_construct_02', 's_m_y_dealer_01', 's_m_y_devinsec_01', 's_m_y_dockwork_01', 's_m_y_doorman_01', 's_m_y_dwservice_01', 's_m_y_dwservice_02', 's_m_y_factory_01', 's_m_y_fireman_01', 's_m_y_garbage', 's_m_y_grip_01', 's_m_y_mime', 's_m_y_pestcont_01', 's_m_y_pilot_01', 's_m_y_shop_mask', 's_m_y_strvend_01', 's_m_y_uscg_01', 's_m_y_valet_01', 's_m_y_waiter_01', 's_m_y_winclean_01', 's_m_y_xmech_01', 's_m_y_xmech_02', 's_m_y_xmech_02_mp', 'u_f_m_corpse_01', 'u_f_m_miranda', 'u_f_m_promourn_01', 'u_f_o_moviestar', 'u_f_o_prolhost_01', 'u_f_y_bikerchic', 'u_f_y_comjane', 'u_f_y_corpse_01', 'u_f_y_hotposh_01', 'u_f_y_jewelass_01', 'u_f_y_mistress', 'u_f_y_poppymich', 'u_f_y_princess', 'u_f_y_spyactress', 'u_m_m_aldinapoli', 'u_m_m_bankman', 'u_m_m_bikehire_01', 'u_m_m_fibarchitect', 'u_m_m_filmdirector', 'u_m_m_glenstank_01', 'u_m_m_griff_01', 'u_m_m_jesus_01', 'u_m_m_jewelsec_01', 'u_m_m_jewelthief', 'u_m_m_markfost', 'u_m_m_partytarget', 'u_m_m_prolsec_01', 'u_m_m_promourn_01', 'u_m_m_rivalpap', 'u_m_m_spyactor', 'u_m_m_willyfist', 'u_m_o_finguru_01', 'u_m_o_taphillbilly', 'u_m_o_tramp_01', 'u_m_y_abner', 'u_m_y_antonb', 'u_m_y_babyd', 'u_m_y_baygor', 'u_m_y_burgerdrug_01', 'u_m_y_chip', 'u_m_y_cyclist_01', 'u_m_y_fibmugger_01', 'u_m_y_guido_01', 'u_m_y_gunvend_01', 'u_m_y_hippie_01', 'u_m_y_imporage', 'u_m_y_mani', 'u_m_y_militarybum', 'u_m_y_paparazzi', 'u_m_y_party_01', 'u_m_y_pogo_01', 'u_m_y_proldriver_01', 'u_m_y_rsranger_01', 'u_m_y_staggrm_01', 'u_m_y_tattoo_01', 'u_m_y_zombie_01' }
