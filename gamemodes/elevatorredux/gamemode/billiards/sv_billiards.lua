------------------------------------------------------------
-- MBilliards by Athos Arantes Pereira
-- Contact: athosarantes@hotmail.com
------------------------------------------------------------
physenv.AddSurfaceData([["billiard_ball"
{
	"scraperough"	"DoorSound.Null"
	"scrapesmooth"	"DoorSound.Null"
	"impacthard"	"DoorSound.Null"
	"impactsoft"	"DoorSound.Null"

	"audioreflectivity"		"0.66"
	"audiohardnessfactor"	"0.0"
	"audioroughnessfactor"	"0.0"

	"elasticity"	"1000"
	"friction"		"0.4"
	"density"		"10000"
}

"billiard_table"
{
	"scraperough"	"DoorSound.Null"
	"scrapesmooth"	"DoorSound.Null"
	"impacthard"	"DoorSound.Null"
	"impactsoft"	"DoorSound.Null"

	"audioreflectivity"		"0.66"
	"audiohardnessfactor"	"0.0"
	"audioroughnessfactor"	"0.0"

	"scrapeRoughThreshold"	"1.0"
	"impactHardThreshold"	"1.0"
	"friction"		"0.4"
}]])

CreateConVar("billiard_admins_only", 1, {FCVAR_NOTIFY}, "Should only admins be able to create new billiard tables?")

CreateConVar("billiard_max_tables", 4, {FCVAR_NOTIFY}, "Max billiard tables, global value")

CreateConVar("billiard_req_time", 20, {FCVAR_NOTIFY}, "The Request time in seconds, auto refused if no answer is given")

CreateConVar("billiard_no_training", 1, {FCVAR_NOTIFY}, "Should Training mode be disabled?")

CreateConVar("billiard_walk_across_a_table", 1, {FCVAR_ARCHIVE}, "Allows the player to walk around the table during the game.", 0, 1)

BILLIARD_GAMETYPE_8BALL = 0
BILLIARD_GAMETYPE_9BALL = 1
BILLIARD_GAMETYPE_SNOOKER = 2
BILLIARD_GAMETYPE_ROTATION = 3
BILLIARD_GAMETYPE_CARAMBOL = 4
local mEntity = FindMetaTable("Entity")
svPBilliardTables = {}
BilliardTables = 0

-- This is also used in players
function mEntity:GetBilliardTable()
  if not self.BilliardTableID or not ents.GetByIndex(self.BilliardTableID) then return end

  return ents.GetByIndex(self.BilliardTableID)
end

function mEntity:BilliardSpectate(c_b, ent1, ent2)
  if not self:IsPlayer() then return end

  if not c_b or not ent1 then
    self:SetMoveType(MOVETYPE_WALK)
    self.BSpectating = nil
    umsg.Start("billiard_spectate", self)
    umsg.End()

    return
  end

  -- Generating a "Spectating ID"
  local sID = string.format("spec_%s-%s", ent1:EntIndex(), ent2:EntIndex() or "nil")
  if self.BSpectating == sID then return end
  self:SetMoveType(MOVETYPE_NONE)
  self.BSpectating = sID
  umsg.Start("billiard_spectate", self)
  umsg.Bool(true)
  umsg.Short(ent1:EntIndex())

  if ent2 then
    umsg.Short(ent2:EntIndex())
  end

  umsg.End()

  if ent2 and ent2:IsValid() then
    self:GetBilliardTable():GetTableEnt("Cue"):UpdateCue(ent2)
  end
end

function CBilliardMingeProtection(ply, ent)
  if table.Count(svPBilliardTables) >= 1 then
    if type(ent) == "table" then
      ent = ent.Entity
    end

    for k, v in pairs(svPBilliardTables) do
      if ent:GetClass() == "billiard_table" and ent.ID == v then
        return false
      elseif ent.BilliardTableID and ent.BilliardTableID == v then
        return false
      end
    end
  end
end

hook.Add("GravGunPickupAllowed", "CBilliardGravGunPickup", CBilliardMingeProtection)
hook.Add("CanPlayerUnfreeze", "CBilliardCanPlayerUnfreeze", CBilliardMingeProtection)
hook.Add("PhysgunPickup", "CBilliardPhysgunPickup", CBilliardMingeProtection)
hook.Add("GravGunPunt", "CBilliardGravGunPunt", CBilliardMingeProtection)
hook.Add("CanTool", "CBilliardCanTool", CBilliardMingeProtection)

function CBilliardQuitGame(ptable, plyid)
  if ptable.PlayerData[2] then
    for i = 1, 2 do
      if ptable.PlayerData[i]["ID"] ~= plyid then continue end
      ptable.Turn = 1

      if i == 1 then
        ptable.Turn = 2
      end

      return ptable:EndBilliardGame()
    end
  end

  ptable:ClearEnts()
  ptable:ClearPlayers()
  ptable:ResetVars()
end

function BilliardPlayerDisconnected(ent)
  if type(ent) == "Player" and ent.BilliardTableID and ent.bpUniqueID then
    CBilliardQuitGame(ents.GetByIndex(ent.BilliardTableID), ent.bpUniqueID)
  end
end

hook.Add("EntityRemoved", "CBilliardEntityRemoved", function(ent)
  BilliardPlayerDisconnected(ent)
end)

hook.Add("PlayerDisconnected", "CBilliardPlayerDisconnected", function(ply)
  BilliardPlayerDisconnected(ply)
end)

hook.Add("PlayerInitialSpawn", "CBilliardPlayerInitialSpawn", function(ply)
  ply.bpUniqueID = ply:UniqueID()
end)

hook.Add("PlayerLoadout", "CBilliardPlayerLoadout", function(ply)
  local ptable = ply:GetBilliardTable()
  if not ptable then return end
  ptable:StripPlayerWeapons(ply.bpID)

  return true
end)

------------------------------------------------------------
-- CUSTOM BILLIARD HOOKS
------------------------------------------------------------
hook.Add("CanPlayerEnterBilliard", "plyEnterBilliard", function(ptable, ply) return true end)

hook.Add("OnBilliardGameStart", "StartingGameBilliard", function(ptable, ply1, ply2)
  local gtype = ptable.GameType

  if gtype == BILLIARD_GAMETYPE_8BALL then
    gtype = "8-Ball"
  elseif gtype == BILLIARD_GAMETYPE_9BALL then
    gtype = "9-Ball"
  elseif gtype == BILLIARD_GAMETYPE_SNOOKER then
    gtype = "Snooker"
  elseif gtype == BILLIARD_GAMETYPE_ROTATION then
    gtype = "Rotation"
  end

  Msg("New Billiard Game started! Game type is " .. gtype .. "\n")
  Msg("Name1: " .. ply1:GetName() .. "\n")

  if ply2 then
    Msg("Name2: " .. ply2:GetName() .. "\n")
  end
end)

hook.Add("OnBilliardGameEnd", "EndingGameBilliard", function(ptable, winner, loser)
  umsg.Start("billiard_scrMsg", winner)
  umsg.String("You Win!")
  umsg.String("Congratulations!")
  umsg.End()

  if loser then
    umsg.Start("billiard_scrMsg", loser)
    umsg.String("You Lost!")
    umsg.String("")
    umsg.End()
  end
end)

------------------------------------------------------------
local ptable, b_ball, b_cue, b_pcmd, b_mx, b_my, b_dir, b_pos, b_ppos, b_bool, b_pset, b_pms

hook.Add("Move", "CBilliardMove", function(ply, movedata)
  ptable = ply:GetBilliardTable()

  if ptable then
    -- Out of playing area!
    b_ppos, b_pos, b_bool = ply:GetPos(), ptable:GetPos()

    if b_ppos[1] > b_pos[1] + 200 then
      b_bool = true
    elseif b_ppos[2] > b_pos[2] + 200 then
      b_bool = true
    elseif b_ppos[1] < (b_pos[1] - 200) then
      b_bool = true
    elseif b_ppos[2] < (b_pos[2] - 200) then
      b_bool = true
    end

    if b_bool and not ply.WarnAreaSent then
      ply.WarnAreaSent = true
      umsg.Start("billiard_scrMsg", ply)
      umsg.String("Warning!")
      umsg.String("You have 5 seconds to get back to play area\nor you will lose the game!")
      umsg.End()

      timer.Create("ply_lose_" .. ply:UniqueID(), 5, 1, function()
        CBilliardQuitGame(ptable, ply:UniqueID())
      end)
    elseif not b_bool and ply.WarnAreaSent then
      ply.WarnAreaSent = nil
      timer.Destroy("ply_lose_" .. ply:UniqueID())
      umsg.Start("billiard_scrMsg", ply)
      umsg.End()
    end

    if ptable:IsMyTurn(ply) and not ptable.WaitBallsToStop and ptable:GetTableEnt() then
      b_cue = ptable:GetTableEnt("Cue")
      b_ball = ptable:GetTableEnt()
      b_pcmd = ply:GetCurrentCommand()
      b_mx, b_my = b_pcmd:GetMouseX(), b_pcmd:GetMouseY()

      if ptable.FPerson then
        b_bool = true
        local n = ply:GetInfo("billiard_cl_mouse_sensitivity")

        if n then
          n = tonumber(n) or 2
        end

        b_pms = math.Clamp(n, 0.5, 10) / 100

        if ptable.GameType == BILLIARD_GAMETYPE_SNOOKER then
          if not ptable.BehindHeadString then
            b_bool = false
          end
        else
          if not ptable.Foul and not ptable.OpenBreakShot then
            b_bool = false
          end
        end

        if ptable.Training and ptable.Balls[ptable.MovingBall] then
          b_ball = ptable.Balls[ptable.MovingBall]
          ply:BilliardSpectate(true, ptable:GetTableEnt("Cue"), b_ball)
        end

        if ply:KeyDown(IN_SPEED) and b_bool or ply:KeyDown(IN_SPEED) and ptable.Training then
          b_cue:GetPhysicsObject():EnableMotion(false)
          b_cue.CanShoot = false

          if not b_pset then
            b_cue:SetColor(Color(0, 0, 0, 0))
            b_cue:SetPos(ptable:GetPos() + Vector(0, 0, 50))
          end

          b_mx, b_my = b_mx * -0.7, b_my * 0.7 -- To left/right, forward/backward respectively
          b_dir = b_cue:GetForward():GetNormal() * b_my
          b_dir:Add(b_cue:GetForward():GetNormal():Angle():Right():GetNormal() * b_mx)
          b_ball:GetPhysicsObject():EnableMotion(true)
          b_dir = Vector(math.Clamp(b_dir[1], -120, 120), math.Clamp(b_dir[2], -120, 120), 0)
          b_ball:GetPhysicsObject():SetVelocity(b_dir)
          b_pset = true
        else
          b_ball:GetPhysicsObject():EnableMotion(false)
          b_cue:GetPhysicsObject():EnableMotion(false)
          b_cue.CanShoot = true

          if ply:KeyDown(IN_ATTACK2) then
            b_cue:GetPhysicsObject():EnableMotion(true)
            b_my = math.Clamp(b_my * 0.7, -400, 400)
            b_dir = b_cue:GetForward():GetNormal()
            b_pos = b_ball:GetPos()
            b_cue:GetPhysicsObject():SetVelocity(b_dir * b_my)
            b_bool = true

            for k, v in pairs(ents.FindInSphere(b_pos, 20)) do
              if v:GetClass() ~= "billiard_cue" then continue end
              b_bool = false
              break
            end

            if b_bool then
              b_pos:Add(b_dir * 20)
              b_cue:SetPos(b_pos)
              b_cue:SetVelocity(Vector(0, 0, 0))
            end

            b_pset = true
          else
            b_mx, b_my = b_mx * -b_pms, b_my * b_pms
            local n = ply:GetInfo("billiard_cl_cue_invmouse_h")

            if tobool(n) then
              b_mx = -b_mx
            end

            n = ply:GetInfo("billiard_cl_cue_invmouse_v")

            if n then
              b_my = -b_my
            end

            b_dir = b_cue:GetAngles()
            b_cue:SetAngles(Angle(math.Clamp(b_dir.p - b_my, -85, b_cue.ZAng), b_dir.y + b_mx, 0))

            if b_pset then
              b_pset = nil
              b_cue:SetPos(b_ball:GetPos())
              b_cue:SetColor(Color(255, 255, 255, 255))
            end
            --b_cue:GetPhysicsObject():EnableMotion(false)
          end
        end
      else
        if b_cue.CanShoot and ptable.Foul or ptable.OpenBreakShot and b_cue.CanShoot or ptable.BehindHeadString and b_cue.CanShoot then
          if ply:KeyDown(IN_SPEED) then
            local ang = ply:GetAimVector()
            local b_dir = ang:GetNormal() * b_my * -1
            b_cue:SetColor(Color(0, 0, 0, 0))
            b_cue:SetPos(ptable:GetPos() + Vector(0, 0, 50))
            b_dir:Add(ang:GetNormal():Angle():Right():GetNormal() * b_mx)
            b_ball:GetPhysicsObject():EnableMotion(true)
            b_ball:GetPhysicsObject():SetVelocity(Vector(math.Clamp(b_dir[1], -120, 120), math.Clamp(b_dir[2], -120, 120), 0))
          else
            b_ball:GetPhysicsObject():EnableMotion(false)
            b_ball:GetPhysicsObject():SetVelocity(Vector(0, 0, 0))
            b_cue:SetColor(Color(255, 255, 255, 255))
            b_cue:SetPos(b_ball:GetPos())
          end
        end
      end

      if ptable.Training then
        if ply:KeyPressed(IN_FORWARD) then
          ptable:GetNextBall()
        elseif ply:KeyPressed(IN_BACK) then
          ptable:GetNextBall(true)
        end
      end
    end
  end
end)

------------------------------------------------------------
-- CONSOLE COMMANDS
------------------------------------------------------------
concommand.Add("billiard_debug_info", function(ply, cmd, args)
  local ptable = ply:GetBilliardTable()
  if not ptable or not ply:IsAdmin() then return end
  Msg("\n=================== MBILLIARDS DEBUG ===================\n")
  Msg("---- CONFIG -------------------------------\n")
  PrintTable(ptable:GetConfig())
  Msg("---- INFO ------------------------------\n")
  Msg("ID: " .. ptable.ID .. "\n")
  Msg("Foul: " .. tostring(ptable.Foul) .. "\n")
  Msg("Turn: " .. ptable.Turn .. "\n")
  Msg("NextPlayer: " .. (ptable.NextPlayer or "none") .. "\n")
  Msg("RoundTime: " .. ptable.RoundTime .. "\n")
  Msg("OpenTable: " .. tostring(ptable.OpenBreakShot) .. "\n")
  Msg("WaitingBalls: " .. tostring(ptable.WaitBallsToStop) .. "\n")
  Msg("LastGameBallPos: " .. tostring(ptable.LastGameBallPos) .. "\n")

  for i = 1, 2 do
    local ply = ptable:GetTurnPlayer(i)
    if not ply or not ply:IsValid() then continue end
    Msg(string.format("Player: %02d Objective: %s\n", i, ply.Objective))
  end

  Msg("---- INTERNAL ENTITES -------------------------------\n")
  PrintTable(ptable.EntsData)
  Msg("---- PLAYERS & WEAPONS -------------------------------\n")
  PrintTable(ptable.PlayerData)
  Msg("---- BALLS -------------------------------\n")
  PrintTable(ptable.Balls)
  Msg("---- WAITING PLAYERS -------------------------------\n")
  PrintTable(ptable.WaitingPlayers)
  Msg("---- POCKETED BALLS -------------------------------\n")
  PrintTable(ptable.PocketedBalls)
  Msg("\n================ END OF DEBUG ===============\n")
end)

concommand.Add("billiard_strike", function(ply, cmd, args)
  local ptable = ply:GetBilliardTable()
  if not ptable or ptable.FPerson or not ptable:IsMyTurn(ply) or ptable.WaitBallsToStop or not ptable:GetTableEnt("Cue").CanShoot then return end
  local cue = ptable:GetTableEnt("Cue")
  local speed = tonumber(args[1]) or 150
  speed = math.Clamp(speed, 1, 400)
  cue.ShotSpeed = speed
  cue.CanShoot = false
  cue:GetPhysicsObject():SetVelocity(cue:GetForward():GetNormal() * 30)

  timer.Create("cue_shot_" .. cue:EntIndex(), 0.25, 1, function()
    cue:GetPhysicsObject():SetVelocity(cue:GetForward():GetNormal() * speed * -1)
  end)
end)

concommand.Add("billiard_create", function(ply, cmd, args)
  if BilliardTables >= GetConVarNumber("billiard_max_tables") then return end
  if GetConVar("billiard_admins_only"):GetBool() and not ply:IsAdmin() then return end
  if not args[1] or not args[2] or not args[3] then return end
  local ent = ents.Create("billiard_table")
  local skin = math.Clamp(tonumber(args[5]) or 0, 0, 2)
  ent:SetSize(args[4])
  ent:SetPos(Vector(args[1], args[2], args[3] + 0.2))
  ent:Spawn()
  ent:GetPhysicsObject():EnableMotion(false)
  ent:SetConfig(tonumber(args[6]), tonumber(args[7]), tobool(args[8]), tobool(args[9]), tonumber(args[10]), tobool(args[11]), tobool(args[12]))
  ent:Activate()

  if ent.GameType == BILLIARD_GAMETYPE_SNOOKER then
    skin = skin + 3
  end

  ent:SetSkin(skin)
  BilliardTables = BilliardTables + 1
  undo.Create("billiard_entity")
  undo.AddEntity(ent)
  undo.SetPlayer(ply)
  undo.SetCustomUndoText("Undone Billiard Table")
  undo.Finish()
end)

print("loaded")

concommand.Add("make_table", function(ply, cmd, args)
  if BilliardTables >= GetConVarNumber("billiard_max_tables") then return end
  if GetConVar("billiard_admins_only"):GetBool() and not ply:IsAdmin() then return end
  umsg.Start("billiard_createMenu", ply)
  umsg.Vector(ply:GetEyeTrace().HitPos)
  umsg.End()
end)

concommand.Add("billiard_config", function(ply, cmd, args)
  local ptable = ents.GetByIndex(args[1])
  if not ptable or ptable:GetTableEnt():IsValid() or GetConVar("billiard_admins_only"):GetBool() and not ply:IsAdmin() then return end
  ptable:SetConfig(tonumber(args[3]), tonumber(args[4]), tobool(args[5]), tobool(args[6]), tonumber(args[7]), tobool(args[8]), tobool(args[9]))
  local skin = math.Clamp(tonumber(args[2]) or 0, 0, 2)

  if ptable.GameType == BILLIARD_GAMETYPE_SNOOKER then
    skin = skin + 3
  end

  ptable:SetSkin(skin)
  if tobool(args[8]) then return end

  for k, v in pairs(svPBilliardTables) do
    if v ~= tonumber(args[1]) then continue end
    svPBilliardTables[k] = nil
  end
end)

concommand.Add("billiard_acc_ref", function(ply, cmd, args)
  local ptable = ply:GetBilliardTable()
  if not ptable or not ptable:IsPlayerInList(args[2]) then return end
  local reqply = player.GetByUniqueID(args[2])

  if tobool(args[1]) then
    for k, v in pairs(ptable.WaitingPlayers) do
      timer.Destroy("del_wait_ply_" .. v)
    end

    ptable.WaitingPlayers = {}
    reqply.BilliardTableID = ptable.ID
    ptable.PlayerData[2] = {}
    ptable.PlayerData[2]["ID"] = args[2]
    ptable.PlayerData[2]["Score"] = 0
    umsg.Start("billiard_scrMsg", reqply)
    umsg.String("Accepted")
    umsg.String("You are now in the game!")
    umsg.End()
    umsg.Start("billiard_updateInfo", reqply)
    umsg.String(ply:GetName())
    umsg.End()
    umsg.Start("billiard_updateInfo", ply)
    umsg.String(reqply:GetName())
    umsg.End()
    ptable:ClearEnts() -- We need to remove all balls, the cue, etc.
    ptable:ResetVars(true) -- We need to reset the game but also we need to keep the player data
    ptable:StartBilliardGame() -- Then we start the game :D

    return
  else
    for k, v in pairs(ptable.WaitingPlayers) do
      if v == args[2] then
        timer.Destroy("del_wait_ply_" .. v)
        ptable.WaitingPlayers[k] = nil
        break
      end
    end

    umsg.Start("billiard_scrMsg", reqply)
    umsg.String("Refused")
    umsg.String("Your request was refused!")
    umsg.End()
  end
end)

concommand.Add("billiard_quit", function(ply, cmd, args)
  CBilliardQuitGame(ply:GetBilliardTable(), ply:UniqueID())
end)