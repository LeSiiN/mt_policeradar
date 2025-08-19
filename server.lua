lib.locale()
local Radar = lib.load('config')

local function dbug(msg, table)
    if not Radar.debug then return end
    if not table then
        print("[DEBUG-SERVER] " .. msg)
    else
        print("[DEBUG-SERVER] " .. json.encode(msg, {indent = true}))
    end
end

RegisterServerEvent('lsl-policeradar:server:giveDetectionTicket', function(plate, speed)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end

    local info = {}
    info.plate = plate
    info.speed = speed.. " KM/H"
    info.officer = player.PlayerData.job.grade.name.. " " ..player.PlayerData.charinfo.lastname

    local success, response = exports.ox_inventory:AddItem(src, 'ticket', 1, info)
    if success then
        dbug("Item was given.", false)
        TriggerClientEvent('ox_lib:notify', src, {
            title = "Information",
            type = 'info',
            description = "Ticket wurde ausgedruckt.",
            duration = 5000,
            showDuration = true
        })
    else
        return print(response)
    end
end)
