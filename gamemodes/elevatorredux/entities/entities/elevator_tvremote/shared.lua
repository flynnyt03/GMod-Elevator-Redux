-- This is only here to stop errors on server load


if SERVER then
	AddCSLuaFile("shared.lua")
end

ENT.Base = "base_anim"
ENT.Type = "anim"

ENT.RenderGroup = RENDERGROUP_BOTH

function ENT:Initialize()
	print("Redux: Removed old TV Remote")
	self:DrawShadow( false )
	self:SetNotSolid(true)
	self:SetNoDraw( true )
end
