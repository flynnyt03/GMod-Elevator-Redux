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
	self:SetUseType(SIMPLE_USE)
end

function ENT:Use(ply, caller)
	if not ply:IsPlayer() then return end
	local ptable = self:GetBilliardTable()
	if not ptable then return end

	return ptable:UsePressed(ply, caller)
end

function ENT:PhysicsCollide(data, physobj)
	if GetConVar("billiard_walk_across_a_table"):GetBool() then return end

	local ply = data.HitEntity
	if not ply:IsPlayer() then return end
	local ptable = self:GetBilliardTable()
	if not ply.BilliardTableID or ply.BilliardTableID ~= self.BilliardTableID then return end
	if ply:GetPos()[3] < self:GetPos()[3] + 37.5 then return end

	if ptable:GetOpponentPlayer(ply) then
		ptable.Turn = ptable:GetOpponentPlayer(ply).bpID

		return ptable:EndBilliardGame()
	end

	ptable:ClearEnts()
	ptable:ClearPlayers()
	ptable:ResetVars()
end