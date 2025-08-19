lib.locale()
local Radar = lib.load('config')
local showRadar = GetResourceKvpInt('lsl_showRadar') == 1 or Radar.defaultShowingRadar
local showLaser = GetResourceKvpInt('lsl_showLaser') == 1
local lsl_autoLockSpeed = GetResourceKvpInt('lsl_autoLockSpeed') > 0 and GetResourceKvpInt('lsl_autoLockSpeed') or Radar.autoLockSpeed
Radar.autoLockSpeed = lsl_autoLockSpeed
local speedMultiplier = Radar.speedType == "MPH" and 2.23694 or 3.6
local showingRadar = false
local radarLocked = false
local lastLocaleSent = nil
local lastVisibility = nil
local localeData = json.decode(LoadResourceFile(cache.resource, ('locales/%s.json'):format(Radar.locale or 'en')))
local wantedPlates = {}

local function dbug(msg, table)
    if not Radar.debug then return end
    if not table then
        print("[DEBUG] " .. msg)
    else
        print("[DEBUG] " .. json.encode(msg, {indent = true}))
    end
end

---@param message string
---@param type string
local function notify(message, type, duration)
    if not duration then duration = 5000 end
    lib.notify({ description = message, type = type, duration = duration })
end

local function saveDetection(plate, speed)
    local history = {}
    table.insert(history, { plate = plate, speed = speed })
    dbug(history, true)
    SetResourceKvp('lsl_radarHistory', json.encode(history))
end

RegisterNuiCallback('hideFrame', function(data, cb)
    SetNuiFocus(false, false)
    cb(true)
end)

RegisterNuiCallback('saveRadarPosition', function(data, cb)
    local position = { x = data.x or 1580, y = data.y or 860 }
    SetResourceKvp('lsl_radarPosition', json.encode(position))
    SendNUIMessage({ action = 'setRadarPosition', data = position })
    cb(true)
end)

RegisterCommand(Radar.changeRadarPositionCommand, function()
    if showingRadar then
        notify('ESC zum bestätigen!', 'info')
        SetNuiFocus(true, true)
    end
end, false)

RegisterCommand(Radar.lockRadarCommand, function()
    if showingRadar then
        radarLocked = not radarLocked
        SendNUIMessage({ action = 'updateRadarLocked', data = radarLocked })
        PlaySoundFrontend(-1, '5_SEC_WARNING', "HUD_MINI_GAME_SOUNDSET", true)
        notify(radarLocked and locale('locked') or locale('unlocked'), 'info')
    end
end, false)
RegisterKeyMapping(Radar.lockRadarCommand, locale('lockRadarKeybind'), 'KEYBOARD', Radar.lockRadarKeybind)

exports("AddWantedPlate", function(plate)
    if not plate or plate == "" then return false end
    plate = string.upper(plate)
    wantedPlates[plate] = true
    notify("Kennzeichen " .. plate .. " zur Fahndungsliste hinzugefügt ✅", "success")
    return true
end)

exports("RemoveWantedPlate", function(plate)
    if not plate or plate == "" then return false end
    plate = string.upper(plate)
    if wantedPlates[plate] then
        wantedPlates[plate] = nil
        notify("Kennzeichen " .. plate .. " von der Fahndungsliste entfernt ❌", "error")
        return true
    end
    return false
end)

exports("IsPlateWanted", function(plate)
    if not plate or plate == "" then return false end
    plate = string.upper(plate)
    return wantedPlates[plate] ~= nil
end)

-- Kennzeichen auf Fahndungsliste setzen
-- exports["mt_policeradar"]:AddWantedPlate(plate)

-- Kennzeichen wieder löschen
-- exports["mt_policeradar"]:RemoveWantedPlate(plate)

-- Abfrage ob gesuchtes Fahrzeug
-- if exports["mt_policeradar"]:IsPlateWanted(plate) then
--     print("🚨 plate ist auf der Liste!")
-- end

RegisterCommand(Radar.showRadarCommand, function()
    local jobName = QBX.PlayerData.job.name
    local jobGrade = QBX.PlayerData.job.grade.level or 0
    local allowedRank = Radar.radarJobs[jobName]

    if not allowedRank then
        showRadar = false
        notify("Du bist nicht autorisiert, das Radar zu nutzen!", 'error')
        return
    end

    if jobGrade < allowedRank then
        notify("Dein Rang ist zu niedrig für das Radar!", 'error')
        return
    end

    if not IsPedInAnyVehicle(cache.ped, false) then
        notify("Du sitzt in keinem Fahrzeug!", 'error')
        return
    end

    if GetVehicleClass(GetVehiclePedIsIn(cache.ped, false)) ~= 18 then
        notify("Du sitzt nicht im Polizeifahrzeug!", 'error')
        return
    end

    local history = json.decode(GetResourceKvpString('lsl_radarHistory')) or {}
    local lastDetection = history[#history]

    -- aktuelle Fahndungsliste formatieren
    local plateList = "LEER"
    if next(wantedPlates) then
        local t = {}
        for plate in pairs(wantedPlates) do
            table.insert(t, plate)
        end
        plateList = table.concat(t, ", ")
    end

    local input = lib.inputDialog('ANPR Einstellungen', {
        { type = 'checkbox', label = '❯ Radar anzeigen', checked = showRadar },
        { type = 'checkbox', label = '❯ Auto-Lock aktivieren', checked = lsl_autoLockSpeed > 0 },
        { type = 'number', icon = 'fas fa-car-burst', label = 'Auto-Lock Geschwindigkeit (KM/H)', step = 5, max = 260, placeholder = '130', default = lsl_autoLockSpeed or 0 },
        { type = 'checkbox', label = '❯ Laser anzeigen', checked = showLaser },
        { type = 'checkbox', label = '❯ Letzte Erfassung ausdrucken', checked = false },
        { type = 'input', icon = 'fas fa-clipboard-list', label = 'Letzte Erfassung', disabled = true, default = lastDetection and (lastDetection.plate .. '      |      ' .. lastDetection.speed .. ' KM/H') or 'LEER' },
        { type = 'input', icon = 'fas fa-car', label = 'Kennzeichen verwalten', placeholder = 'z.B. ABC123' },
        { type = 'select', icon = 'fas fa-list-ul', label = 'Fahndungsliste Aktion', options = {
            { value = 'none', label = '⚠️ Keine Aktion' },
            { value = 'add', label = '✅ Hinzufügen' },
            { value = 'remove', label = '❌ Entfernen' }
        }, default = 'none' },
        { type = 'input', icon = 'fas fa-list', label = 'Fahndungsliste', disabled = true, default = plateList },
    })

    if not input then return end

    showRadar = input[1]
    local autoLock = input[2]
    lsl_autoLockSpeed = tonumber(input[3]) or 0
    showLaser = input[4]
    local printLastDetection = input[5]
    local plate = input[7] and string.upper(input[7]) or nil
    local action = input[8]

    -- Radar Settings speichern
    SetResourceKvpInt('lsl_showRadar', showRadar and 1 or 0)
    SetResourceKvpInt('lsl_autoLockSpeed', lsl_autoLockSpeed)
    SetResourceKvpInt('lsl_showLaser', showLaser and 1 or 0)
    Radar.autoLockSpeed = autoLock and lsl_autoLockSpeed or 0

    -- Notifications
    if autoLock then
        if lsl_autoLockSpeed > 0 then
            notify('Einstellungen gespeichert. Auto-Lock bei ' .. lsl_autoLockSpeed .. ' KM/H gesetzt! Radar ist ' .. (showRadar and 'aktiviert' or 'deaktiviert') .. '.', 'info')
        else
            notify('Auto-Lock deaktiviert! Radar ist ' .. (showRadar and 'aktiviert' or 'deaktiviert') .. '.', 'info')
        end
    else
        notify('Einstellungen gespeichert. Radar ist ' .. (showRadar and 'aktiviert' or 'deaktiviert') .. '.', 'info')
        lsl_autoLockSpeed = 0
        SetResourceKvpInt('lsl_autoLockSpeed', lsl_autoLockSpeed)
    end
    PlaySoundFrontend(-1, 'Beep_Red', "DLC_HEIST_HACKING_SNAKE_SOUNDS", true)

    -- Fahndungsliste Aktion
    if plate and action == 'add' then
        if not exports["mt_policeradar"]:IsPlateWanted(plate) then
            wantedPlates[plate] = true
            notify(plate .. " zur Fahndungsliste hinzugefügt ✅", "success")
        else
            notify(plate .. " war bereits auf der Liste ⚠️", "warning")
        end
    elseif plate and action == 'remove' then
        if wantedPlates[plate] then
            wantedPlates[plate] = nil
            notify(plate .. " von der Fahndungsliste entfernt ❌", "error")
        else
            notify(plate .. " war nicht auf der Liste ⚠️", "warning")
        end
    end

    -- Ticket-Druck
    if printLastDetection then
        Wait(1000)
        ExecuteCommand('me druckt Ticket aus...')
        local success = lib.progressBar({
            duration     = 3000,
            label        = 'Drucke Ticket aus...',
            canCancel    = true,
            useWhileDead = false,
            disableControl = {
                move     = true,
                car      = true,
                mouse    = false,
                combat   = true,
            },
        })
        if success then
            TriggerServerEvent('mt_policeradar:server:giveDetectionTicket', lastDetection.plate, lastDetection.speed)
        end
    end
end, false)

RegisterKeyMapping(Radar.showRadarCommand, locale('toggleRadarKeybind'), 'KEYBOARD', Radar.showRadarKeybind)

local function vehicleLoop()
    CreateThread(function()
        local jobName = QBX.PlayerData.job.name
        local allowedRank = Radar.radarJobs[jobName]
        if not allowedRank then return end

        local position = json.decode(GetResourceKvpString('lsl_radarPosition')) or { x = 1580, y = 860 }
        SendNUIMessage({ action = 'setRadarPosition', data = position })
        dbug("Position in X: " .. position.x .. " pixel | Position in Y: " .. position.y .. " pixel", false)

        -- Haupt-Schleife, die läuft, solange der Spieler im Fahrzeug ist
        while cache.vehicle do
            if showRadar then
                -- Erkennungs-Thread
                local recognitionThread = CreateThread(function()
                    while showRadar and cache.vehicle do
                        if showingRadar and not radarLocked then
                            local veh = cache.vehicle
                            local coordA = GetOffsetFromEntityInWorldCoords(veh, 0.0, 1.0, 0.4)
                            local coordB = GetOffsetFromEntityInWorldCoords(veh, 0.0, 105.0, 0.0)
                            local frontcar = StartShapeTestCapsule(coordA, coordB, 6.0, 10, veh, 7)
                            local _, _, _, _, e = GetShapeTestResult(frontcar)

                            if IsEntityAVehicle(e) then
                                local plate = GetVehicleNumberPlateText(e)
                                local frontSpeed = math.ceil(GetEntitySpeed(e) * speedMultiplier)

                                if not plate or plate == "" then return end

                                if wantedPlates[plate] then
                                    PlaySoundFrontend(-1, 'CHECKPOINT_MISSED', "HUD_MINI_GAME_SOUNDSET", true)

                                    notify("Gesuchtes Fahrzeug erkannt: " .. plate .. "!", "error")

                                    if Radar then
                                        radarLocked = true
                                        SendNUIMessage({ action = 'updateRadarLocked', data = radarLocked })
                                    end
                                end

                                SendNUIMessage({ action = 'updateFrontCar', data = { speed = frontSpeed, plate = plate } })
                                if showLaser then
                                    local targetPos = GetOffsetFromEntityInWorldCoords(e, 0.0, -2.0, 0)
                                    DrawLine(coordA.x, coordA.y, coordA.z, targetPos.x, targetPos.y, targetPos.z, 255, 0, 0, 255)
                                end
                                if Radar.autoLockSpeed > 0 and frontSpeed >= Radar.autoLockSpeed then
                                    radarLocked = true
                                    SendNUIMessage({ action = 'updateRadarLocked', data = radarLocked })
                                    PlaySoundFrontend(-1, 'OOB_Start', "GTAO_FM_Events_Soundset", true)
                                    notify('Vorderes Kennzeichen gesperrt! ' ..plate.. " wurde mit " ..frontSpeed.. " KMH gemessen!", 'info', 15000)
                                    saveDetection(plate, frontSpeed)
                                end
                            end

                            local bcoordB = GetOffsetFromEntityInWorldCoords(veh, 0.0, -105.0, 0.0)
                            local rearcar = StartShapeTestCapsule(coordA, bcoordB, 3.0, 10, veh, 7)
                            local _, _, _, _, j = GetShapeTestResult(rearcar)

                            if IsEntityAVehicle(j) then
                                local plate = GetVehicleNumberPlateText(j)
                                local rearSpeed = math.ceil(GetEntitySpeed(j) * speedMultiplier)

                                if wantedPlates[plate] then
                                    PlaySoundFrontend(-1, 'CHECKPOINT_MISSED', "HUD_MINI_GAME_SOUNDSET", true)

                                    notify("Gesuchtes Fahrzeug erkannt: " .. plate .. "!", "error")

                                    if Radar then
                                        radarLocked = true
                                        SendNUIMessage({ action = 'updateRadarLocked', data = radarLocked })
                                    end
                                end

                                SendNUIMessage({ action = 'updateRearCar', data = { speed = rearSpeed, plate = plate } })
                                if Radar.autoLockSpeed > 0 and rearSpeed >= Radar.autoLockSpeed then
                                    radarLocked = true
                                    SendNUIMessage({ action = 'updateRadarLocked', data = radarLocked })
                                    PlaySoundFrontend(-1, 'OOB_Start', "GTAO_FM_Events_Soundset", true)
                                    notify('Hinteres Kennzeichen gesperrt! ' ..plate.. " wurde mit " ..rearSpeed.. " KMH gemessen!", 'info', 15000)
                                    saveDetection(plate, rearSpeed)
                                end
                            end
                        end
                        Wait(Radar.radarUpdateInterval)
                    end
                end)

                -- Sichtbarkeits-Thread
                local visibilityThread = CreateThread(function()
                    local wait = 500
                    while showRadar and cache.vehicle do
                        if IsPauseMenuActive() then
                            wait = 1
                            if lastVisibility ~= false then
                                SendNUIMessage({ action = 'setVisibleRadar', data = false })
                                lastVisibility = false
                                showingRadar = false
                            end
                        else
                            wait = 500
                            if lastVisibility ~= true then
                                SendNUIMessage({ action = 'setVisibleRadar', data = true })
                                lastVisibility = true
                            end
                            if lastLocaleSent ~= Radar.locale then
                                SendNUIMessage({ action = 'setLocale', data = localeData })
                                lastLocaleSent = Radar.locale
                            end
                            showingRadar = true
                        end
                        Wait(wait)
                    end
                end)

                -- Warte, bis showRadar false wird oder das Fahrzeug verlassen wird
                while showRadar and cache.vehicle do
                    Wait(1000)
                end

                -- Wenn showRadar false wird, beende die Threads und setze das Radar zurück
                if showingRadar then
                    SendNUIMessage({ action = 'setVisibleRadar', data = false })
                    lastVisibility = false
                    showingRadar = false
                end
            else
                -- Wenn showRadar false ist, warte und überprüfe erneut
                Wait(1000)
            end
        end
    end)
end

AddEventHandler('onResourceStart', function(resource)
    if GetCurrentResourceName() ~= resource then return end

    exports.ox_inventory:displayMetadata({
        officer = 'Erfasst von',
        plate = 'Kennzeichen',
        speed = 'Geschwindigkeit',
    })
end)

AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    exports.ox_inventory:displayMetadata({
        officer = 'Erfasst von',
        plate = 'Kennzeichen',
        speed = 'Geschwindigkeit',
    })
end)

lib.onCache('vehicle', function(veh)
    if veh and GetVehicleClass(veh) == 18 then
        vehicleLoop()
    end
end)

Citizen.CreateThread(function()
    TriggerEvent('chat:addSuggestion', '/'..Radar.changeRadarPositionCommand, '❯ Lasst dich die Position des Radars anpassen.')
    TriggerEvent('chat:addSuggestion', '/'..Radar.showRadarCommand, '❯ Öffnet das ANPR Menü.')
    TriggerEvent('chat:addSuggestion', '/'..Radar.lockRadarCommand, '❯ Toggle Radar')

end)
