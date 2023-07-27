local settings = {
    ["com_modem"] = "left",
    ["com_port"] = 1415,
    ["server_id"] = 6289,
    ["monitors"] = {
        ["monitor_1554"] = {
            uuid = "123asd",
            x = 989,
            z = 275
        },
        ["monitor_1555"] = {
            uuid = "321dsa",
            x = 993,
            z = 275
        },
    },
}

--local man = peripheral.find("manipulator")
local modem = peripheral.wrap(settings.com_modem)

modem.open(settings.com_port)

-- Receives from the modem
function receiveModem(filter, timeout)
    local side, channel, replyChannel, message, distance
    local function m()
        while true do
            local levent, lside, lchannel, lreplyChannel, lmessage, ldistance = os.pullEvent("modem_message")
            if filter(lside, lchannel, lreplyChannel, lmessage, ldistance) then
                side, channel, replyChannel, message, distance = lside, lchannel, lreplyChannel, lmessage, ldistance
                break 
            end
        end
    end
    local function w()
        os.sleep(timeout)
    end
    if timeout == nil then
        m()
    else
        parallel.waitForAny(m, w)
    end
    return side, channel, replyChannel, message, distance
end

-- Sends on the modem
function sendModem(port, to, mode, data)
    modem.transmit(port, port, {
        from = os.getComputerID(),
        to = to,
        mode = mode,
        data = data
    })
end

function copy(tbl)
    local out = {}
    for k,v in pairs(tbl) do
        out[k] = v 
    end
    return out
end

function getItems()
    sendModem(settings.com_port, settings.server_id, "getItems", {})
    local side, channel, replyChannel, message, distance = receiveModem(function(side, channel, replyChannel, message, distance)
        return (type(message) == "table") and (message.to == os.getComputerID()) and (message.mode == "items")
    end, 2)
    if side ~= nil then
        for k,v in ipairs(message.data) do
            message.data[k].getPrice = function()
                local price = v.price
                if not v.dp_forcePrice then
                    local ic = v.dp_normalStock / v.count
                    local np = v.price * ic
                    np = math.floor(np*100)/100
                    if np == 0 then
                        np = v.price
                    end
                    price = np
                end
                if v.discount == 0 then
                    return price
                else
                    local nnp = math.floor((price-(price*(v.discount/100)))*100)/100
                    if nnp == 0 then
                        nnp = v.price
                    end
                    return nnp
                end
            end
        end
        return message.data
    else
        print("Server does not responding...")
    end
end

function getItemDataById(dat,uuid)
    --[[sendModem(settings.com_port, settings.server_id, "getItemById", {
        uuid = uuid
    })
    local side, channel, replyChannel, message, distance = receiveModem(function(side, channel, replyChannel, message, distance)
        return (type(message) == "table") and (message.to == os.getComputerID()) and ((message.mode == "itemData") or (message.mode == "error")) 
    end, 2)
    if side ~= nil then
        if message.mode == "error" then
            print("Server had an error: "..message.data.message)
        else
            return message.data
        end
    else
        print("Server does not responding...")
    end]]
    for k,v in ipairs(dat) do
        if v.uuid == uuid then
            return v
        end
    end
end

local function writeToCenter(mon, text, y)
    local w,h = mon.getSize()
    mon.setCursorPos(math.floor(w/2-#text/2)+1,y)
    mon.write(text)
end

local itemData = {}
function updateItemData()
    local litems = getItems()
    while litems == nil do
        litems = getItems()
    end
    for k,v in pairs(settings.monitors) do
        local litemData = getItemDataById(litems,v.uuid)
        while litemData == nil do
            litemData = getItemDataById(litems,v.uuid)
        end
        if litemData ~= nil then
            itemData[k] = litemData
            itemData[k].getPrice = function()
                local price = litemData.price
                if not litemData.dp_forcePrice then
                    local ic = litemData.dp_normalStock / litemData.count
                    local np = litemData.price * ic
                    np = math.floor(np*100)/100
                    if np == 0 then
                        np = litemData.price
                    end
                    price = np
                end
                if litemData.discount == 0 then
                    return price
                else
                    local nnp = math.floor((price-(price*(litemData.discount/100)))*100)/100
                    if nnp == 0 then
                        nnp = litemData.price
                    end
                    return nnp
                end
            end
        else
            itemData[k] = {
                ["uuid"] = "-1",
                ["name"] = "Error occured",
                ["price"] = 0,
                ["dp_normalStock"] = 0,
                ["discount"] = 0,
                ["id"] = "",
                ["dp_forcePrice"] = true,
                ["count"] = 0,
                ["getPrice"] = function()
                    return 0
                end
            }
        end
        local mon = peripheral.wrap(k)
        mon.setTextScale(0.5)
        mon.setBackgroundColor(colors.black)
        mon.setTextColor(colors.white)
        mon.clear()
        local w,h = mon.getSize()
        if w==15 and h==10 then
            --displayPic(mon, 1, 1, itemData[k].name)
            if itemData[k].discount == 0 then
                writeToCenter(mon, itemData[k].name, 8)
                mon.setTextColor(colors.green)
                writeToCenter(mon, "Price: "..itemData[k].getPrice(), 9)
                mon.setTextColor(colors.cyan)
                writeToCenter(mon, "Stock: "..itemData[k].count, 10)
            else
                writeToCenter(mon, itemData[k].name, 7)
                mon.setTextColor(colors.green)
                writeToCenter(mon, "Price: "..itemData[k].getPrice(), 8)
                mon.setTextColor(colors.yellow)
                writeToCenter(mon, itemData[k].discount.."% off", 9)
                mon.setTextColor(colors.cyan)
                writeToCenter(mon, "Stock: "..itemData[k].count, 10)
            end
        else
            writeToCenter(mon, "Invalid monitor size", h/2)
        end
    end
    
end

function addItemToCart(uuid,user)
    sendModem(settings.com_port, settings.server_id, "addItemToCart",{
        item = uuid,
        user = user,
    })
    local side, channel, replyChannel, message, distance = receiveModem(function(side, channel, replyChannel, message, distance)
        return (type(message) == "table") and (message.to == os.getComputerID()) and ((message.mode == "success") or (message.mode == "error"))
    end, 2)
    if side ~= nil then
        if message.mode == "success" then
            print(message.data.message)
        else
            print("Server had an error: "..message.data.message)
        end
    else
        print("Timed out")
    end
end

local function getDist(x1,z1,x2,z2)
    local dx = math.abs(x1 - x2)
    local dy = math.abs(z1 - z2)
    return dx + dy
end

function getUserAtMon(side)
    players = {}
    local handle = http.get("https://dynmap.sc3.io/up/world/SwitchCraft/")
    local sensed = textutils.unserialiseJSON(handle.readAll())
    handle.close()
    for k, v in ipairs(sensed.players) do
        players[k] = getDist(settings.monitors[side].x,settings.monitors[side].z,v.x,v.z)*100
    end
    local lowst = nil
    local lowstn = math.huge
    for k,v in pairs(players) do
        if v < lowstn then
            lowst = sensed.players[k]
            lowstn = v
        end
    end
    return lowst
end

local function clickert()
    while true do
        local event, side, x, y = os.pullEvent("monitor_touch")
        if settings.monitors[side] ~= nil then
            addItemToCart(settings.monitors[side].uuid, getUserAtMon(side).name)
        end
    end
end

local function updater()
    while true do
        updateItemData()
        os.sleep(30)
    end 
end

local function itemDataChangeListener()
    while true do
        local side, channel, replyChannel, message, distance = receiveModem(function(side, channel, replyChannel, message, distance)
            return (type(message) == "table") and (message.to == "all") and (message.mode == "itemDataUpdate")
        end)
        updateItemData()
        os.sleep(0)
    end
end

parallel.waitForAny(function()
    local ok,err = pcall(clickert)
    if not ok then
        print(err)
    end
end,function()
    local ok,err = pcall(updater)
    if not ok then
        print(err)
    end
end,function()
    local ok,err = pcall(itemDataChangeListener)
    if not ok then
        print(err)
    end
end)