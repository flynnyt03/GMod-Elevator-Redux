------------------------------------------------------------
-- MBilliards by Athos Arantes Pereira
-- Contact: athosarantes@hotmail.com
------------------------------------------------------------
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")
-- Lets initialize our main tables
ENT.WaitingPlayers = {}
ENT.PocketedBalls = {}
ENT.BallPositions = {}
ENT.PlayerData = {}
ENT.EntsData = {}
ENT.Balls = {}
-- Lets initialize our vars
ENT.BehindHeadString = true
ENT.WaitBallsToStop = false
ENT.LastGameBallPos = nil
ENT.OpenBreakShot = true
ENT.BallsHitRail = nil
ENT.FirstHitBall = nil
ENT.ThreeCFouls = false
ENT.Points_tmp = nil
ENT.NextPlayer = nil
ENT.LowestNum = nil
ENT.CRHitRed = nil
ENT.Timer = nil
ENT.Foul = false
ENT.Turn = 1
-- These vars, once set up, can't be changed in any way
ENT.Size = 12
ENT.ID = nil
-- These vars can only be changed in config mode
ENT.RoundTime = nil
ENT.GameType = 0
ENT.Training = false
ENT.SmartCue = false
ENT.FPerson = false
ENT.MProtect = false
ENT.ABMethod = 0

-- This will lead the user to a nice derma menu with options, such as skin, table size, etc.
function ENT:SpawnFunction(ply, tr)
	if not tr.Hit then return end
	if GetConVar("billiard_admins_only"):GetBool() and not ply:IsAdmin() or BilliardTables >= GetConVarNumber("billiard_max_tables") then return end
	umsg.Start("billiard_createMenu", ply)
	umsg.Vector(tr.HitPos)
	umsg.End()
end

function ENT:Initialize()
	self.Size = 12
	self:SetModel(string.format("models/billiards/table_%dft.mdl", self.Size))
	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	self:SetUseType(SIMPLE_USE)
	self:ResetVars()
	self.ID = self:EntIndex()
	self:GetPhysicsObject():SetMaterial("billiard_table")
end

function ENT:UsePressed(ply, caller)
	if not ply:IsPlayer() then return end
	-- The activator is trying to enter in a billiard game even already in another one...
	print("use")
	ply.tableinuse = true
	if ply.BilliardTableID ~= nil and ply.BilliardTableID ~= self.ID then
		return
	elseif ply.BilliardTableID == self.ID then
		-- Maybe he wants to exit?
		print("exit")
		umsg.Start("billiard_promptExit", ply)
		umsg.End()

		return
	end

	-- Now we'll check if there is already one player, if so, we'll check if the activator can enter
	-- in the slot #2, but we won't put the activator in game, we'll send the request to the player #1
	if self.PlayerData[1] ~= nil then
		local b_error = nil

		if self.PlayerData[2] ~= nil then
			b_error = "The billiard table is full!"
		elseif self.Training then
			b_error = "The billiard table is in Training mode!"
		elseif self:IsPlayerInList(ply:UniqueID()) then
			b_error = "A request has already been sent!"
		end

		if b_error ~= nil then
			umsg.Start("billiard_scrMsg", ply)
			umsg.String("Error!")
			umsg.String(b_error)
			umsg.End()

			return
		elseif not hook.Call("CanPlayerEnterBilliard", nil, self, ply) then
			return
		end

		local id = table.Count(self.WaitingPlayers) + 1
		self.WaitingPlayers[id] = ply:UniqueID()
		umsg.Start("billiard_sendRequest", self:GetTurnPlayer(1))
		umsg.String(ply:UniqueID())
		umsg.String(ply:GetName())
		umsg.End()
		umsg.Start("billiard_scrMsg", ply)
		umsg.String("Request Sent!")
		umsg.String("A request has been sent! Wait for the answer")
		umsg.End()

		timer.Create("del_wait_ply_" .. id, GetConVarNumber("billiard_req_time"), 1, function()
			table.remove(self.WaitingPlayers, id)
			umsg.Start("billiard_removeRequest", self:GetTurnPlayer(1))
			umsg.String(ply:UniqueID())
			umsg.End()
		end)

		return
	end

	-- The player wants to change the Billiard Table's configuration
	if ply:KeyDown(IN_RELOAD) then
		umsg.Start("billiard_setConfig", ply)
		umsg.Short(self.ID)
		umsg.Short(self.GameType)
		umsg.Short(self.RoundTime)
		umsg.Short(self.ABMethod)
		umsg.Short(self:GetSkin())
		umsg.Bool(self.FPerson)
		umsg.Bool(self.Training)
		umsg.Bool(self.SmartCue)
		umsg.Bool(self.MProtect)
		umsg.End()

		return
	end

	if not hook.Call("CanPlayerEnterBilliard", nil, self, ply) then return end
	-- but if the player is the first one to use this table, we'll setup the vars and start the game...
	ply.BilliardTableID = self.ID
	self.PlayerData[1] = {}
	self.PlayerData[1]["ID"] = ply:UniqueID()
	self.PlayerData[1]["Score"] = 0
	self:StripPlayerWeapons(1)
	self:StartBilliardGame()

	return
end

function ENT:Use(ply, caller)
	self:UsePressed(ply, caller)
end

function ENT:Think()
	self:NextThink(CurTime())
	-- If there are no balls, no need to proceed  xD
	if not self:GetTableEnt() then return true end

	-- We'll check if the "round" time exists and if has expired...
	if self.Timer ~= nil and not self.WaitBallsToStop and self.Timer - CurTime() <= 0 then
		-- if so, next player turn...
		self:GetTurnPlayer():BilliardSpectate()
		self.NextPlayer = nil
		self.Foul = true

		return self:EndRound()
	end

	-- Are we waiting balls to stop moving?
	if not self.WaitBallsToStop then return true end

	-- This avoids the ball returning back when it was supposed to be pocketed... METHOD 2
	if self.ABMethod == 2 and self.GameType ~= BILLIARD_GAMETYPE_CARAMBOL then
		local pckt_ents, pckt_att, physobj

		-- 6 holes xD
		for i = 1, 6 do
			pckt_att = self:GetAttachment(self:LookupAttachment(string.format("hole%02d", i)))
			pckt_ents = ents.FindInSphere(pckt_att.Pos, 0.8)
			if table.Count(pckt_ents) <= 0 then continue end

			for k, v in pairs(pckt_ents) do
				if v:GetClass() ~= "billiard_ball" or v.BilliardTableID ~= self.ID then continue end
				physobj = v:GetPhysicsObject()
				physobj:SetVelocity(Vector(physobj:GetVelocity()[1] * 0.1, physobj:GetVelocity()[2] * 0.1, -80))
			end
		end
	end

	-- Let's make sure all balls are stopped.
	for k, v in pairs(self.Balls) do
		--if(v.BallType != "CueBall" && v:GetPos()[3] <= self:GetPos()[3] + 33) then continue end
		if v:GetPhysicsObject():GetVelocity():Length2DSqr() > 0.03 then return true end
	end

	-- All balls are stopped, let's start the main billiard function...
	self.Timer = nil
	self.WaitBallsToStop = false
	self:ToggleBallsMotion(false)
	self:RulesParser()

	return true
end

function ENT:OnRemove()
	self:ClearEnts()
	self:ClearPlayers()
	BilliardTables = BilliardTables - 1
	if not self.MProtect then return end

	for k, v in pairs(svPBilliardTables) do
		if v ~= self.ID then continue end
		svPBilliardTables[k] = nil
		break
	end
end

function ENT:StartBilliardGame()
	hook.Call("OnBilliardGameStart", nil, self, self:GetTurnPlayer(1), self:GetTurnPlayer(2))

	for i = 1, 2 do
		local ply = self:GetTurnPlayer(i)
		if not ply then continue end

		if self.GameType ~= BILLIARD_GAMETYPE_CARAMBOL then
			self:SetPlayerObjective(ply)
		end

		self:StripPlayerWeapons(i)
		ply.bpID = i
	end

	if not self.PlayerData[1] and self.PlayerData[2] ~= nil then
		self.PlayerData[1] = self.PlayerData[2]
		self.PlayerData[2] = nil
	elseif not self.PlayerData[1] and not self.PlayerData[2] then
		return self:ResetVars()
	end

	self.Timer = CurTime() + self.RoundTime
	self:SyncRoundTime(true) -- Syncronizing the timer with players...

	if self.MProtect then
		local mp = ents.Create("billiard_static")
		mp:SetModel(string.format("models/billiards/minge_p%dft.mdl", self.Size))
		mp:Spawn()
		mp:SetPos(self:GetPos())
		mp:SetAngles(self:GetAngles())
		mp:GetPhysicsObject():SetMaterial("billiard_table")
		mp:GetPhysicsObject():EnableMotion(false)
		mp.BilliardTableID = self.ID
		self.EntsData["MGP"] = mp:EntIndex() -- MGP means MingeBag Protection xD
		constraint.NoCollide(mp, self, 0, 0)
	end

	-- Creating the HeadString collision (or the D-Zone in case of Snooker)...
	local hs = ents.Create("prop_physics")
	hs:SetModel(string.format("models/billiards/headstring%dft.mdl", self.Size))

	if self.GameType == BILLIARD_GAMETYPE_SNOOKER then
		hs:SetModel(string.format("models/billiards/dzone%dft.mdl", self.Size))
	end

	hs:Spawn()
	-- Fixed object transparency
	hs:SetRenderMode(RENDERMODE_TRANSCOLOR)
	hs:SetColor(Color(0, 0, 0, 0))
	hs:SetPos(self:GetPos() - Vector(0, 0, 10))
	hs:SetAngles(self:GetAngles())
	hs:GetPhysicsObject():SetMaterial("billiard_table")
	hs:GetPhysicsObject():EnableMotion(false)
	hs.BilliardTableID = self.ID
	self.EntsData["HSL"] = hs:EntIndex() -- HSL means HeadString Line xD
	constraint.NoCollide(hs, self, 0, 0)
	-- I know it sucks creating different models, but whenever I tried to use the mesh functions it
	-- crashed gmod or didn't work at all, yes, I mean the Entity:PhysicsFromMesh() function.
	-- Creating the balls
	local tmpDat = {}
	tmpDat.c, tmpDat.p = 15, "" -- Ball count, Ball attachment prefix

	if self.GameType == BILLIARD_GAMETYPE_9BALL then
		tmpDat.c, tmpDat.p = 9, "9B_"
	elseif self.GameType == BILLIARD_GAMETYPE_SNOOKER then
		self.OpenBreakShot = false -- There is no Opening Break Shot in snooker
		tmpDat.c, tmpDat.p = 21, "SN_"
		tmpDat.t = {}
		tmpDat.t[1], tmpDat.t[2], tmpDat.t[3] = "Yellow", "Green", "Brown"
		tmpDat.t[4], tmpDat.t[5], tmpDat.t[6] = "Blue", "Pink", "Black"
	elseif self.GameType == BILLIARD_GAMETYPE_CARAMBOL then
		self.OpenBreakShot = false -- No Opening Break Shot in carambol either
		tmpDat.c, tmpDat.p = 2, "CR_"
	end

	local angPos, ball

	for i = 0, tmpDat.c do
		-- Attachments are handy, look how easy is to setup the balls in their positions...
		angPos = self:GetAttachment(self:LookupAttachment(string.format("%sball%02d", tmpDat.p, i)))
		ball = ents.Create("billiard_ball")
		ball:SetPos(angPos.Pos)
		-- We don't want all balls with angle(0,0,0)
		ball:SetAngles(Angle(math.Rand(0, 360), math.Rand(0, 360), math.Rand(0, 360)))
		ball.BilliardTableID = self.ID

		-- Cue Ball xD
		if i == 0 then
			ball.BallType = "CueBall"
			ball.DontRemove = true
			ball:SetSkin(0)
			self.EntsData["CueBall"] = ball:EntIndex()
		end

		ball:Spawn()
		ball.uID = i -- Ball's internal ID

		if self.GameType == BILLIARD_GAMETYPE_8BALL then
			if i >= 1 and i <= 7 then
				ball.BallType = "Solids"
			elseif i == 8 then
				ball.DontRemove = true
			elseif i >= 9 then
				ball.BallType = "Stripes"
			end

			ball:SetSkin(i)
		elseif self.GameType == BILLIARD_GAMETYPE_9BALL then
			if i == 9 then
				ball.DontRemove = true
			end

			ball:SetSkin(i)
		elseif self.GameType == BILLIARD_GAMETYPE_SNOOKER then
			-- 15 Red Balls =D
			if i ~= 0 and i <= 15 then
				ball.BallType = "Red"
				ball.Value = 1
				ball:SetSkin(0)
				ball:SetColor(Color(255, 0, 0, 255))
			elseif i >= 16 then
				ball.BallType = tmpDat.t[i - 15]
				ball.DontRemove = true
				ball.Value = i - 14
				ball:SetColor(Color(self:GetColorByName(tmpDat.t[i - 15])))
			end
		elseif self.GameType == BILLIARD_GAMETYPE_ROTATION and i ~= 0 then
			ball.Value = i
			ball:SetSkin(i)
		elseif self.GameType == BILLIARD_GAMETYPE_CARAMBOL then
			ball:SetSkin(0)

			if i == 1 then
				ball.BallType = "Yellow"
				ball:SetColor(Color(255, 230, 0, 255))
			elseif i == tmpDat.c then
				ball.BallType = "Red"
				ball:SetColor(Color(255, 0, 0, 255))
			end
		end

		self.Balls[i] = ball
		constraint.NoCollide(ball, self:GetTableEnt("MGP"), 0, 0)

		if i ~= 0 then
			constraint.NoCollide(ball, self:GetTableEnt("HSL"), 0, 0)
		end

		-- Creating the pocket collisions, enabled while cue ball in hand
		if i == 0 or i >= 7 or self.GameType == BILLIARD_GAMETYPE_CARAMBOL then continue end
		local HoleAttach = self:GetAttachment(self:LookupAttachment(string.format("hole%02d", i)))
		local hb = ents.Create("prop_physics")
		hb:SetModel("models/billiards/ball.mdl")
		hb:Spawn()
		hb:SetColor(Color(0, 0, 0, 0))
		hb:PhysicsInitSphere(2.9)
		hb:GetPhysicsObject():SetMaterial("billiard_table")
		hb:SetCollisionBounds(Vector(-3.2, -3.2, -3.2), Vector(3.2, 3.2, 3.2))
		hb:GetPhysicsObject():EnableMotion(false)
		hb:SetPos(HoleAttach.Pos - Vector(0, 0, 20))
		hb.BilliardTableID = self.ID
		self.EntsData[string.format("Pocket%02d_col", i)] = hb:EntIndex()
		constraint.NoCollide(hb, self, 0, 0)
		constraint.NoCollide(hb, self:GetTableEnt("MGP"), 0, 0)
		constraint.NoCollide(hb, self:GetTableEnt("HSL"), 0, 0)
	end

	-- Now it's time to create the Cue...
	local cue = ents.Create("billiard_cue")
	cue:Spawn()
	cue:InitialSetup(self.ID)
	cue:UpdateCue()
	self.EntsData["Cue"] = cue:EntIndex()

	if self.GameType == BILLIARD_GAMETYPE_9BALL or self.GameType == BILLIARD_GAMETYPE_ROTATION then
		self.ThreeCFouls = true
		self.LowestNum = self:GetLowestNumber()
	end

	if self.FPerson then
		self:GetTurnPlayer():BilliardSpectate(true, cue, self:GetTableEnt())
	end

	if self.Training then
		self.MovingBall = 0
	end

	local rp, msg = self:GetPlayersFilter()
	self:ToggleCollisions(true, true)
	self:ToggleBallsMotion(false)
	umsg.Start("billiard_toggleHUD", rp)
	umsg.Bool(true)
	umsg.Short(self.GameType)
	umsg.Bool(self.FPerson)
	umsg.End()
	umsg.Start("billiard_mouseLock", rp)
	umsg.Bool(true)
	umsg.End()

	if self.GameType == BILLIARD_GAMETYPE_SNOOKER then
		msg = "Cue ball inside D-Zone"
	elseif self.OpenBreakShot then
		msg = "Opening Break Shot - Cue ball in hand"
	end

	if not msg then return end
	umsg.Start("billiard_sendSMsg", rp)
	umsg.String(msg)
	umsg.End()
end

-- The most complex function in the whole addon...
function ENT:RulesParser()
	local ply = self:GetTurnPlayer()
	local opp = self:GetOpponentPlayer()
	local cObjective = ply.Objective -- The current player objective xD

	-- If we didn't hit any ball, Foul!
	if not self.FirstHitBall and not self.Training and self.GameType ~= BILLIARD_GAMETYPE_CARAMBOL then
		if self.GameType == BILLIARD_GAMETYPE_8BALL then
			if cObjective == "8-Ball" and self:PocketedBall("CueBall") then
				return self:EndBilliardGame(true)
			elseif self.OpenBreakShot then
				self.BehindHeadString = true
				self:RackBalls()
			end
		elseif self.GameType == BILLIARD_GAMETYPE_9BALL then
			self.OpenBreakShot = false
		elseif self.GameType == BILLIARD_GAMETYPE_SNOOKER then
			if self:PocketedBall("CueBall") then
				self.BehindHeadString = true
			end
		end

		self.Foul = true

		return self:EndRound()
	end

	-- NOTE: We don't give the objectives here because it's the Opening Break Shot.
	if self.OpenBreakShot and self.GameType == BILLIARD_GAMETYPE_8BALL then
		if not self:PocketedBall() and self.BallsHitRail < 4 or self:PocketedBall("CueBall") or self:PocketedBall("8-Ball") then
			self:RackBalls()
			self.BehindHeadString = true
			self.Foul = true

			return self:EndRound()
		elseif self:PocketedBall() then
			self.NextPlayer = self.Turn
		end

		self.OpenBreakShot = false

		return self:EndRound()
	elseif self.OpenBreakShot and self.GameType == BILLIARD_GAMETYPE_9BALL then
		if self:PocketedBall("CueBall") or self.FirstHitBall ~= self.LowestNum or self.BallsHitRail < 4 and not self:PocketedBall() then
			self.Foul = true

			return self:EndRound()
		elseif self:PocketedBall("9-Ball") and self.FirstHitBall == self.LowestNum then
			return self:EndBilliardGame() -- The Player won the game on the break shot...
		elseif self:PocketedBall() and self.FirstHitBall == self.LowestNum then
			self.NextPlayer = self.Turn
		end

		self.OpenBreakShot = false

		return self:EndRound()
	elseif self.OpenBreakShot and self.GameType == BILLIARD_GAMETYPE_ROTATION then
		if self:PocketedBall("CueBall") or self.FirstHitBall ~= self.LowestNum or self.BallsHitRail < 4 and not self:PocketedBall() then
			self.Foul = true

			return self:EndRound()
		elseif self:PocketedBall() and self.FirstHitBall == self.LowestNum then
			self:GiveScore(ply)
			self.NextPlayer = self.Turn
		end

		self.OpenBreakShot = false

		return self:EndRound()
	end

	if self.GameType == BILLIARD_GAMETYPE_8BALL then
		if cObjective == "OpenTable" then
			-- Foul if player pockets the Cueball, 8-Ball or pocketes both Stripe and Solid balls
			if self:PocketedBall("Solids") and self:PocketedBall("Stripes") or self:PocketedBall("CueBall") or self:PocketedBall("8-Ball") then
				self.Foul = true

				return self:EndRound()
			end

			-- We didn't make any foul, and if we didn't pocket any ball then the turn ends
			if not self:PocketedBall("Stripes") and not self:PocketedBall("Solids") then return self:EndRound() end
			-- We'll check what type of ball the player pocketed and set his objective.
			local objective = "Stripes"

			if not self:PocketedBall("Stripes") then
				objective = "Solids"
			end

			self:SetPlayerObjective(ply, objective)

			-- Now that we set the objective for this player, we have to check if there is another player,
			-- if so, we need to set his objective too!
			if opp then
				if objective == "Stripes" then
					objective = "Solids"
				else
					objective = "Stripes"
				end

				self:SetPlayerObjective(opp, objective)
			end

			-- Because the player pocketed the ball, it'll be his turn again...
			self.NextPlayer = self.Turn

			return self:EndRound()
		elseif cObjective ~= "OpenTable" and cObjective ~= "8-Ball" then
			local wobjective = "Stripes"

			if cObjective == "Stripes" then
				wobjective = "Solids"
			end

			-- We'll check if the first hit ball was wrong or if the player pocketed the CueBall,
			-- the 8-Ball, the wrong ball or both ball types, then it's Foul!
			if self.FirstHitBall ~= cObjective or self:PocketedBall("CueBall") or self:PocketedBall(wobjective) or self:PocketedBall("8-Ball") then
				self.Foul = true

				return self:EndRound()
			elseif not self:BallTypeExist(cObjective) then
				-- Checking if the objective ball type still exists, if not, his last objective is the 8-Ball
				self:SetPlayerObjective(ply, "8-Ball")
				-- If the player pockets the 8-ball on the same stroke of the last ball type, he loses the game.
				if self:PocketedBall("8-Ball") then return self:EndBilliardGame(true) end
			end

			if not self:PocketedBall() then return self:EndRound() end
			-- Player pocketed the right ball type, it'll be his turn again...
			self.NextPlayer = self.Turn

			return self:EndRound()
		end

		-- We'll check if the player pocketed the 8-Ball, if yes, then we'll check if he also pocketed
		-- the CueBall, but instead of a foul, he'll lose the game.
		if self:PocketedBall("8-Ball") or self:PocketedBall("CueBall") then
			if self:PocketedBall("CueBall") then return self:EndBilliardGame(true) end -- The player loses the game for pocketing the cue ball
			-- but if he didn't make any mistakes, congratulations! The player won the game!

			return self:EndBilliardGame()
		elseif self.FirstHitBall ~= 8 or self:PocketedBall("Solids") or self:PocketedBall("Stripes") then
			-- but if he just hit the wrong ball or pocketed opponent balls, it's a foul
			self.Foul = true
		end

		return self:EndRound()
	elseif self.GameType == BILLIARD_GAMETYPE_9BALL then
		-- if the player pockets both CueBall and the 9-Ball, he loses the game
		if self:PocketedBall("CueBall") and self:PocketedBall("9-Ball") then return self:EndBilliardGame(true) end

		if cObjective == 9 then
			-- if the objective is the 9-Ball and it was pocketed, the player wins the game
			if self:PocketedBall("9-Ball") then
				return self:EndBilliardGame()
			elseif self:PocketedBall("CueBall") then
				return self:EndBilliardGame(true)
			end
			-- or if he couldn't pocket the 9-ball, the game just continues...

			return self:EndRound()
		end

		-- but if he just pocketed the CueBall or didn't hit right ball, it's a foul
		if self:PocketedBall("CueBall") or self.FirstHitBall ~= self.LowestNum then
			self.Foul = true
			-- Now if the player hit the right ball and pocketed the 9-Ball he just wins the game =P

			return self:EndRound()
		elseif self.FirstHitBall == self.LowestNum and self:PocketedBall("9-Ball") then
			return self:EndBilliardGame()
		elseif not self:PocketedBall() then
			-- The player didn't pocket any ball, so now it's the opponent's turn...
			return self:EndRound()
		end

		-- The player pocketed a ball, it'll be his turn again
		self.NextPlayer = self.Turn

		return self:EndRound()
	elseif self.GameType == BILLIARD_GAMETYPE_SNOOKER then
		if self:PocketedBall("CueBall") then
			self.BehindHeadString = true
			if self:BallTypeExist("Black") and not self:BallTypeExist("Yellow") and not self:BallTypeExist("Green") and not self:BallTypeExist("Brown") and not self:BallTypeExist("Blue") and not self:BallTypeExist("Pink") then return self:EndBilliardGame(true) end
		end

		if cObjective == "Red" then
			if self:PocketedBall("Color") or self.FirstHitBall ~= "Red" or self:PocketedBall("CueBall") then
				if opp then
					self:GiveScore(opp, self:GetFoulPoints())
				end

				self.Foul = true

				return self:EndRound()
			elseif not self:PocketedBall() then
				-- No Balls were pocketed...
				return self:EndRound()
			end

			self:GiveScore(ply)
			self:SetPlayerObjective(ply, "Color")
			self.NextPlayer = self.Turn

			return self:EndRound()
		elseif cObjective == "Color" then
			if self.FirstHitBall == "Red" or self:PocketedBall("Red") or self:PocketedBall("CueBall") then
				if opp then
					self:GiveScore(opp, self:GetFoulPoints())
				end

				self.Foul = true

				return self:EndRound()
			end

			self:SetPlayerObjective(ply, "Red")
			if not self:PocketedBall() then return self:EndRound() end
			self:GiveScore(ply)
			self.NextPlayer = self.Turn

			return self:EndRound()
		end

		if self:PocketedBall() then
			-- We'll check if he pocketed any ball other than his ball objective
			if self:PocketedBall(cObjective .. "-Except") or self.FirstHitBall ~= cObjective or self:PocketedBall("CueBall") then
				if opp then
					self:GiveScore(opp, self:GetFoulPoints())
				end

				self.Foul = true

				return self:EndRound()
			end

			-- He didn't commit foul, so his turn again
			self:SetPlayerObjective(ply, "Red")
			self:GiveScore(ply)
			self.NextPlayer = self.Turn

			return self:EndRound()
		elseif self.FirstHitBall ~= cObjective or self:PocketedBall("CueBall") then
			if opp then
				self:GiveScore(opp, self:GetFoulPoints())
			end

			self.Foul = true
		end

		return self:EndRound()
	elseif self.GameType == BILLIARD_GAMETYPE_ROTATION then
		if self:PocketedBall("CueBall") or self.FirstHitBall ~= self.LowestNum then
			self.Foul = true

			return self:EndRound()
		elseif not self:PocketedBall() then
			return self:EndRound()
		end

		self:GiveScore(ply)
		self.NextPlayer = self.Turn
	elseif self.GameType == BILLIARD_GAMETYPE_CARAMBOL and self.FirstHitBall and self.CRHitRed then
		self:GiveScore(ply, 1)
		self.NextPlayer = self.Turn

		return self:EndRound()
	end

	return self:EndRound()
end

-- Another very important function
function ENT:EndRound()
	local ply = self:GetTurnPlayer()
	local fouls = self:GetFoulReason(ply.Objective)
	self.Timer = CurTime() + self.RoundTime
	self:SyncRoundTime(true)
	self:ResetBallPos()

	if self.GameType == BILLIARD_GAMETYPE_9BALL or self.GameType == BILLIARD_GAMETYPE_ROTATION then
		self.LowestNum = self:GetLowestNumber()
	elseif self.GameType == BILLIARD_GAMETYPE_SNOOKER and ply.Objective == "Color" and self.Foul then
		self:SetPlayerObjective(ply, "Red")
	end

	local o, pl, ball, cObjective = 1

	for i = 1, 2 do
		pl = self:GetTurnPlayer(i)
		if not pl then continue end

		-- If all balls were pocketed we have to check wich player have more points
		if self.GameType == BILLIARD_GAMETYPE_SNOOKER and not self:BallTypeExist() then
			if not self.PlayerData[2] then return self:EndBilliardGame() end
			local tmp = 0

			for j = 1, 2 do
				if self.PlayerData[j].Score > tmp then
					tmp = self.PlayerData[j].Score
					self.Turn = j
				end
			end
			-- Game ending

			return self:EndBilliardGame()
		end

		-- We have to update the score to each player
		if self.GameType == BILLIARD_GAMETYPE_SNOOKER or self.GameType == BILLIARD_GAMETYPE_ROTATION or self.GameType == BILLIARD_GAMETYPE_CARAMBOL then
			o = 1

			if i == 1 then
				o = 2
			end

			umsg.Start("billiard_updateScore", pl)
			umsg.Short(self.PlayerData[i].Score)

			if self.PlayerData[o] then
				umsg.Short(self.PlayerData[o].Score)
			end

			umsg.End()
		end
	end

	-- If only colored balls remain, we have to allow them to be removed when pocketed
	if self.GameType == BILLIARD_GAMETYPE_SNOOKER and not self:BallTypeExist("Red") then
		for k, v in pairs(self.Balls) do
			if v.BallType == "CueBall" or not v.DontRemove then continue end
			v.DontRemove = nil
		end
	elseif self.GameType == BILLIARD_GAMETYPE_ROTATION or self.GameType == BILLIARD_GAMETYPE_CARAMBOL then
		-- If the both players have 60 points, then who made the last ball gains a bonus point and wins the game
		if self.PlayerData[2] and self.PlayerData[1].Score == 60 and self.PlayerData[2].Score == 60 then
			if self.NextPlayer then
				return self:EndBilliardGame()
			elseif self.Foul then
				return self:EndBilliardGame(true)
			end
			-- But if one player has already reached 60 or more points, he is the winner
		elseif self.PlayerData[self.Turn].Score >= 60 then
			return self:EndBilliardGame()
		end
	end

	-- If the 3 consecutive fouls rule is enabled, then the player will lose the game if he commits the third one
	if self.ThreeCFouls then
		local id = self.Turn

		if self.Foul then
			if not self.PlayerData[id].Fouls then
				self.PlayerData[id].Fouls = 0
			end

			self.PlayerData[id].Fouls = self.PlayerData[id].Fouls + 1

			-- Warn him about the 2 fouls
			if self.PlayerData[id].Fouls == 2 then
				umsg.Start("billiard_scrMsg", ply)
				umsg.String("Warning!")
				umsg.String("You already commited 2 fouls! Commiting another one\nwill result in a Loss of Game!")
				umsg.End()
			elseif self.PlayerData[id].Fouls >= 3 then
				-- 3 consecutive fouls results in a Loss of game
				return CBilliardQuitGame(self, self.PlayerData[self.Turn].ID)
			end
		else
			self.PlayerData[id].Fouls = 0
		end
	end

	-- Switching player turns
	if not self.NextPlayer and self.PlayerData[2] then
		if self.Turn == 1 then
			self.Turn = 2
		else
			self.Turn = 1
		end

		ply = self:GetTurnPlayer()
	end

	if self.GameType == BILLIARD_GAMETYPE_8BALL then
		cObjective = ply.Objective

		if cObjective ~= "8-Ball" and cObjective ~= "OpenTable" and not self:BallTypeExist(cObjective) then
			self:SetPlayerObjective(ply, "8-Ball")
		end
	elseif self.GameType == BILLIARD_GAMETYPE_9BALL or self.GameType == BILLIARD_GAMETYPE_ROTATION then
		self:SetPlayerObjective(ply, self.LowestNum)
	elseif self.GameType == BILLIARD_GAMETYPE_SNOOKER and ply.Objective ~= "Color" then
		self:SetPlayerObjective(ply, self:GetSnookerObjective())
	elseif self.GameType == BILLIARD_GAMETYPE_CARAMBOL then
		self.CRHitRed = false
	end

	ball = self:GetTableEnt() -- Getting the CueBall

	if self.GameType == BILLIARD_GAMETYPE_CARAMBOL then
		ball = self:GetTableEnt((self.Turn - 1) .. "-Ball")
	end

	if self.FPerson then
		ply:BilliardSpectate(true, self:GetTableEnt("Cue"), ball)
	end

	self:ToggleBallsMotion(false)
	self:GetTableEnt("Cue"):UpdateCue(ball)
	self.PocketedBalls = {}
	self.FirstHitBall = nil
	self.NextPlayer = nil

	if self.Foul then
		if self.BehindHeadString then
			local pf = ""

			if self.GameType == BILLIARD_GAMETYPE_SNOOKER then
				pf = "SN_"
			end

			local angPos = self:GetAttachment(self:LookupAttachment(string.format("%sBall00", pf)))
			ball:SetPos(angPos.Pos)
		end

		self:ToggleCollisions(true, self.BehindHeadString)
		self.Points_tmp = 0
		umsg.Start("billiard_mouseLock", ply)
		umsg.Bool(true)
		umsg.End()
		umsg.Start("billiard_sendSMsg", self:GetPlayersFilter())

		if self.BehindHeadString and self.GameType == BILLIARD_GAMETYPE_SNOOKER then
			umsg.String("FOUL! Cue ball inside D-Zone")
		elseif self.BehindHeadString then
			umsg.String("FOUL! Cue ball in hand behind head string")
		else
			umsg.String("FOUL! Cue ball in hand")
		end

		umsg.String(fouls)
		umsg.End()
		ball:GetPhysicsObject():EnableMotion(true)

		return
	end
end

function ENT:PocketedBall(bType)
	if self.GameType == BILLIARD_GAMETYPE_SNOOKER then
		local tmpDat = {}
		tmpDat[1], tmpDat[2], tmpDat[3], tmpDat[4] = "Red", "Yellow", "Green", "Brown"
		tmpDat[5], tmpDat[6], tmpDat[7] = "Blue", "Pink", "Black"

		if not bType or bType == "Color" or string.match(bType, "(%-Except)$") then
			local exclude = nil

			if bType and string.match(bType, "(%-Except)$") then
				exclude = string.gsub(bType, "-Except", "")
			end

			for i = 1, 7 do
				if exclude and tmpDat[i] == exclude or bType == "Color" and i == 1 then continue end
				if self.PocketedBalls[tmpDat[i]] then return true end
			end
		elseif bType and self.PocketedBalls[bType] then
			return true
		end

		return false
	end

	-- Checking if ANY ball was pocketed
	if not bType then
		if self.GameType == BILLIARD_GAMETYPE_9BALL or self.GameType == BILLIARD_GAMETYPE_ROTATION then
			if table.Count(self.PocketedBalls) >= 1 then return true end
		elseif self.GameType == BILLIARD_GAMETYPE_8BALL then
			if self.PocketedBalls["Stripes"] or self.PocketedBalls["Solids"] then return true end
		end

		return false
	end

	if self.PocketedBalls[bType] then return true end

	return false
end

function ENT:PocketBall(ball)
	local bType = ball.BallType

	-- Using the Ball's internal ID as type
	if not bType then
		bType = string.format("%d-Ball", ball.uID)
	end

	if self.GameType == BILLIARD_GAMETYPE_SNOOKER and bType ~= "CueBall" or self.GameType == BILLIARD_GAMETYPE_ROTATION and bType ~= "CueBall" then
		if not self.Points_tmp then
			self.Points_tmp = 0
		end

		if self.GameType == BILLIARD_GAMETYPE_SNOOKER and ball.DontRemove and self.PocketedBalls[bType] then
			return
		elseif self.GameType == BILLIARD_GAMETYPE_ROTATION and self.PocketedBalls[bType] then
			return
		end

		self.Points_tmp = self.Points_tmp + ball.Value
	end

	self.PocketedBalls[bType] = true
	if ball.DontRemove then return ball:GetPhysicsObject():EnableMotion(false) end
	local ID = ball.uID
	self.Balls[ID] = nil
	ball:Remove()

	-- We need to spectate other ball because this doesn't exist anymore
	if self.Training then
		self.MovingBall = 0
	end

	if self.GameType == BILLIARD_GAMETYPE_SNOOKER or self.GameType == BILLIARD_GAMETYPE_ROTATION then return end
	umsg.Start("billiard_pocketBall", self:GetPlayersFilter())
	umsg.Short(ID)
	umsg.String(self:GetTurnPlayer():UniqueID())
	umsg.End()
end

function ENT:ResetBallPos()
	local ball, angPos

	if self:PocketedBall("CueBall") then
		angPos = self:GetAttachment(self:LookupAttachment("ball00"))
		self:GetTableEnt():SetPos(angPos.Pos)
	end

	if self.GameType == BILLIARD_GAMETYPE_8BALL then
		ball = "8-Ball"
	elseif self.GameType == BILLIARD_GAMETYPE_9BALL then
		ball = "9-Ball"
	elseif self.GameType == BILLIARD_GAMETYPE_SNOOKER and self:BallTypeExist("Red") then
		-- Respotting the colored balls
		local tmpDat = {}
		tmpDat[1], tmpDat[2], tmpDat[3] = "Yellow", "Green", "Brown"
		tmpDat[4], tmpDat[5], tmpDat[6] = "Blue", "Pink", "Black"

		for i = 1, 6 do
			if not self:PocketedBall(tmpDat[i]) then continue end
			angPos = self:GetAttachment(self:LookupAttachment(string.format("SN_ball%02d", 15 + i)))
			self.Balls[15 + i]:SetPos(angPos.Pos)
		end

		return
	elseif self.GameType == BILLIARD_GAMETYPE_ROTATION then
		-- In rotation is quite different, all illegaly pocketed balls should be respotted
		if not self.Foul then return end
		local uid

		for k, v in pairs(self.PocketedBalls) do
			if not string.match(k, "(%-Ball)$") then continue end
			k = string.gsub(k, "-Ball", "")
			uid = tonumber(k)
			ball = ents.Create("billiard_ball")
			ball:Spawn()
			ball:SetSkin(uid)
			ball:SetPos(self.BallPositions[uid])
			ball:GetPhysicsObject():EnableMotion(false)
			constraint.NoCollide(ball, self:GetTableEnt("MGP"), 0, 0)
			constraint.NoCollide(ball, self:GetTableEnt("HSL"), 0, 0)
			constraint.NoCollide(ball, self:GetTableEnt("Cue"), 0, 0)
			ball.BilliardTableID = self.ID
			ball.Value = uid
			ball.uID = uid
			self.Balls[uid] = ball
		end

		return
	end

	if self:PocketedBall(ball) and self.LastGameBallPos ~= nil then
		self:GetTableEnt(ball):SetPos(self.LastGameBallPos)
	end
end

function ENT:EndBilliardGame(inv)
	if inv and self.Turn == 1 then
		self.Turn = 2
	elseif inv then
		self.Turn = 1
	end

	local winner = self:GetTurnPlayer()
	local loser = self:GetOpponentPlayer(winner)
	self:ClearEnts()
	self:ClearPlayers()
	self:ResetVars()
	hook.Call("OnBilliardGameEnd", nil, self, winner, loser)
end

-- This function toggles the pockets collisions, blocking the player from pocketing a ball while ball in hand
function ENT:ToggleCollisions(c_b, c_bh)
	local ent

	if self.GameType ~= BILLIARD_GAMETYPE_CARAMBOL then
		local angpos

		for i = 1, 6 do
			angPos = self:GetAttachment(self:LookupAttachment(string.format("hole%02d", i)))
			ent = ents.GetByIndex(self.EntsData[string.format("Pocket%02d_col", i)])
			if not ent then continue end

			if c_b then
				ent:SetPos(angPos.Pos)
				continue
			end

			ent:SetPos(angPos.Pos - Vector(0, 0, 20))
		end
	end

	ent = ents.GetByIndex(self.EntsData["HSL"])
	if c_bh then return ent:SetPos(self:GetPos()) end
	ent:SetPos(self:GetPos() - Vector(0, 0, 10))
end

-- Self explanatory xD
function ENT:ToggleBallsMotion(c_b)
	local phys

	for k, v in pairs(self.Balls) do
		phys = v:GetPhysicsObject()
		-- Fixed accidental collisions
		-- phys:SetVelocity(Vector(0, 0, 0))
		phys:EnableMotion(c_b)
	end
end

function ENT:BallTypeExist(bType)
	if not bType and self.GameType == BILLIARD_GAMETYPE_SNOOKER then
		if table.Count(self.Balls) <= 1 then return false end

		return true
	end

	for k, v in pairs(self.Balls) do
		if v.BallType ~= bType then continue end

		return true
	end

	return false
end

function ENT:GiveScore(ply, score)
	local id = ply.bpID

	if not score then
		score = self.Points_tmp
	end

	self.PlayerData[id].Score = self.PlayerData[id].Score + score
	self.Points_tmp = 0
end

function ENT:GetLowestNumber()
	local i, ID

	for k, v in pairs(self.Balls) do
		ID = v.uID
		if ID == 0 then continue end

		if not i then
			i = ID
			continue
		end

		if ID < i then
			i = ID
		end
	end

	return i
end

function ENT:GetTableEnt(nm)
	if not nm then
		nm = "CueBall"
	end

	if not nm or nm == "CueBall" then
		if not self.EntsData["CueBall"] then return false end

		return ents.GetByIndex(self.EntsData["CueBall"])
	elseif string.match(nm, "(%-Ball)$") then
		local i = string.gsub(nm, "-Ball", "")
		i = tonumber(i)

		return self.Balls[i]
	else
		return ents.GetByIndex(self.EntsData[nm])
	end

	return nil
end

function ENT:GetSnookerObjective()
	local tmpDat = {}
	tmpDat[1], tmpDat[2], tmpDat[3], tmpDat[4] = "Red", "Yellow", "Green", "Brown"
	tmpDat[5], tmpDat[6], tmpDat[7] = "Blue", "Pink", "Black"

	for i = 1, 7 do
		if self:BallTypeExist(tmpDat[i]) then return tmpDat[i] end
	end
end

function ENT:GetColorByName(name)
	name = string.lower(name)

	if name == "yellow" then
		return 255, 255, 0, 255
	elseif name == "green" then
		return 0, 160, 25, 255
	elseif name == "brown" then
		return 90, 60, 20, 255
	elseif name == "blue" then
		return 0, 80, 175, 255
	elseif name == "pink" then
		return 255, 100, 255, 255
	elseif name == "black" then
		return 0, 0, 0, 255
	end
	-- no color name recognized, so return white

	return 255, 255, 255, 255
end

function ENT:GetFoulPoints()
	if self:PocketedBall("Black") then
		return 7
	elseif self:PocketedBall("Pink") then
		return 6
	elseif self:PocketedBall("Blue") then
		return 5
	elseif self:PocketedBall("CueBall") then
		if self.FirstHitBall == "Black" then
			return 7
		elseif self.FirstHitBall == "Pink" then
			return 6
		elseif self.FirstHitBall == "Blue" then
			return 5
		end
	end

	return 4
end

function ENT:GetPlayersFilter()
	local rp = RecipientFilter()

	for i = 1, 2 do
		if not self:GetTurnPlayer(i) then continue end
		rp:AddPlayer(self:GetTurnPlayer(i))
	end

	return rp
end

function ENT:GetTurnPlayer(num)
	num = num or self.Turn
	if not self.PlayerData[num] then return end

	return player.GetByUniqueID(self.PlayerData[num]["ID"])
end

function ENT:GetOpponentPlayer(ply)
	local num = 1

	if not ply and self.Turn == 1 or ply and ply.bpID == 1 then
		num = 2
	end

	return self:GetTurnPlayer(num)
end

function ENT:GetNextBall(prev)
	if not self.Training then return end

	if not prev then
		if self.MovingBall + 1 > 15 then
			self.MovingBall = 0
		else
			self.MovingBall = self.MovingBall + 1
		end
	else
		if self.MovingBall - 1 < 0 then
			self.MovingBall = 15
		else
			self.MovingBall = self.MovingBall - 1
		end
	end

	if not self.Balls[self.MovingBall] then return self:GetNextBall(prev) end
end

function ENT:SetPlayerObjective(ply, objective)
	if not objective and self.GameType == BILLIARD_GAMETYPE_8BALL then
		objective = "OpenTable"
	elseif not objective and self.GameType == BILLIARD_GAMETYPE_9BALL or not objective and self.GameType == BILLIARD_GAMETYPE_ROTATION then
		objective = 1
	elseif not objective and self.GameType == BILLIARD_GAMETYPE_SNOOKER then
		objective = "Red"
	end

	ply.Objective = objective
	umsg.Start("billiard_setObjective", ply)
	umsg.String(objective)
	umsg.End()
end

function ENT:SyncRoundTime(c_b)
	umsg.Start("billiard_syncTime", self:GetPlayersFilter())
	umsg.Bool(c_b)

	if c_b then
		umsg.Short(self.RoundTime)
	end

	umsg.End()
end

function ENT:IsPlayerInList(p_id)
	for k, v in pairs(self.WaitingPlayers) do
		if v == p_id then return true end
	end

	return false
end

function ENT:IsMyTurn(ply)
	return self:GetTurnPlayer():UniqueID() == ply:UniqueID()
end

function ENT:ClearPlayers()
	local rp, ply = self:GetPlayersFilter()

	for i = 1, 2 do
		ply = self:GetTurnPlayer(i)
		if not ply then continue end

		if not ply:OnGround() then
			ply:SetPos(self:GetPos() + Vector(0, 0, 90))
		end

		ply:BilliardSpectate()
		ply.BilliardTableID = nil
		self:RestorePlayerWeapons(i)
	end

	umsg.Start("billiard_toggleHUD", rp)
	umsg.End()
end

function ENT:ClearEnts()
	for k, v in pairs(self.Balls) do
		v:Remove()
		self.Balls[k] = nil
	end

	for k, v in pairs(self.EntsData) do
		if not ents.GetByIndex(v) then
			continue
		elseif k == "Cue" and not self.FPerson then
			timer.Destroy("cue_shot_" .. self.EntsData["Cue"])
		end

		ents.GetByIndex(v):Remove()
		self.EntsData[k] = nil
	end
end

function ENT:SetSize(sz)
	sz = tonumber(sz or 9)

	if sz ~= 9 and sz ~= 10 and sz ~= 12 then
		sz = 9
	end

	self.Size = sz
end

function ENT:SetConfig(c_gm, c_tm, c_tr, c_sc, c_ab, c_mp, c_fp)
	if self:GetTableEnt() and self:GetTableEnt():IsValid() then return end -- Changing config while game is running is not allowed!

	-- NO SmartCue in Training, enabling this would need much more work...
	if c_tr and c_sc then
		c_sc = false
	end

	-- Training was disallowed!
	if GetConVar("billiard_no_training"):GetBool() and c_tr then
		c_tr = false
	end

	self.GameType = math.Clamp(math.floor(c_gm or BILLIARD_GAMETYPE_8BALL), 0, 4) -- NO Decimal values
	self.RoundTime = math.Clamp(math.floor(c_tm or 2), 1, 4) * 15 -- NO Decimal values either
	self.Training = c_tr or false
	self.SmartCue = c_sc or true
	self.ABMethod = math.Clamp(math.floor(c_ab or 2), 0, 2) -- I guess you already know...
	self.MProtect = c_mp or true
	self.FPerson = c_fp or true

	-- NO Snooker in 9ft tables!
	if self.GameType == BILLIARD_GAMETYPE_SNOOKER and self.Size == 9 then
		self.GameType = BILLIARD_GAMETYPE_8BALL
	end

	if self.GameType == BILLIARD_GAMETYPE_CARAMBOL then
		self:SetModel(string.format("models/billiards/cr_table_%dft.mdl", self.Size))
	else
		self:SetModel(string.format("models/billiards/table_%dft.mdl", self.Size))
	end

	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	self:ResetVars()
	self:GetPhysicsObject():SetMaterial("billiard_table")
	self:GetPhysicsObject():EnableMotion(false)

	if c_mp and not table.HasValue(svPBilliardTables, self.ID) then
		table.insert(svPBilliardTables, self.ID)
	end
end

function ENT:GetConfig()
	local output = {}
	output["GameType"] = tostring(self.GameType)
	output["RoundTime"] = tostring(self.RoundTime)
	output["Training"] = tostring(self.Training)
	output["SmartCue"] = tostring(self.SmartCue)

	if self.ABMethod == 0 then
		output["AntiBFH"] = "none"
	else
		output["AntiBFH"] = tostring(self.ABMethod)
	end

	output["MingeProtection"] = tostring(self.MProtect)
	output["CueFirstPerson"] = tostring(self.FPerson)

	return output
end

function ENT:StripPlayerWeapons(plyid)
	local ply = self:GetTurnPlayer(plyid)
	if not ply then return end

	if not self.PlayerData[plyid]["Weapons"] then
		local weaps = {}

		for k, v in pairs(ply:GetWeapons()) do
			weaps[k] = {}
			weaps[k]["class"] = v:GetClass()
			weaps[k]["C1"] = v:Clip1()
			weaps[k]["C2"] = v:Clip2()
			weaps[k]["T1"] = ply:GetAmmoCount(v:GetPrimaryAmmoType())
			weaps[k]["T2"] = ply:GetAmmoCount(v:GetSecondaryAmmoType())
		end

		self.PlayerData[plyid]["Weapons"] = weaps
	end

	ply:StripWeapons()
end

function ENT:RestorePlayerWeapons(plyid)
	local ply, weap = self:GetTurnPlayer(plyid)
	if not self.PlayerData[plyid] then return end

	for k, v in pairs(self.PlayerData[plyid]["Weapons"]) do
		ply:Give(v.class)
		weap = ply:GetWeapon(v.class)
		weap:SetClip1(v.C1)
		weap:SetClip2(v.C2)
		ply:SetAmmo(v.T1, weap:GetPrimaryAmmoType())
		ply:SetAmmo(v.T2, weap:GetSecondaryAmmoType())
	end
end

function ENT:ResetVars(kplys)
	-- In case the kplys is true we'll reset everything but player data;
	if not kplys then
		self.PlayerData = {}
	end

	self.WaitingPlayers = {}
	self.PocketedBalls = {}
	self.BallPositions = {}
	self.EntsData = {}
	self.Balls = {}
	self.BehindHeadString = true
	self.WaitBallsToStop = false
	self.LastGameBallPos = nil
	self.OpenBreakShot = true
	self.BallsHitRail = 0
	self.FirstHitBall = nil
	self.ThreeCFouls = false
	self.Points_tmp = nil
	self.NextPlayer = nil
	self.LowestNum = nil
	self.CRHitRed = nil
	self.Timer = nil
	self.Foul = false
	self.Turn = 1
end

function ENT:RackBalls()
	local tmpDat = {}
	tmpDat.c, tmpDat.p = 15, "" -- Ball count, Ball attachment prefix

	if self.GameType == BILLIARD_GAMETYPE_9BALL then
		tmpDat.c, tmpDat.p = 9, "9B_"
	elseif self.GameType == BILLIARD_GAMETYPE_SNOOKER then
		self.OpenBreakShot = false -- There is no Opening Break Shot in snooker
		tmpDat.c, tmpDat.p = 21, "SN_"
		tmpDat.t = {}
		tmpDat.t[1], tmpDat.t[2], tmpDat.t[3] = "Yellow", "Green", "Brown"
		tmpDat.t[4], tmpDat.t[5], tmpDat.t[6] = "Blue", "Pink", "Black"
	end

	for i = 1, tmpDat.c do
		-- Attachments are handy, look how easy is to setup the balls in their positions...
		angPos = self:GetAttachment(self:LookupAttachment(string.format("%sball%02d", tmpDat.p, i)))

		-- if any balls were pocketed in a invalid break shot we'll have to re-create it
		if not self.Balls[i] then
			ball = ents.Create("billiard_ball")
			ball.BilliardTableID = self.ID
			ball:Spawn()
			self.Balls[i] = ball
			ball.uID = i

			if self.GameType == BILLIARD_GAMETYPE_8BALL then
				if i >= 1 and i <= 7 then
					ball.BallType = "Solids"
				elseif i >= 9 then
					ball.BallType = "Stripes"
				end

				ball:SetSkin(i)
			elseif self.GameType == BILLIARD_GAMETYPE_SNOOKER then
				-- 15 Red Balls =D
				if i <= 15 then
					ball.BallType = "Red"
					ball.Value = 1
					ball:SetSkin(0)
					ball:SetColor(Color(255, 0, 0, 255))
				end
			else
				ball:SetSkin(i)
			end
		end

		ball = self.Balls[i]
		ball:SetPos(angPos.Pos)
		ball:SetAngles(Angle(math.Rand(0, 360), math.Rand(0, 360), math.Rand(0, 360)))
		ball.HitRail = nil
		constraint.NoCollide(ball, self:GetTableEnt("MGP"), 0, 0)
		constraint.NoCollide(ball, self:GetTableEnt("HSL"), 0, 0)
	end

	for i = 1, 2 do
		if not self.PlayerData[i] then continue end
		self.PlayerData[i].Score = 0
	end

	umsg.Start("billiard_resetInfos", self:GetPlayersFilter())
	umsg.End()
	self:ToggleBallsMotion(false)
	self.LastGameBallPos = nil
	self.BallsHitRail = 0
end

-- Let's colect all the reasons of the foul (if any)...
function ENT:GetFoulReason(cObjective)
	if not self.Foul then return end -- if there isn't any foul then just return

	if self:PocketedBall("CueBall") then
		return "Scratch!"
	elseif not self.FirstHitBall then
		return "No balls were hit!"
	elseif self.BallsHitRail < 4 and self.GameType ~= BILLIARD_GAMETYPE_SNOOKER then
		return "At least four balls must hit the rail"
	elseif self.FirstHitBall ~= cObjective and self.GameType ~= BILLIARD_GAMETYPE_SNOOKER then
		return "First hitted ball was wrong"
	end

	if self.GameType == BILLIARD_GAMETYPE_8BALL then
		if self:PocketedBall("8-Ball") then
			return "Pocketed the 8-Ball!"
		elseif cObjective == "OpenTable" and self:PocketedBall("Solids") and self:PocketedBall("Stripes") then
			return "Pocketed both Stripe and Solid balls"
		end

		if cObjective ~= "OpenTable" then
			local wObjective = "Stripes"

			if cObjective == "Stripes" then
				wObjective = "Solids"
			end

			if self:PocketedBall(wObjective) or cObjective == "8-Ball" and self:PocketedBall() then return "Pocketed wrong ball" end
		end
	elseif self.GameType == BILLIARD_GAMETYPE_SNOOKER then
		if cObjective == "Color" and self:PocketedBall("Red") or cObjective ~= "Color" and self:PocketedBall(cObjective .. "-Except") then
			return "Pocketed wrong ball"
		elseif cObjective == "Color" and self.FirstHitBall == "Red" or cObjective == "Red" and self.FirstHitBall ~= "Red" then
			return "First hitted ball was wrong"
		end
	end

	return "unknown"
end