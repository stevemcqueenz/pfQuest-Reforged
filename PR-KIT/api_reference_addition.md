<!-- Addition for docs/api_reference.md: new "World" section, and add
     "[World](#world)" to the nav line at the top of the file. -->

# World
World-space helpers: read unit positions in world coordinates and project any world point onto the screen using the client's own camera projection.

## UnitPosition `API`
**Arguments:** `unitId` (string)
**Returns:** `x, y, z` (numbers) or nothing

World position of a unit in yards. Resolves any unit token the client knows (player, party1, target, nameplate tokens). Returns nothing when the token does not resolve, for example a party member beyond the object manager's range. Works indoors and in instances, where the map position APIs return nothing.

```lua
local x, y, z = UnitPosition("party1")
if x then
  -- party1 is in object range
end
```

## WorldToScreen `API`
**Arguments:** `x, y, z` (numbers)
**Returns:** `sx, sy, visible` (number, number, 1 or nil)

Projects a world position onto the screen using the client's own camera projection. `sx, sy` are in the UI coordinate space produced by the client (origin bottom left, 1024x768 percent base); multiply by `UIParent:GetWidth() / 1024` and `UIParent:GetHeight() / 768` for UIParent-relative coordinates. `visible` is 1 when the point is inside the camera view and nil otherwise; coordinates are still returned while not visible so off-screen indicators can be driven from them.

```lua
local px, py, pz = UnitPosition("player")
local sx, sy, visible = WorldToScreen(px, py, pz)
if visible then
  frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", sx * UIParent:GetWidth() / 1024, sy * UIParent:GetHeight() / 768)
end
```
