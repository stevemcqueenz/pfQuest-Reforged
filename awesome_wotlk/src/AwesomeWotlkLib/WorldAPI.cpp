#include "WorldAPI.h"
#include "GameClient.h"
#include "Lua.h"
#include "Hooks.h"

// World<->screen bridge for addons: exposes the client's OWN projection to Lua
// so UI can be pinned at world positions (in-world waypoints/markers,
// compass pins). The client function was already mapped in GameClient.h
// (CGWorldFrame::To2D @ 0x004F6D20) but never exported; this only wires it up.

namespace {

// UnitPosition("unit") -> x, y, z (world yards), or nothing when the token
// does not resolve. Same resolution path as the Unit* state APIs (UnitAPI.cpp).
int lua_UnitPosition(lua_State* L)
{
    CGUnit_C* unit = ObjectMgr::Get<CGUnit_C>(ObjectMgr::GetGuidByUnitID(Lua::luaL_checkstring(L, 1)), TYPEMASK_UNIT);
    if (!unit) return 0;
    C3Vector pos;
    unit->GetPosition(pos);
    Lua::lua_pushnumber(L, pos.X);
    Lua::lua_pushnumber(L, pos.Y);
    Lua::lua_pushnumber(L, pos.Z);
    return 3;
}

// WorldToScreen(x, y, z) -> screenX, screenY, visible
// screenX/screenY are in the UI coordinate space PercToScreenPos produces
// (origin bottom-left); `visible` is 1 when the point projects on screen and
// nil otherwise -- kept as 1/nil (not a boolean) for compatibility with the
// first WorldAPI builds and with the client's own IsEventRegistered-style
// returns; addon-side `if visible then` reads the same either way.
// Coordinates are still returned when not visible so callers can edge-clamp.
int lua_WorldToScreen(lua_State* L)
{
    CGWorldFrame* wf = CGWorldFrame::GetWorldFrame();
    if (!wf) return 0;
    C3Vector pos3d = { (float)Lua::luaL_checknumber(L, 1), (float)Lua::luaL_checknumber(L, 2), (float)Lua::luaL_checknumber(L, 3) };
    C3Vector pos2d = {};
    uint32_t flags = 0;
    int visible = wf->To2D(&pos3d, &pos2d, &flags);
    float sx = 0.f, sy = 0.f;
    CGWorldFrame::PercToScreenPos(pos2d.X, pos2d.Y, &sx, &sy);
    Lua::lua_pushnumber(L, sx);
    Lua::lua_pushnumber(L, sy);
    if (visible != 0)
        Lua::lua_pushnumber(L, 1);
    else
        Lua::lua_pushnil(L);
    return 3;
}

int lua_openworldlib(lua_State* L)
{
    Lua::luaL_Reg funcs[] = {
        { "UnitPosition", lua_UnitPosition },
        { "WorldToScreen", lua_WorldToScreen },
    };

    for (auto& [name, func] : funcs) {
        Lua::lua_pushcfunction(L, func);
        Lua::lua_setglobal(L, name);
    }

    return 0;
}

}

void WorldAPI::initialize()
{
    Hooks::FrameXML::registerLuaLib(lua_openworldlib);
}
