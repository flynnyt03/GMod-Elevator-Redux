-- This is only here to stop errors on server load


if SERVER then
	AddCSLuaFile("shared.lua")
end

ENT.Base = "base_anim"
ENT.Type = "anim"

ENT.RenderGroup = RENDERGROUP_BOTH

function ENT:Initialize()
	--[[loc = self:GetPos() -- lets find those tvs
	print(loc)--]]
	print("Redux: Removed old TV")
	self:DrawShadow( false )
	self:SetNotSolid(true)
	self:SetNoDraw( true )
end
