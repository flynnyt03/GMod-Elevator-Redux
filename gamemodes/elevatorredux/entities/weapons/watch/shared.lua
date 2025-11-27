if SERVER then
    AddCSLuaFile("shared.lua")
end

SWEP.Spawnable = true
SWEP.AdminSpawnable = true

SWEP.PrintName = "Watch"
SWEP.Slot = 0
SWEP.SlotPos = 0

SWEP.ViewModel = Model("models/weapons/v_watch.mdl")
SWEP.WorldModel = ""
SWEP.HoldType = "normal"

SWEP.Primary = {
    ClipSize = -1,
    Delay = 1,
    DefaultClip = -1,
    Automatic = false,
    Ammo = "none"
}

SWEP.Secondary = {
    ClipSize = -1,
    DefaultClip = -1,
    Automatic = false,
    Ammo = "none"
}

SWEP.Delay = {
    View = 1,
    Cough = function()
        if not COOLDOWN_CVAR:GetBool() then return 2 end
        return math.random(45, 60)
    end,
    Slap = function()
        if not COOLDOWN_CVAR:GetBool() then return 2 end
        return math.random(120, 540)
    end,
    Drink = 25 / 30 * 2
}

SWEP.Sounds = {
    Miss = Sound("Weapon_Knife.Slash"),
    HitWorld = Sound("Default.ImpactSoft")
}

SWEP.CheapAnims = {
    Watch = {
        {"ValveBiped.Bip01_Head1", Angle(0, -25, 0)},
        {"ValveBiped.Bip01_R_UpperArm", Angle(15, -40, -60)},
        {"ValveBiped.Bip01_R_Forearm", Angle(0, -80, -45)}
    }
}

SWEP.Mins = Vector(-8, -8, -8)
SWEP.Maxs = Vector(8, 8, 8)

function SWEP:Initialize()
    self.iNextCough = nil
    self:SetWeaponHoldType(self.HoldType)
    self:DrawShadow(false)

    if SERVER then
        self:SetNextSecondaryFire(CurTime() + self.Delay:Cough())
    end
end

function SWEP:SetupDataTables()
    self:DTVar("Bool", 0, "Viewing")
    self:DTVar("Bool", 1, "Spinning")
end

local spin = {hour = math.Rand(0, 1), min = math.Rand(0, 1)}

function SWEP:Think()
    if not IsValid(self.Owner) then return end

    local vm = self.Owner:GetViewModel()
    if not IsValid(vm) then return end

    if SERVER then
        if self.iNextCough and CurTime() > self.iNextCough then
            self.iNextCough = nil
            self:Cough()
        end

        if not self:IsDrinking() and vm:GetBodygroup(0) == 1 then
            vm:SetBodygroup(0, 0)
        end

        if not self:IsInUse() and self:GetSequence() ~= 0 then
            self:SendWeaponAnim(ACT_VM_IDLE)
        end
    else
        if self:IsSpinning() then
            spin.hour = spin.hour + 0.003
            spin.min = spin.min + 0.008
            vm:SetPoseParameter("hhand_rot", spin.hour)
            vm:SetPoseParameter("mhand_rot", spin.min)
        else
            local time = os.date("*t")
            local mrot = time.min / 60
            local hrot = (time.hour / 12) + ((1 / 12) * mrot)
            vm:SetPoseParameter("hhand_rot", hrot)
            vm:SetPoseParameter("mhand_rot", mrot)
        end
    end
end

function SWEP:IsInUse()
    return self:IsViewingWatch(true) or self:IsCoughing() or self:IsSlapping() or self:IsDrinking()
end

SWEP.ActionSlots = {}
SLOT_COUGH = 1
SLOT_SLAP = 2
SLOT_DRINK = 3

function SWEP:SetNextAction(slot, time)
    self.ActionSlots[slot] = self.ActionSlots[slot] or {}
    self.ActionSlots[slot].Last = CurTime()
    self.ActionSlots[slot].Next = time
end

function SWEP:GetNextAction(slot)
    return self.ActionSlots[slot] and self.ActionSlots[slot].Next or -1
end

function SWEP:GetLastAction(slot)
    return self.ActionSlots[slot] and self.ActionSlots[slot].Last or -1
end

function SWEP:IsViewingWatch(bCheckAnim)
    if bCheckAnim then
        return self.dt.Viewing or (self:GetNextPrimaryFire() > CurTime())
    else
        return self.dt.Viewing
    end
end

function SWEP:SetViewing(bView)
    self.dt.Viewing = bView
end

function SWEP:IsSpinning()
    return self.dt.Spinning
end

function SWEP:SetSpinning(bSpin)
    self.dt.Spinning = bSpin
end

function SWEP:IsCoughing()
    return self:GetLastAction(SLOT_COUGH) + 1 > CurTime()
end

function SWEP:Cough()
    if self:IsViewingWatch() then self:SetViewing(false) end
    self:SendWeaponAnim(ACT_VM_RECOIL1)
    self.Owner:EmitSound(GAMEMODE:RandomDefinedSound(SOUNDS_COUGH), 100, 100)
    self:SetNextAction(SLOT_COUGH, CurTime() + self.Delay:Cough())
end

function SWEP:IsDrinking()
    return self:GetLastAction(SLOT_DRINK) + 2 > CurTime()
end

function SWEP:Drink()
    if not SERVER then return end
    if self:IsViewingWatch() then self:SetViewing(false) end

    local vm = self.Owner:GetViewModel()
    vm:SetBodygroup(0, 1)
    self:SendWeaponAnim(ACT_VM_FIZZLE)

    timer.Simple(2 / 3, function()
        if not IsValid(self) then return end
        self.Owner:EmitSound(GAMEMODE:RandomDefinedSound(SOUNDS_DRINK), 60, 100)
    end)

    self:SetNextAction(SLOT_DRINK, CurTime() + self.Delay.Drink)
end

function SWEP:IsSlapping()
    return self:GetLastAction(SLOT_SLAP) + 1 > CurTime()
end

function SWEP:Slap()
    if not SERVER then return end
    if self:IsViewingWatch() then self:SetViewing(false) end

    -- Set next action correctly
    self:SetNextAction(SLOT_SLAP, CurTime() + self.Delay:Slap())

    -- Trace for hit detection
    local tr = util.TraceHull({
        start = self.Owner:GetShootPos(),
        endpos = self.Owner:GetShootPos() + (self.Owner:GetAimVector() * 40),
        mins = self.Mins,
        maxs = self.Maxs,
        filter = self.Owner
    })

    local EmitSound = self.Sounds.Miss
    self.Owner:AnimRestartGesture(GESTURE_SLOT_ATTACK_AND_RELOAD, ACT_HL2MP_GESTURE_RANGE_ATTACK_MELEE)

    if IsFirstTimePredicted() then
        -- Play a valid melee animation
        self:SendWeaponAnim(ACT_VM_HITCENTER)
    end

    if tr.Hit then
        local ent = tr.Entity
        if IsValid(ent) and (ent:IsPlayer() or ent:IsNPC() or ent:GetClass() == "prop_physics") then
            if ent:IsPlayer() or ent:IsNPC() then
                EmitSound = GAMEMODE:RandomDefinedSound(SOUNDS_SLAP)
            else
                EmitSound = self.Sounds.HitWorld
            end

            local dmginfo = DamageInfo()
            dmginfo:SetDamage(0)
            dmginfo:SetDamagePosition(tr.HitPos)
            dmginfo:SetDamageType(DMG_CLUB)
            dmginfo:SetInflictor(self.Owner)
            dmginfo:SetAttacker(self.Owner)

            local vec = (tr.HitPos - tr.StartPos):GetNormal()
            if ent:IsPlayer() then
                ent:SetVelocity(vec * SLAPFORCE_CVAR:GetFloat())
            else
                dmginfo:SetDamageForce(vec * 5000)
            end

            ent:TakeDamageInfo(dmginfo)
        else
            EmitSound = self.Sounds.HitWorld
        end
    end

    self.Owner:EmitSound(EmitSound, 65, 100)
end
function SWEP:PrimaryAttack()
    if not SERVER then return end
    if self:IsCoughing() or self:IsDrinking() or self:IsSlapping() then return end
    if IsValid(self.Owner.PickupItem) then
        self.Owner.PickupItem = nil
        return
    end

    if self:IsViewingWatch() then
        self:SendWeaponAnim(ACT_VM_SECONDARYATTACK)
        self:SetViewing(false)

        for _, bone in pairs(self.CheapAnims.Watch) do
            self.Owner:ManipulateBoneAngles(self.Owner:LookupBone(bone[1]) or 0, Angle(0, 0, 0))
        end
    else
        self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
        self:SetViewing(true)

        for _, bone in pairs(self.CheapAnims.Watch) do
            self.Owner:ManipulateBoneAngles(self.Owner:LookupBone(bone[1]) or 0, bone[2])
        end
    end

    self:SetNextPrimaryFire(CurTime() + self.Delay.View)
end

function SWEP:SecondaryAttack()
    if not SERVER then return end
    if self:GetNextAction(SLOT_COUGH) > CurTime() then return end
    if self:IsSlapping() or self:IsDrinking() then return end
    if self:IsViewingWatch() then
        self:PrimaryAttack()
        return
    end

    self:Cough()
end

function SWEP:Reload()
    if not SERVER then return end
    if self:GetNextAction(SLOT_SLAP) > CurTime() then return end
    if self:IsCoughing() or self:IsDrinking() then return end
    if self:IsViewingWatch() then
        self:PrimaryAttack()
        return
    end

    self:Slap()
end

if CLIENT then
    local IsSinglePlayer = game.SinglePlayer
    local angfix = Angle(0, 0, -90)
    local lerpSpeed = 10 -- higher = faster interpolation

    function SWEP:DrawWorldModel() end

    function SWEP:GetViewModelAttachment(attachment)
        local vm = self.Owner:GetViewModel()
        local attachID = vm:LookupAttachment(attachment)
        if attachID == 0 then return end
        return vm:GetAttachment(attachID)
    end

    function SWEP:CalcView(ply, origin, angles, fov)
        if IsSinglePlayer() then return end
        if not IsValid(self.Owner:GetVehicle()) then
            local attach = self:GetViewModelAttachment("attach_camera")
            if not attach then return end

            local targetAngDiff = Angle(0, 0, 0)
            if self:IsViewingWatch() or self:GetNextPrimaryFire() > CurTime() then
                targetAngDiff = angles - (attach.Ang + angfix)
                if targetAngDiff.r > 179.9 then
                    targetAngDiff.p = math.Clamp(targetAngDiff.p, -89, 89)
                end
            end

            -- interpolate smoothly between current and target
            self.LastAngDiff = self.LastAngDiff or Angle(0, 0, 0)
            self.LastAngDiff = LerpAngle(FrameTime() * lerpSpeed, self.LastAngDiff, targetAngDiff)

            angles = angles - self.LastAngDiff
        end

        return origin, angles, fov
    end
end

function SWEP:CanPrimaryAttack() return true end
function SWEP:CanSecondaryAttack() return true end
function SWEP:ShouldDropOnDie() return false end
