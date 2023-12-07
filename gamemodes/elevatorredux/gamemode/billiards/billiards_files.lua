------------------------------------------------------------
-- MBilliards by Athos Arantes Pereira
-- Contact: athosarantes@hotmail.com
------------------------------------------------------------
-- LUA Files
AddCSLuaFile("cl_billiards.lua")

-- Models
resource.AddFile("models/billiards/ball.mdl")
resource.AddFile("models/billiards/cue.mdl")
resource.AddFile("models/billiards/table_9ft.mdl")
resource.AddFile("models/billiards/table_10ft.mdl")
resource.AddFile("models/billiards/table_12ft.mdl")
resource.AddFile("models/billiards/cr_table_9ft.mdl")
resource.AddFile("models/billiards/cr_table_10ft.mdl")
resource.AddFile("models/billiards/cr_table_12ft.mdl")
resource.AddFile("models/billiards/dzone10ft.mdl")
resource.AddFile("models/billiards/dzone12ft.mdl")
resource.AddFile("models/billiards/minge_p9ft.mdl")
resource.AddFile("models/billiards/minge_p10ft.mdl")
resource.AddFile("models/billiards/minge_p12ft.mdl")
resource.AddFile("models/billiards/headstring9ft.mdl")
resource.AddFile("models/billiards/headstring10ft.mdl")
resource.AddFile("models/billiards/headstring12ft.mdl")

-- Materials
for i = 1, 15 do
	resource.AddFile(string.format("materials/models/billiards/ball%02d.vmt", i))
	resource.AddFile(string.format("materials/vgui/panel/ball%02d.vmt", i))
	if(i >= 4) then continue end
	resource.AddFile(string.format("materials/vgui/panel/skin%d.vmt", i - 1))
end
resource.AddFile("materials/models/billiards/chrome.vmt")
resource.AddFile("materials/models/billiards/cue.vmt")
resource.AddFile("materials/models/billiards/cloth.vmt")
resource.AddFile("materials/models/billiards/cloth2.vmt")
resource.AddFile("materials/models/billiards/cloth3.vmt")
resource.AddFile("materials/models/billiards/sn_cloth.vmt")
resource.AddFile("materials/models/billiards/sn_cloth2.vmt")
resource.AddFile("materials/models/billiards/sn_cloth3.vmt")
resource.AddFile("materials/models/billiards/cr_cloth.vmt")
resource.AddFile("materials/models/billiards/cr_cloth2.vmt")
resource.AddFile("materials/models/billiards/cr_cloth3.vmt")
resource.AddFile("materials/models/billiards/white.vmt")
resource.AddFile("materials/models/billiards/wood.vmt")
resource.AddFile("materials/vgui/entities/billiard_table.vmt")
resource.AddFile("materials/vgui/panel/billiard_gui.vmt")
resource.AddFile("materials/vgui/panel/billiard_sgui.vmt")
resource.AddFile("materials/vgui/panel/billiard_subgui.vmt")
resource.AddFile("materials/vgui/panel/meter.vmt")
resource.AddFile("materials/vgui/panel/needle.vmt")

-- Sounds
for i = 0, 6 do
	local wav = string.format("sound/billiards/hit_%02d.wav", i)
	util.PrecacheSound(wav)
	resource.AddFile(wav)
	if(i >= 6) then continue end
	wav = string.format("sound/billiards/cuehit_%02d.wav", i)
	util.PrecacheSound(wav)
	resource.AddFile(wav)
	wav = string.format("sound/billiards/tablehit_%02d.wav", i)
	util.PrecacheSound(wav)
	resource.AddFile(wav)
end