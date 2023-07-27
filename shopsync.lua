local settings = {
    ["shop_location_description"] = "znepb St.",
    ["shop_location_dimension"] = "overworld",
    ["com_modem"] = "bottom",
    ["com_port"] = 1415,
    ["server_id"] = 6289,
    ["shopsync_modem"] = "top",
    ["shopsync_port"] = 9773
}

local cmodem = peripheral.wrap(settings.com_modem)
local tmodem = peripheral.wrap(settings.shopsync_modem)

cmodem.open(settings.com_port)

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
    cmodem.transmit(port, port, {
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

function getShopInfo()
    sendModem(settings.com_port, settings.server_id, "getShopInfo", {})
    local side, channel, replyChannel, message, distance = receiveModem(function(side, channel, replyChannel, message, distance)
        return (type(message) == "table") and (message.to == os.getComputerID()) and (message.mode == "shopInfo")
    end, 2)
    if side ~= nil then
        return message.data
    else
        print("Server does not responding...")
    end
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

function sendShopsync()
    local shopInfo = getShopInfo()
    while shopInfo == nil do
        shopInfo = getShopInfo()
        os.sleep(0)
    end
    local shopItems = getItems()
    while shopItems == nil do
        shopItems = getItems()
        os.sleep(0)
    end
    local itms = {}
    for k,v in ipairs(shopItems) do
        table.insert(itms, {
            prices = {
                {
                    value = v.getPrice(),
                    currency = "KST",
                    address = shopInfo.address
                }
            },
            item = {
                name = v.id,
                displayName = v.name
            },
            dynamicPricing = (not v.dp_forcePrice),
            stock = v.stock,
            madeOnDemand = false,
            requiresInteraction = true
        })
    end
    local coords = {gps.locate()}
    local data = {
        type = "ShopSync",
        info = {
            name = shopInfo.name,
            description = shopInfo.desc,
            owner = shopInfo.owner,
            computerID = os.getComputerID(),
            software = {
                name = "shipshop",
                version = "latest"
            },
            location = {
                cordinates = coords,
                description = settings.shop_location_description,
                dimension = "overworld"
            }
        },
        items = itms
    }
    tmodem.transmit(settings.shopsync_port, os.getComputerID()%65536, data)
    print("Shopsync sent!")
    lastShopsync = os.clock()
end

local lastShopsync = 0

local function mmodem()
    while true do
        local side, channel, replyChannel, message, distance = receiveModem(function(side, channel, replyChannel, message, distance)
            return (type(message) == "table") and (message.to == "all") and (message.mode == "itemDataUpdate")
        end)
        os.sleep(2)
        if os.clock() - lastShopsync > 10 then
            sendShopsync() 
        end
        os.sleep(0)
    end
end

sendShopsync()

mmodem()