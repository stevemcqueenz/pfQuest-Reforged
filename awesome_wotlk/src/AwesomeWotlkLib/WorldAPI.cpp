#include "WorldAPI.h"
#include "GameClient.h"
#include "Hooks.h"

// World<->screen bridge for addons: exposes the client's OWN projection to Lua so
// UI can be pinned at world positions (in-world waypoints/markers, Skyrim-style
// compass pins). The client function was already mapped in GameClient.h
// (WorldFrame_3Dto2D @ 0x004F6D20) but never exported; this only wires it up.

// UnitPosition("unit") -> x, y, z (world yards), or nothing when the token does
// not resolve. Same resolution path as the Unit* state APIs (UnitAPI.cpp).
static int lua_UnitPosition(lua_State* L)
{
    Unit* unit = (Unit*)ObjectMgr::Get(luaL_checkstring(L, 1), ObjectFlags_Unit);
    if (!unit) return 0;
    VecXYZ pos;
    unit->vmt->GetPosition(unit, &pos);
    lua_pushnumber(L, pos.x);
    lua_pushnumber(L, pos.y);
    lua_pushnumber(L, pos.z);
    return 3;
}

// WorldToScreen(x, y, z) -> screenX, screenY, visible
// screenX/screenY are in the UI coordinate space WorldFrame_PercToScreenPos
// produces (origin bottom-left); `visible` is 1 when the point projects on
// screen and nil otherwise -- 1/nil rather than a boolean because GameClient.h
// maps lua_pushnumber/lua_pushnil but NOT lua_pushboolean (reads the same from
// Lua, and matches the client's own IsEventRegistered-style returns).
// Coordinates are still returned when not visible so callers can edge-clamp.
static int lua_WorldToScreen(lua_State* L)
{
    WorldFrame* wf = GetWorldFrame();
    if (!wf) return 0;
    VecXYZ pos3d = { (float)luaL_checknumber(L, 1), (float)luaL_checknumber(L, 2), (float)luaL_checknumber(L, 3) };
    VecXYZ pos2d = {};
    uint32_t flags = 0;
    int visible = WorldFrame_3Dto2D(wf, nullptr, &pos3d, &pos2d, &flags);
    float sx = 0.f, sy = 0.f;
    WorldFrame_PercToScreenPos(pos2d.x, pos2d.y, &sx, &sy);
    lua_pushnumber(L, sx);
    lua_pushnumber(L, sy);
    if (visible != 0)
        lua_pushnumber(L, 1);
    else
        lua_pushnil(L);
    return 3;
}

static int lua_openworldlib(lua_State* L)
{
    luaL_Reg funcs[] = {
        { "UnitPosition", lua_UnitPosition },
        { "WorldToScreen", lua_WorldToScreen },
    };

    for (const auto& [name, func] : funcs) {
        lua_pushcfunction(L, func);
        lua_setglobal(L, name);
    }

    return 0;
}

void WorldAPI::initialize()
{
    Hooks::FrameXML::registerLuaLib(lua_openworldlib);
}
