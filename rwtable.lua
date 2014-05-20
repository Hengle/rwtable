--
--------------------------------------------------------------------------------
--         FILE:  rwtable.lua
--        USAGE:   
--  DESCRIPTION:  
--      OPTIONS:  ---
-- REQUIREMENTS:  ---
--         BUGS:  ---
--        NOTES:  ---
--       AUTHOR:  John, <chexiongsheng@qq.com>
--      VERSION:  1.0
--      CREATED:  2014年05月19日 17时37分19秒 CST
--     REVISION:  ---
--------------------------------------------------------------------------------
--


local _value_of = {}

local make_wrap_obj, recycle_obj, write_obj_mt, read_obj_mt

local function make_read_obj(obj)
    return make_wrap_obj(obj, read_obj_mt)
end

local function make_write_obj(obj)
    return make_wrap_obj(obj, write_obj_mt)
end

--save the original table func
local original = {table = {}}
original.next = _G.next
original.pairs = _G.pairs
original.ipairs = _G.ipairs
for fun_name, fun in pairs(_G.table) do
    original.table[fun_name] = fun
end

local pairs = _G.pairs
local next = _G.next
local table = _G.table

local function unfold_robj (obj)
    local target_obj = rawget(obj, '__target_obj')
    setmetatable(obj, nil)
    rawset(obj, '__target_obj', nil)
    for k, v in pairs(target_obj) do
        rawset(obj, k, type(v) == 'table' and make_read_obj(v) or v)
    end
    return obj
end

local function unfold_wobj (obj)
    local target_obj = rawget(obj, '__target_obj')
    setmetatable(obj, nil)
    rawset(obj, '__target_obj', nil)
    --shallow copy of target_obj, and if a child is unfold, make a folded object of it 
    for k, v in pairs(target_obj) do
        if type(v) == 'table' then
            local av = rawget(obj, v)
            if av then 
                rawset(obj, k, av)
                rawset(obj, v, nil)
            else
                rawset(obj, k, make_write_obj(v))
            end
        else
            rawset(obj, k, v)
        end
    end
    return obj
end

read_obj_mt = {
    __index = function(t, k)
        local v = rawget(rawget(t, '__target_obj'), k)
        if type(v) == 'table' then
            v = make_read_obj(v)
        end
        rawset(t, k, v)
        return v
    end,
    __newindex = function()
        error('this object readonly!')
    end,
}

write_obj_mt = {
    __index = function(t, k)
        local v = rawget(rawget(t, '__target_obj'), k)
        if type(v) == 'table' then
            local cv = rawget(t, v)
            if cv then
                v = cv
            else
                local nv = make_write_obj(v)
                rawset(t, v, nv)
                v = nv
            end
        else
            error('this object writeonly!')
        end
        return v
    end,
    __newindex = function(t, k, v)
        assert(type(k) ~= 'table')
        if rawget(rawget(t, '__target_obj'), k) == v then return end
        unfold_wobj(t)[k] = v
    end
}


local make_w_table_fun = function(org_fun) --可写
    return function(t, ...)
        if getmetatable(t) == write_obj_mt then
            return org_fun(unfold_wobj(t), ...)
        elseif getmetatable(t) == read_obj_mt then
            error('this object readonly!')
        else
            return org_fun(t, ...)
        end
    end
end
local make_r_table_fun = function(org_fun) --只读
    return function(t, ...)
        if getmetatable(t) == write_obj_mt then
            return org_fun(unfold_wobj(t), ...)
        elseif getmetatable(t) == read_obj_mt then
            return org_fun(unfold_robj(t), ...)
        else
            return org_fun(t, ...)
        end
    end
end
local intercepted = {table = {}}
for fun_name, fun in pairs(_G.table) do
    if fun_name == 'sort' or fun_name == 'remove' or fun_name == 'insert' then
        intercepted.table[fun_name] = make_w_table_fun(fun)
    else
        intercepted.table[fun_name] = make_r_table_fun(fun)
    end
end
intercepted.next = make_r_table_fun(next)
intercepted.pairs = make_r_table_fun(pairs)
intercepted.ipairs = make_r_table_fun(ipairs)
local intercept_tbl_func = function()
    for fun_name, fun in pairs(_G.table) do
        _G.table[fun_name] = intercepted.table[fun_name]
    end
    _G.next = intercepted.next
    _G.pairs = intercepted.pairs
    _G.ipairs = intercepted.ipairs
end

local _obj_list = {}
local _max_obj_list_size = 100
make_wrap_obj = function(obj, mt)
    local ret = table.remove(_obj_list)
    if ret then
        rawset(ret, '__target_obj', obj)
        setmetatable(ret, mt)
        return ret
    else
        return setmetatable({__target_obj = obj}, mt)
    end
end
recycle_obj = function(obj)
    assert(not next(obj))
    if #_obj_list < _max_obj_list_size then
        table.insert(_obj_list, obj)
    end
end

local function _is_dirty(robj, wobj)
    rawset(robj, '__target_obj', nil)
    for k, v in pairs(robj) do
        if type(v) == 'table' then
            if _is_dirty(v, rawget(wobj, k)) then 
                return true
            end
        else
            if v ~= rawget(wobj, k) then 
                return true
            else
            end
        end
    end
    return false
end

local function _merge(obj)
    local obj_modifyed = false

    local target_obj = rawget(obj, '__target_obj')
    rawset(obj, '__target_obj', nil)
    for k, v in pairs(obj) do
        if type(v) == 'table' then
            local nv, bm = _merge(v)
            rawset(obj, k, nv)
            obj_modifyed = obj_modifyed or bm
        end
    end

    if obj_modifyed and target_obj then --merge change to target_obj
        --target_obj is normal obj
        for k, v in pairs(target_obj) do
            local nv = rawget(obj, v)
            if nv then 
                rawset(target_obj, k, nv)
                rawset(obj, v, nil)
            end
        end
    end
    if target_obj then
        recycle_obj(obj)
    end
    return (target_obj or obj), (obj_modifyed or target_obj == nil)
end

local put, read_obj, write_obj, commit, is_dirty, remove, existed

put = function(key, value)
    assert(key ~= nil and type(key) ~= 'table' and type(key) ~= 'userdata', 'key must not be nil or ref type')
    assert(type(value) == 'table', 'value must be a table')
    if existed(key) then return false end
    _value_of[key] = value
    return true
end

read_obj = function(key) 
    assert(key)
    return make_read_obj(_value_of[key])
end

write_obj = function(key)
    assert(key)
    return make_write_obj(_value_of[key])
end

commit = function(key, value)
    assert(key)
    _value_of[key] = _merge(value)
end

is_dirty = function(key, value)
    return _is_dirty(value, _value_of[key])
end

--remove the data(for memory saving)
remove = function(key)
    assert(key)
    _value_of[key] = nil
end

existed = function(key)
    return _value_of[key] ~= nil
end

local M = {
    put = put,
    read_obj = read_obj,
    write_obj = write_obj,
    commit = commit,
    is_dirty = is_dirty,
    remove = remove,
    existed = existed,
    table_func = {
        original = original,
        next = intercepted.next,
        ipairs = intercepted.ipairs,
        pairs = intercepted.pairs,
        table = intercepted.table,
    },
    intercept_G = intercept_tbl_func,
}

--unsafe api, for inner usage only
M._raw_get = function(key) return _value_of[key] end
M._raw_get_all = function() return _value_of end
M._clear_up = function()
    _value_of = {}
end

return M

