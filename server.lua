local sf = fs.open("config.txt", "r")
local settings = textutils.unserialise(sf.readAll())
sf.close()
local ic = fs.open("items.txt", "r")
settings.items = textutils.unserialise(ic.readAll())
ic.close()

function loadCache(filename)
    local fa = fs.open(filename, "r")
    local fi = fa.readAll()
    fi = fi:gsub("SYSTEM CACHE, DO NOT EDIT!","")
    fa.close()
    return textutils.unserialise(fi)
end

function saveCache(filename, data)
    local fa = fs.open(filename, "w")
    fa.write("SYSTEM CACHE, DO NOT EDIT!"..textutils.serialise(data))
    fa.close()
end

if not fs.exists("userkst.txt") then
    saveCache("userkst.txt", {})
end

if not fs.exists("reviews.txt") then
    local fa = fs.open("reviews.txt", "w")
    fa.write()
    fa.close()
end

for k,v in ipairs(settings.items) do
    settings.items[k].getPrice = function()
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

if _G.shipshopkws then
    _G.shipshopkws.close() 
end

local modem = peripheral.find("modem")
local kapi = require("kristapi")
local dw = require("discordWebhook")

local carts = {}
local cashiers = {}
local checkouts = {}
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

-- Checks the item counts
function getItemCount(id)
    local co = 0
    for k,v in ipairs(storages) do
        for kk,vv in pairs(v.wrap.list()) do
            if vv.name == id then
                co = co + vv.count
            end
        end
    end
    return co
end
function getItemCountNoCart(uuid)
    local _,gitem = getItemById(uuid)
    local inCartAmount = 0
    for k,v in pairs(carts) do
        for kk,vv in pairs(v) do
            if kk == uuid then
                inCartAmount = inCartAmount + vv
            end
        end
    end
    return getItemCount(gitem.id) - inCartAmount
end

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

--- Gets an item by its id from configurated item list
--- @param id string The id of the item to retrieve
--- @return number key of the item in settings.items
--- @return table the item
function getItemById(uuid)
    for k,v in pairs(settings.items) do
        if v.uuid == uuid then
            return k, v
        end
    end
    return nil, nil
end

function copy(tbl)
    local out = {}
    for k,v in pairs(tbl) do
        out[k] = v 
    end
    return out
end

local function isPlayerOnline(player)
    local online = chatbox.getPlayers()
    for k,v in ipairs(online) do
        if v.name:lower() == player then
            return true
        end
    end
    return false
end

local function onMMessage(side, channel, replyChannel, message, distance)
    print("Got packet from: "..message.from..", mode: "..message.mode)
    if message.mode == "getItemById" then
        local _,gitem = getItemById(message.data.uuid)
        if gitem == nil then
            sendModem(settings.com_port, message.from, "error", {
                message = "Invalid item uuid",
                type = "invalid_item_uuid"
            })
            return
        end
        local itemdata = copy(gitem)
        itemdata.count = getItemCountNoCart(message.data.uuid)
        if not settings.dp_enabled then
            itemdata.dp_forcePrice = true
        end
        sendModem(settings.com_port, message.from, "itemData", itemdata)
    elseif message.mode == "getItems" then
        local itemdatas = copy(settings.items)
        for k,v in ipairs(itemdatas) do
            itemdatas[k].count = getItemCountNoCart(v.uuid)
            if not settings.dp_enabled then
                itemdatas[k].dp_forcePrice = true
            end
        end
        sendModem(settings.com_port, message.from, "items", itemdatas)
    elseif message.mode == "getShopInfo" then
        sendModem(settings.com_port, message.from, "shopInfo", {
            name = settings.shop_name,
            desc = settings.shop_desc,
            owner = settings.shop_owner,
            address = settings.shop_address
        })
    elseif message.mode == "addItemToCart" then
        message.data.user = message.data.user:lower()
        local _,gitem = getItemById(message.data.item)
        if carts[message.data.user] == nil then
            carts[message.data.user] = {}
        end
        if gitem == nil then
            sendModem(settings.com_port, message.from, "error", {
                message = "Invalid item uuid",
                type = "invalid_item_uuid"
            })
            return
        end
        if not isPlayerOnline(message.data.user) then
            sendModem(settings.com_port, message.from, "error", {
                message = "Player is not online",
                type = "player_is_not_online"
            })
            return
        end
        if carts[message.data.user][message.data.item] == nil then
            carts[message.data.user][message.data.item] = 0
        end
        local icn = getItemCountNoCart(message.data.item)+carts[message.data.user][message.data.item]
        carts[message.data.user][message.data.item] = carts[message.data.user][message.data.item] + 1
        if carts[message.data.user][message.data.item] > icn then
            carts[message.data.user][message.data.item] = icn
            sendModem(settings.com_port, message.from, "error", {
                message = "Item out of stock",
                type = "item_out_of_stock",
            })
            return
        end
        sendModem(settings.com_port, message.from, "success", {
            message = "Item added to cart",
            type = "item_added_to_cart"
        })
        chatbox.tell(message.data.user,"&ax1 &f"..gitem.name.." added to your cart, your cart now contains &ax"..carts[message.data.user][message.data.item],settings.shop_name,nil,"format")
        sendModem(settings.com_port, "all", "itemDataUpdate", {})
    elseif message.mode == "registerCashier" then
        cashiers[message.data.id] = {
            id = message.from
        }
        sendModem(settings.com_port, message.from, "success", {
            message = "Cashier Registered",
            type = "cashier_registered"
        })
    end
end

local function modemes()
    while true do
        local side, channel, replyChannel, message, distance = receiveModem(function(side, channel, replyChannel, message, distance)
            return (type(message) == "table") and (message.to == os.getComputerID())
        end)
        onMMessage(side, channel, replyChannel, message, distance)
    end
end

local function onCMessage(user, command, args)
    user = user:lower()
    if args[1] == "help" then
        local help = 
[[
`\]]..settings.shop_command[1]..[[ help`: The help command
`\]]..settings.shop_command[1]..[[ info`: Shows some info about the shop
`\]]..settings.shop_command[1]..[[ balance`: The balance kept from the previous purchase
`\]]..settings.shop_command[1]..[[ review <message>`: The balance kept from the previous purchase
`\]]..settings.shop_command[1]..[[ cart <set/list/remove/clear> [<uuid>] [<count>]`: List the cart, remove from the cart or clear the cart
`\]]..settings.shop_command[1]..[[ checkout <cancel/cashier_id>`: Pay for the items in your cart
]]
        chatbox.tell(user,help,settings.shop_name,nil,"markdown")
    elseif args[1] == "review" then
        if args[2] == nil then
            chatbox.tell(user,"&cUsage: \\"..settings.shop_command[1].." review <message>",settings.shop_name,nil,"format")
            return
        end
        local txt = ""
        for i=2,#args do
            txt = txt .. args[i] .. " " 
        end
        local fa = fs.open("reviews.txt", "r")
        local ffa = fa.readAll()
        fa.close()
        local fb = fs.open("reviews.txt", "w")
        fb.write(ffa..os.date().." "..user..": "..txt.."\n")
        fb.close()
        chatbox.tell(user,"&aReview saved!",settings.shop_name,nil,"format")
    elseif args[1] == "info" then
        chatbox.tell(user,"&a"..settings.shop_name.."\n&7Description: "..settings.shop_desc.."\n&7Owner(s): "..settings.shop_owner.."\n&7Software: ShipShop\n&aMake sure to /sethome "..settings.shop_name,settings.shop_name,nil,"format")
    elseif args[1] == "balance" then
        local userkst = loadCache("userkst.txt")
        if userkst[user] == nil then
            userkst[user] = 0
        end
        chatbox.tell(user,"&aBalance: &6"..userkst[user].."kst",settings.shop_name,nil,"format")
    elseif args[1] == "cart" then
        if args[2] == "list" then
            local out = ""
            if carts[user] == nil then
                carts[user] = {}
            end
            local co = 0
            for k,v in pairs(carts[user]) do
                local _,gitem = getItemById(k)
                if v > 0 then
                    out = out .. "&ax"..v.." &6" .. gitem.name.."&7("..gitem.uuid..")&6("..(gitem.getPrice() * v).."kst)&f, "
                end
                co = co + v
            end
            local ccost = 0
            for k,v in pairs(carts[user]) do
                local _,gitem = getItemById(k)
                ccost = ccost + (gitem.getPrice() * v)
            end
            out = "Your cart&a("..co..")&f: " .. (co > 0 and out or "&7Empty") .. "\n&fCart cost: &6"..ccost.."kst"
            chatbox.tell(user,out,settings.shop_name,nil,"format")
        elseif args[2] == "clear" then
            carts[user] = {}
            chatbox.tell(user,"&aYour cart has been cleared!",settings.shop_name,nil,"format")
            sendModem(settings.com_port, "all", "itemDataUpdate", {})
        elseif args[2] == "remove" then
            if (args[3] == nil) or (args[4] == nil) then
                chatbox.tell(user,"&cUsage: \\"..settings.shop_command[1].." cart remove <uuid> <count>",settings.shop_name,nil,"format")
                return
            end
            if tonumber(args[4]) == nil then
                chatbox.tell(user,"&cCount must be a number",settings.shop_name,nil,"format")
                return
            end
            if carts[user] == nil then
                carts[user] = {}
            end
            if carts[user][args[3]] == nil then
                chatbox.tell(user,"&cYour cart does not contains this item!",settings.shop_name,nil,"format")
            else
                if tonumber(args[4]) < 1 then
                    chatbox.tell(user,"&cThe remove count must be more than 0",settings.shop_name,nil,"format")
                end
                local _,gitem = getItemById(args[3])
                if tonumber(args[4]) > carts[user][args[3]] then
                    chatbox.tell(user,"&aRemoved x"..carts[user][args[3]].." &f"..gitem.name.." &afrom your cart",settings.shop_name,nil,"format")
                    carts[user][args[3]] = 0
                else
                    chatbox.tell(user,"&aRemoved x"..tonumber(args[4]).." &f"..gitem.name.." &afrom your cart",settings.shop_name,nil,"format")
                    carts[user][args[3]] = carts[user][args[3]] - tonumber(args[4])
                end
                sendModem(settings.com_port, "all", "itemDataUpdate", {})
            end
        elseif args[2] == "set" then
            if (args[3] == nil) or (args[4] == nil) then
                chatbox.tell(user,"&cUsage: \\"..settings.shop_command[1].." cart set <uuid> <count>",settings.shop_name,nil,"format")
                return
            end
            if tonumber(args[4]) == nil then
                chatbox.tell(user,"&cCount must be a number",settings.shop_name,nil,"format")
                return
            end
            if carts[user][args[3]] == nil then
                chatbox.tell(user,"&cYour cart does not contains this item!",settings.shop_name,nil,"format")
            else
                if tonumber(args[4]) < 1 then
                    chatbox.tell(user,"&cCount must be more than 0",settings.shop_name,nil,"format")
                    return
                end
                local icn = getItemCountNoCart(args[3])+carts[user][args[3]]
                carts[user][args[3]] = tonumber(args[4])
                if carts[user][args[3]] > icn then
                    carts[user][args[3]] = icn
                end
                local _,gitem = getItemById(args[3])
                chatbox.tell(user,"Your cart now contains &ax"..carts[user][args[3]].." "..gitem.name,settings.shop_name,nil,"format")
                sendModem(settings.com_port, "all", "itemDataUpdate", {})
            end
        else
            chatbox.tell(user,"&cUsage: \\"..settings.shop_command[1].." cart <set/list/remove/clear> [<uuid>] [<count>]",settings.shop_name,nil,"format")
        end
    elseif args[1] == "checkout" then
        if args[2] == nil then
            chatbox.tell(user,"&cUsage: \\"..settings.shop_command[1].." checkout <cancel/cashier_id>",settings.shop_name,nil,"format")
            return
        end
        if args[2] == "cancel" then
            if checkouts[user] ~= nil then
                for k,v in ipairs(checkouts[user].paidFrom) do
                    if v["return"] then
                        kapi.makeTransaction(settings.shop_pKey, v.address, v.value, v["return"]..";message=Checkout cancelled!")
                    else
                        kapi.makeTransaction(settings.shop_pKey, v.address, v.value, ";message=Checkout cancelled!")
                    end
                end
                checkouts[user] = nil
                chatbox.tell(user,"&aCheckout cancelled!",settings.shop_name,nil,"format")
            else
                chatbox.tell(user,"&cYou are currently not in a checkout!",settings.shop_name,nil,"format")
            end
            return
        end
        if tonumber(args[2]) == nil then
            chatbox.tell(user,"&cCashier id must be a number",settings.shop_name,nil,"format")
            return
        end
        if cashiers[tonumber(args[2])] == nil then
            chatbox.tell(user,"&cInvalid cashier",settings.shop_name,nil,"format")
            return
        end
        if checkouts[user] == nil then
            local pr = 0
            local bs = false
            for k,v in pairs(carts[user]) do
                local _,gitem = getItemById(k)
                pr = pr + (gitem.getPrice() * v)
                if v > 0 then
                    bs = true
                end
                if v > getItemCount(gitem.id) then
                    chatbox.tell(user,"&cNot enough items: &ax"..v.." &f"..gitem.name,settings.shop_name,nil,"format")
                    return
                end
            end
            if not bs then
                chatbox.tell(user,"&cYou must buy something",settings.shop_name,nil,"format")
                return
            end
            local userkst = loadCache("userkst.txt")
            if userkst[user] == nil then
                userkst[user] = 0
            end
            local prc = pr-userkst[user]
            if prc < 0 then
                prc = 0
            end 
            checkouts[user] = {
                price = prc,
                remaining = prc,
                paid = 0,
                cart = copy(carts[user]),
                cashier = tonumber(args[2]),
                paidFrom = {}
            }
            chatbox.tell(user,"&6Please send &a"..prc.."kst &6to &a"..settings.shop_address.." &6with meta: &ausername="..user.." &c&l(NOT REQUIRED IF YOU PAY FROM SWITCHCRAFT)",settings.shop_name,nil,"format")
        else
            chatbox.tell(user,"&cYou are currently in a checkout, cancel it with \\"..settings.shop_command[1].." checkout cancel",settings.shop_name,nil,"format")
            return
        end
    else
        chatbox.tell(user,"&cInvalid command",settings.shop_name,nil,"format")
    end
end

local function chatboxos()
    local function isCommand(cmd)
        for k,v in ipairs(settings.shop_command) do
            if v == cmd then
                return true
            end
        end
        return false
    end
    while true do
        local event, user, command, args = os.pullEvent("command")
        if isCommand(command) then
            onCMessage(user, command, args)
        end
    end
end

function initSocket()
    local socket = kapi.websocket()
    socket.send(textutils.serialiseJSON({
        type = "subscribe",
        id = 1,
        event = "transactions"
    }))
    _G.shipshopkws = socket
    return function()
        local ok,data = pcall(socket.receive)

        if not ok then
            print("Socket error: "..data)
            socket.close()
            return initSocket()()
        end
        return data
    end
end

function returnKrist(trans,amount,message)
    if trans.meta["return"] then
        kapi.makeTransaction(settings.shop_pKey, trans.from, amount, trans.meta["return"]..(message ~= nil and ";message="..message or ""))
    else
        kapi.makeTransaction(settings.shop_pKey, trans.from, amount, (message ~= nil and ";message="..message or ""))
    end
end

function mindTrans(trans)
    return (trans.to == settings.shop_address) and (trans.meta.donate ~= "true")
end

function sendHook(trans)
    local chout = checkouts[trans.meta.username]
    local citems = ""
    for k,v in pairs(chout.cart) do
        local _,gitem = getItemById(k)
        citems = citems .. gitem.name.." x"..v.."("..(v*gitem.getPrice())..")\n"
    end
    local emb = dw.createEmbed()
        :setTitle("Purchase info")
        :setColor(3302600)
        :addField("From address", trans.from, true)
        :addField("Paid", chout.paid.."kst", true)
        :addField("Return address", trans.meta["return"] and trans.meta["return"] or "Address", true)
        :addField("-", "-")
        :addField("Cart", citems, true)
        :addField("Cost", chout.price.."kst", true)
        :addField("Remaining", checkouts[trans.meta.username].remaining.."kst", true)
        :setAuthor("Shipshop")
        :setFooter("Shipshop")
        :setTimestamp()
    if chout.whmsgid == nil then
        local msg = dw.sendMessage(settings.webhook_url, settings.shop_name, nil, "", {emb.sendable()}) 
        chout.whmsgid = msg.id
    else
        dw.editMessage(settings.webhook_url, chout.whmsgid, "", {emb.sendable()}) 
    end
end

local function transos()
    sock = initSocket()

    local function onTrans(json)
        if json.type == "event" and json.event == "transaction" then
            local trans = json.transaction
            trans.meta = kapi.parseMeta(trans.metadata)
            if mindTrans(trans) then
                if checkouts[trans.meta.username] ~= nil then
                    checkouts[trans.meta.username].paid = checkouts[trans.meta.username].paid + trans.value
                    checkouts[trans.meta.username].remaining = checkouts[trans.meta.username].price - checkouts[trans.meta.username].paid
                    table.insert(checkouts[trans.meta.username].paidFrom, {
                        address = trans.from,
                        ["return"] = trans.meta["return"],
                        value = trans.value
                    })
                    sendHook(trans)
                    if checkouts[trans.meta.username].remaining < 1 then
                        if math.floor(math.abs(checkouts[trans.meta.username].remaining)) > 0 then
                            returnKrist(trans,math.floor(math.abs(checkouts[trans.meta.username].remaining)),"Here is your change!")
                        end
                        local cartCost = 0
                        for k,v in pairs(carts[trans.meta.username]) do
                            local _,gitem = getItemById(k)
                            cartCost = cartCost + (gitem.getPrice() * v)
                        end
                        local remm = cartCost - checkouts[trans.meta.username].paid
                        local savedBalance = math.abs(remm)-math.floor(math.abs(remm))
                        local userkst = loadCache("userkst.txt")
                        if checkouts[trans.meta.username].price <= 0 then
                            userkst[trans.meta.username] = userkst[trans.meta.username] - cartCost
                        else
                            userkst[trans.meta.username] = 0
                        end
                        userkst[trans.meta.username] = userkst[trans.meta.username] + savedBalance
                        chatbox.tell(trans.meta.username,"&aThank you for your purchase, &cCashier"..checkouts[trans.meta.username].cashier.." &awill drop your items\nThe remaining &6"..userkst[trans.meta.username].."kst &ais stored for your next purchase",settings.shop_name,nil,"format")
                        saveCache("userkst.txt",userkst)
                        carts[trans.meta.username] = {}
                        sendModem(settings.com_port, "all", "itemDataUpdate", {})
                        os.sleep(0)
                        sendModem(settings.com_port, cashiers[checkouts[trans.meta.username].cashier].id, "dropCart", checkouts[trans.meta.username])
                        checkouts[trans.meta.username] = nil
                    else
                        chatbox.tell(trans.meta.username,"&aPaid: &6"..checkouts[trans.meta.username].paid.."kst&a, Remaining: &6"..checkouts[trans.meta.username].remaining.."kst",settings.shop_name,nil,"format")
                    end
                else
                    returnKrist(trans,trans.value,"You are currently not in a checkout")
                end
            end
        end
    end

    while true do
        local data = sock()
        if not data then
            print("Socket error")
        else
            local ok,json = pcall(textutils.unserialiseJSON, data)
            if not ok then
                print("JSON error: "..json)
            else
                onTrans(json)
            end
        end
    end
end

local function borderes()
    while true do
        local handle = http.get("https://dynmap.sc3.io/up/world/SwitchCraft/")
        local sensed = textutils.unserialiseJSON(handle.readAll())
        handle.close()
        for k,v in ipairs(sensed.players) do
            if carts[v.name:lower()] ~= nil then
                if (v.x < settings.border.x1) or (v.x > settings.border.x2) or (v.z < settings.border.z1) or (v.z > settings.border.z2) then 
                    carts[v.name:lower()] = nil
                    chatbox.tell(user,"&cYou left the market, your cart have been removed!",settings.shop_name,nil,"format")
                end
            end
        end
        for k,v in pairs(carts) do
            if not isPlayerOnline(k) then
                carts[v.name:lower()] = nil
            end
        end
        os.sleep(60)
    end
end

parallel.waitForAny(function()
    local ok,err = pcall(modemes)
    if not ok then
        print(err)
    end
end,function()
    local ok,err = pcall(chatboxos)
    if not ok then
        print(err)
    end
end,function()
    local ok,err = pcall(transos)
    if not ok then
        print(err)
    end
end,function()
    local ok,err = pcall(borderes)
    if not ok then
        print(err)
    end
end)
