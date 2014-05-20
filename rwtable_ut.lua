--
--------------------------------------------------------------------------------
--         FILE:  rwtable_ut.lua
--        USAGE:  ./rwtable_ut.lua 
--  DESCRIPTION:  
--      OPTIONS:  ---
-- REQUIREMENTS:  ---
--         BUGS:  ---
--        NOTES:  ---
--       AUTHOR:  John (J), <chexiongsheng@qq.com>
--      COMPANY:  
--      VERSION:  1.0
--      CREATED:  2014年05月20日 16时06分39秒 CST
--     REVISION:  ---
--------------------------------------------------------------------------------
--


require 'lunit'
local rwtable = require 'rwtable'

module( "base", package.seeall, lunit.testcase )

local key = 'abcd'

rwtable.intercept_G()

function setup()
    rwtable.put(key, {
        b = {c = 1111}, 
        [5] = 1,
        x = {y = {z = 100}}
    })
end

function teardown()
    rwtable._clear_up()
end

function test_base()
    local r = rwtable.read_obj(key)
    local w1 = rwtable.write_obj(key)
    assert_equal(1111, r.b.c)
    assert_false(rwtable.is_dirty(key, r))
    w1[5] = 2
    assert_false(rwtable.is_dirty(key, r))
    rwtable.commit(key, w1)
    assert_false(rwtable.is_dirty(key, r))
    local w2 = rwtable.write_obj(key)
    w2.b.c = 2222
    assert_false(rwtable.is_dirty(key, r))
    rwtable.commit(key, w2)
    assert_true(rwtable.is_dirty(key, r))
end

function test_pairs()
    local w = rwtable.write_obj(key)
    local r = rwtable.read_obj(key)
    for k, v in pairs(r) do
        --print(k, v)
    end
    w[5] = 2
    assert_false(rwtable.is_dirty(key, r))
    rwtable.commit(key, w)
    assert_true(rwtable.is_dirty(key, r))
end

