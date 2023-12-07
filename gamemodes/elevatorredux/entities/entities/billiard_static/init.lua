------------------------------------------------------------
-- MBilliards by Athos Arantes Pereira
-- Contact: athosarantes@hotmail.com
------------------------------------------------------------
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

function ENT:Initialize()
	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	self:DrawShadow(false)
	self:SetUseType(SIMPLE_USE)
end

function ENT:Use(ply, caller)

	if !ply:IsPlayer() then return end

	local ptable = ply:GetBilliardTable()
	if !ptable then return end

	ptable:Use(ply, caller, USE_ON, 1)

end