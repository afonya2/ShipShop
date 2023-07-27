local settings = {
    ["com_port"] = 1415,
    ["server_id"] = 6289,
    ["cashier_id"] = 1,
    ["printer_id"] = "printer_99",
    ["self_id"] = "turtle_9491"
}

local modem = peripheral.find("modem")
local storages = {}
local perps = peripheral.getNames()
for k,v in ipairs(perps) do
    local _, t = peripheral.getType(v)
    if t == "inventory" then
        table.insert(storages, {
            id = v,
            wrap = peripheral.wrap(v)
        })
    end
end

modem.open(settings.com_port)
shell.run("label set Cashier"..settings.cashier_id)

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

function registerCashier()
    sendModem(settings.com_port, settings.server_id, "registerCashier", {
        id = settings.cashier_id
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

local function regger()
    while true do
        registerCashier()
        os.sleep(30)
    end
end

function dropItems(id, amount)
    local remaining = amount
    local function itemDrop(idd, amountt)
        if amountt > 64 then
            amountt = 64
        end
        for k,v in ipairs(storages) do
            for kk,vv in pairs(v.wrap.list()) do
                if vv.name == id then
                    local co = v.wrap.pushItems(settings.self_id, kk, amountt, 1)
                    turtle.drop(amountt)
                    return co
                end
            end
        end
    end
    while remaining > 0 do
        local ca = itemDrop(id, remaining)
        remaining = remaining - ca
    end
end

function getItemDataById(uuid)
    sendModem(settings.com_port, settings.server_id, "getItemById", {
        uuid = uuid
    })
    local side, channel, replyChannel, message, distance = receiveModem(function(side, channel, replyChannel, message, distance)
        return (type(message) == "table") and (message.to == os.getComputerID()) and ((message.mode == "itemData") or (message.mode == "error")) 
    end, 2)
    if side ~= nil then
        if message.mode == "error" then
            print("Server had an error: "..message.data.message)
        else
            message.data.getPrice = function()
                local price = message.data.price
                if not message.data.dp_forcePrice then
                    local ic = message.data.dp_normalStock / message.data.count
                    local np = message.data.price * ic
                    np = math.floor(np*100)/100
                    if np == 0 then
                        np = message.data.price
                    end
                    price = np
                end
                if message.data.discount == 0 then
                    return price
                else
                    local nnp = math.floor((price-(price*(message.data.discount/100)))*100)/100
                    if nnp == 0 then
                        nnp = message.data.price
                    end
                    return nnp
                end
            end
            return message.data
        end
    else
        print("Server does not responding...")
    end
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

function giveReceipt(checkout)
    local shopInfo = getShopInfo()
    while shopInfo == nil do
        shopInfo = getShopInfo()
        os.sleep(0)
    end
    local printer = peripheral.find("printer")
    if (printer ~= nil) and (printer.getPaperLevel() > 0) and (printer.getInkLevel() > 0) then
        printer.newPage()
        printer.setPageTitle("Shop purchase")

        printer.setCursorPos(1,1)
        printer.write(shopInfo.name)
        printer.setCursorPos(1,2)
        printer.write(shopInfo.desc)
        printer.setCursorPos(1,3)
        printer.write("Owner: "..shopInfo.owner)
        printer.setCursorPos(1,4)
        printer.write(" --- RECEIPT --- ")
        local cartItems = 0
        for k,v in pairs(checkout.cart) do
            cartItems = cartItems + 1
            local gitem = getItemDataById(k)
            printer.setCursorPos(1,4+cartItems)
            printer.write(gitem.name.." x"..v.."("..(v*gitem.getPrice())..")")
        end
        printer.setCursorPos(1,4+cartItems+1)
        printer.write(" --- RECEIPT --- ")
        printer.setCursorPos(1,4+cartItems+2)
        printer.write("Cost: "..checkout.price.."kst")
        printer.setCursorPos(1,4+cartItems+3)
        printer.write("Paid: "..checkout.paid.."kst")
        printer.setCursorPos(1,4+cartItems+4)
        printer.write("Change: "..math.floor(math.abs(checkout.remaining)).."kst")
        printer.setCursorPos(1,4+cartItems+6)
        printer.write("Thank you for")
        printer.setCursorPos(1,4+cartItems+7)
        printer.write("your purchase!")
        
        printer.endPage()
        storages[1].wrap.pullItems(settings.printer_id, 8)
        for k,v in ipairs(storages[1].wrap.list()) do
            if v.name == "computercraft:printed_page" then
                storages[1].wrap.pushItems(settings.self_id, k)
                turtle.drop()
                break
            end
        end
    else
        print("Pinter out of ink/paper")
    end
end

local function cartDropper()
    while true do
        local side, channel, replyChannel, message, distance = receiveModem(function(side, channel, replyChannel, message, distance)
            return (type(message) == "table") and (message.to == os.getComputerID()) and (message.mode == "dropCart")
        end)
        for k,v in pairs(message.data.cart) do
            local gitem = getItemDataById(k)
            while gitem == nil do
                gitem = getItemDataById(k)
                os.sleep(0)
            end
            dropItems(gitem.id, v)
        end
        giveReceipt(message.data)
        os.sleep(0)
    end
end

parallel.waitForAny(function()
    local ok,err = pcall(regger)
    if not ok then
        print(err)
    end
end,function()
    local ok,err = pcall(cartDropper)
    if not ok then
        print(err)
    end
end)