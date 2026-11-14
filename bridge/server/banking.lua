-- blaze_bossmenu | GNU GPL v3 (see LICENSE) | based on qbx_management by the Qbox Project (see NOTICE.md)
-- Society account bridge. Auto-detects the same banking resources Blaze Medical supports:
-- Renewed-Banking, qb-banking, okokBanking, qb-management. Withdraw checks the balance first.
-- If none is started, Funds are treated as off (one console warning).
if not Config.enabled then return end

Banking = {}

local adapters = {
    {
        res = 'Renewed-Banking',
        balance = function(acc) return exports['Renewed-Banking']:getAccountMoney(acc) end,
        add = function(acc, amt) return exports['Renewed-Banking']:addAccountMoney(acc, amt) end,
        remove = function(acc, amt) return exports['Renewed-Banking']:removeAccountMoney(acc, amt) end,
    },
    {
        res = 'qb-banking',
        balance = function(acc) return exports['qb-banking']:GetAccountBalance(acc) end,
        add = function(acc, amt, why) return exports['qb-banking']:AddMoney(acc, amt, why) end,
        remove = function(acc, amt, why) return exports['qb-banking']:RemoveMoney(acc, amt, why) end,
    },
    {
        res = 'okokBanking',
        balance = function(acc) return exports['okokBanking']:GetAccount(acc) end,
        add = function(acc, amt) return exports['okokBanking']:AddMoney(acc, amt) end,
        remove = function(acc, amt) return exports['okokBanking']:RemoveMoney(acc, amt) end,
    },
    {
        res = 'qb-management',
        balance = function(acc) return exports['qb-management']:GetAccount(acc) end,
        add = function(acc, amt) return exports['qb-management']:AddMoney(acc, amt) end,
        remove = function(acc, amt) return exports['qb-management']:RemoveMoney(acc, amt) end,
    },
}

local function adapter()
    for _, a in ipairs(adapters) do
        if GetResourceState(a.res) == 'started' then return a end
    end
end

--- Name of the detected banking resource, or nil
function Banking.resource()
    local a = adapter()
    return a and a.res or nil
end

function Banking.available() return adapter() ~= nil end

--- Balance as a number, or nil if the account/resource can't be read
function Banking.getBalance(account)
    local a = adapter()
    if not a or not account then return nil end
    local ok, res = pcall(a.balance, account)
    if not ok then return nil end
    if type(res) == 'table' then res = res.balance or res.account_balance or res.amount end
    return tonumber(res)
end

function Banking.deposit(account, amount, reason)
    local a = adapter()
    if not a or not account or not amount or amount <= 0 then return false end
    local ok, res = pcall(a.add, account, amount, reason or 'blaze_bossmenu')
    return ok and res ~= false
end

--- Returns false when the account doesn't hold enough (checked first)
function Banking.withdraw(account, amount, reason)
    local a = adapter()
    if not a or not account or not amount or amount <= 0 then return false end
    local balance = Banking.getBalance(account)
    if not balance or balance < amount then return false end
    local ok, res = pcall(a.remove, account, amount, reason or 'blaze_bossmenu')
    return ok and res ~= false
end

-- Banking resources can start after us: warn once, a little after startup
CreateThread(function()
    Wait(10000)
    if Config.funds.enabled and not Banking.available() then
        print('^3[blaze_bossmenu]^7 No supported banking resource found (Renewed-Banking, qb-banking, okokBanking, qb-management). Funds are off.')
    end
end)
