--[[--------------------------------------------------------------------------
	Wing Tool
	
	Authors:
		- Original :: ROBO_DONUT (Unknown)
		- v1.1     :: PackRat    (Unknown)
		- v1.2     :: ?
		- v1.3     :: Rock       (STEAM_0:1:95796219)
		- v1.4     :: Mista Tea  (STEAM_0:0:27507323)
	
	Math for physics calcs adapted from the	original wing script by ROBO_DONUT.
	Wing tool originally by PackRat. Original code for tool menu by Exeption.
	
	Purpose: Makes props simulate lift and drag like a wing.
]]--

--[[--------------------------------------------------------------------------
-- Localized Functions & Variables
--------------------------------------------------------------------------]]--

-- localizing global functions/tables is an encouraged practice that improves code efficiency,
-- since accessing a local value is considerably faster than a global value
local net = net
local hook = hook
local math = math
local pairs = pairs
local IsValid = IsValid
local SysTime = SysTime
local surface = surface
local duplicator = duplicator

local NOTIFY_GENERIC = NOTIFY_GENERIC or 0
local NOTIFY_ERROR   = NOTIFY_ERROR   or 1
local NOTIFY_CLEANUP = NOTIFY_CLEANUP or 4

local MIN_NOTIFY_BITS = 3 -- the minimum number of bits needed to send a NOTIFY enum
local NOTIFY_DURATION = 5 -- the number of seconds to display notifications

local mode = TOOL.Mode
local prefix = "#tool."..mode.."."

--[[--------------------------------------------------------------------------
-- Tool Settings
--------------------------------------------------------------------------]]--

TOOL.Category = "Construction"
TOOL.Name = prefix.."name"

TOOL.Information = {
	"left",
	"right",
	"reload"
}

TOOL.ClientConVar[ "lift" ] = 1
TOOL.ClientConVar[ "drag" ] = 1
TOOL.ClientConVar[ "area" ] = 1
TOOL.ClientConVar[ "include_area" ] = 0

--[[--------------------------------------------------------------------------
-- Convenience Functions
--------------------------------------------------------------------------]]--

function TOOL:GetLift()           return math.Clamp( self:GetClientNumber( "lift" ), 0, 100 ) end
function TOOL:GetDrag()           return math.Clamp( self:GetClientNumber( "drag" ), 0, 100 ) end
function TOOL:GetArea()           return math.Clamp( self:GetClientNumber( "area" ), 0, 100 ) end
function TOOL:ShouldIncludeArea() return self:GetClientNumber( "include_area" ) == 1 end

if ( CLIENT ) then
	
	--[[--------------------------------------------------------------------------
	-- Language Settings
	--------------------------------------------------------------------------]]--

	language.Add( "tool."..mode..".name", "Wing - Improved" )
	language.Add( "tool."..mode..".desc", "Changes a prop's physical properties to simulate the drag and lift of a wing." )
	language.Add( "tool."..mode..".left", "Create/update wing effect" )
	language.Add( "tool."..mode..".right", "Copy wing settings" )
	language.Add( "tool."..mode..".reload", "Clear wing effect" )
	language.Add( "tool."..mode..".label_lift", "Lift coefficient" )
	language.Add( "tool."..mode..".label_drag", "Drag coefficient" )
	language.Add( "tool."..mode..".label_area", "Wing area" )
	language.Add( "tool."..mode..".label_include_area", "Modify the wing area" )
	
	--[[--------------------------------------------------------------------------
	-- Net Messages
	--------------------------------------------------------------------------]]--

	--[[--------------------------------------------------------------------------
	-- 	Net :: <toolmode>_notif( string )
	--]]--
	net.Receive( mode.."_notif", function( bytes )
		notification.AddLegacy( net.ReadString(), net.ReadUInt(MIN_NOTIFY_BITS), NOTIFY_DURATION )
		local sound = net.ReadString()
		if ( sound ~= "" ) then surface.PlaySound( sound ) end
	end )

	--[[--------------------------------------------------------------------------
	-- 	Net :: <toolmode>_error( string )
	--]]--
	net.Receive( mode.."_error", function( bytes )
		surface.PlaySound( "buttons/button10.wav" )
		notification.AddLegacy( net.ReadString(), net.ReadUInt(MIN_NOTIFY_BITS), NOTIFY_DURATION )
	end )
	
	--[[--------------------------------------------------------------------------
	--
	-- 	TOOL.BuildCPanel( panel )
	--
	--]]--
	function TOOL.BuildCPanel( cpanel )
		local presets = {
			Label = "Presets",
			MenuButton = 1,
			Folder = "wing",
			Options = {
				Default = {
					[mode.."_lift"] = "1",
					[mode.."_drag"] = "1",
					[mode.."_area"] = "1",
					[mode.."_include_area"] = "0",
				}
			},
			CVars = {
				[mode.."_lift"] = "1",
				[mode.."_drag"] = "1",
				[mode.."_area"] = "1",
				[mode.."_include_area"] = "0",
			}
		}
		
		cpanel:AddControl( "Label",    {  Text = prefix.."desc" }  )
		cpanel:AddControl( "ComboBox", presets )
		cpanel:ControlHelp( "" )
		cpanel:AddControl( "Slider",   { Label = prefix.."label_lift", Type = "Float", Min = "0", Max = "20", Command = mode.."_lift" } )
		cpanel:AddControl( "Slider",   { Label = prefix.."label_drag", Type = "Float", Min = "0", Max = "20", Command = mode.."_drag" } )
		cpanel:AddControl( "Checkbox", { Label = prefix.."label_include_area",                                Command = mode.."_include_area" } )
		cpanel:AddControl( "Slider",   { Label = prefix.."label_area", Type = "Float", Min = "0", Max = "20", Command = mode.."_area" } )
	end
	
elseif ( SERVER ) then

	util.AddNetworkString( mode.."_notif" )
	util.AddNetworkString( mode.."_error" )
	
	--[[--------------------------------------------------------------------------
	-- 	TOOL:SendNotif( string )
	--
	--	Convenience function for sending a notification to the tool owner.
	--]]--
	function TOOL:SendNotif( str, notify, sound )
		net.Start( mode.."_notif" )
			net.WriteString( str )
			net.WriteUInt( notify or NOTIFY_GENERIC, MIN_NOTIFY_BITS )
			net.WriteString( sound or "" )
		net.Send( self:GetOwner() )
	end
	
	--[[--------------------------------------------------------------------------
	--	TOOL:SendError( str )
	--
	--	Convenience function for sending an error to the tool owner.
	--]]--
	function TOOL:SendError( str )
		net.Start( mode.."_error" )
			net.WriteString( str )
			net.WriteUInt( notify or NOTIFY_ERROR, MIN_NOTIFY_BITS )
		net.Send( self:GetOwner() )
	end
	
end

--[[--------------------------------------------------------------------------
-- Tool Functions
--------------------------------------------------------------------------]]--

--[[--------------------------------------------------------------------------
--
-- 	TOOL:LeftClick( table )
--
--	Applies the client's wing settings onto the trace entity.
--]]--
function TOOL:LeftClick( tr )
	local ent = tr.Entity
	
	if ( not IsValid( ent ) ) then return false end
	if ( ent:IsPlayer() )     then return false end
	if ( ent:IsWorld() )      then return false end
	if ( CLIENT )             then return true end
	
	local phys = ent:GetPhysicsObject()
	if ( not IsValid( phys ) ) then return false end
	
	-- Check if this entity already has a wing effect
	if ( WingTool.GetData( ent ) ) then
		-- Update existing settings
		WingTool.SetDrag( ent, self:GetDrag() )
		WingTool.SetLift( ent, self:GetLift() )
		WingTool.SetArea( ent, self:ShouldIncludeArea() and self:GetArea() or 1 )
		
		self:SendNotif( "Wing settings updated" )
	else
		-- Setup the entity with a new wing effect
		local data = {
			lift = self:GetLift(),
			drag = self:GetDrag(),
			area = self:ShouldIncludeArea() and self:GetArea() or 1
		}
		
		WingTool.SetupEnt( ply, ent, data )
		
		self:SendNotif( "Wing created" )
	end
	
	return true
end

--[[--------------------------------------------------------------------------
--
-- 	TOOL:RightClick( table )
--
--	Copies the wing settings of the trace entity.
--]]--
function TOOL:RightClick( tr )
	local ent = tr.Entity
	
	if ( not IsValid( ent ) ) then return false end
	if ( ent:IsPlayer() )     then return false end
	if ( ent:IsWorld() )      then return false end
	if ( CLIENT )             then return true end
	
	if ( not IsValid( ent:GetPhysicsObject() ) ) then return false end
	local data = WingTool.GetData( ent )
	if ( not data ) then return false end

	self:GetOwner():ConCommand( ("%s %s; %s %s; %s %s"):format(
		mode.."_lift", data.lift,
		mode.."_drag", data.drag,
		mode.."_area", data.area)
	)
	
	self:SendNotif( "Copied Wing settings" )
	
	return true
end

--[[--------------------------------------------------------------------------
--
-- 	TOOL:Reload( table )
--
--	Clears the trace entity's wing effect.
--]]--
function TOOL:Reload( tr ) 
	local ent = tr.Entity
	
	if ( not IsValid( ent ) ) then return false end
	if ( ent:IsPlayer() )     then return false end
	if ( ent:IsWorld() )      then return false end
	if ( CLIENT )             then return true end
	
	if ( not IsValid( ent:GetPhysicsObject() ) ) then return false end
	if ( not WingTool.GetData( ent ) )           then return false end
	
	WingTool.ClearEnt( ent )
	WingTool.RemoveEnt( ent )

	self:SendNotif( "Wing removed" )
	
	return true
end

if ( SERVER ) then
	
	-- WingTool library
	WingTool = WingTool or {}
	
	-- Highly-accurate time of the last server frame
	WingTool.LastFrame = WingTool.LastFrame or SysTime()
	
	-- Constants
	WingTool.AIR_DENSITY  = WingTool.AIR_DENSITY  or 1.225 -- kg/m^3 https://en.wikipedia.org/wiki/Density_of_air
	WingTool.WATER_DESITY = WingTool.WATER_DESITY or 1000  -- kg/m^3 maximum density of pure water (depends on temperature)
	
	-- Wing-applied entities
	WingTool.Ents = WingTool.Ents or {}
	
	-- Adds a wing effect to the entity and stores the settings for duplicator support
	function WingTool.SetupEnt( ply, ent, data )
		if ( not ( data.lift and data.drag and data.area ) ) then return end
		
		WingTool.AddEnt( ent, data )
		duplicator.StoreEntityModifier( ent, "wing", data )
	end
	duplicator.RegisterEntityModifier( "wing", WingTool.SetupEnt )
	
	-- Adds a wing effect to the entity
	function WingTool.AddEnt( ent, data )
		WingTool.Ents[ent] = {
			lift = data.lift,
			drag = data.drag,
			area = data.area,
			pos  = ent:GetPos()
		}
	end
	
	-- Removes the entity from the table of wings when the entity gets deleted
	function WingTool.RemoveEnt( ent )
		if ( WingTool.Ents[ent] ) then
			WingTool.Ents[ent] = nil
		end
	end
	hook.Add( "EntityRemoved", "WingTool", WingTool.RemoveEnt )
	
	-- Removes the wing effect settings from the entity entirely so they don't carry over via duplicator
	function WingTool.ClearEnt( ent ) duplicator.ClearEntityModifier( ent, "wing" ) end
	
	-- Setters
	function WingTool.SetLift( ent, lift ) WingTool.Ents[ent].lift = lift end
	function WingTool.SetDrag( ent, drag ) WingTool.Ents[ent].drag = drag end
	function WingTool.SetArea( ent, area ) WingTool.Ents[ent].area = area end
	function WingTool.SetPos(  ent,  pos ) WingTool.Ents[ent].pos  = pos  end
	
	-- Getters
	function WingTool.GetData( ent ) return WingTool.Ents[ent]      end
	function WingTool.GetLift( ent ) return WingTool.Ents[ent].lift end
	function WingTool.GetDrag( ent ) return WingTool.Ents[ent].drag end
	function WingTool.GetArea( ent ) return WingTool.Ents[ent].area end
	function WingTool.GetPos(  ent ) return WingTool.Ents[ent].pos  end
	
	--[[--------------------------------------------------------------------------
	--
	-- 	WingTool.Think()
	--
	--	Calculates the force to apply for each wing entity.
	--]]--
	function WingTool.Think()
		local now = SysTime()
		local delta = now - WingTool.LastFrame
		WingTool.LastFrame = now
		
		for ent, data in pairs( WingTool.Ents ) do
			if ( not IsValid( ent ) ) then continue end
			
			local lift = data.lift
			local drag = data.drag
			local area = data.area
			local pos  = data.pos
			
			local dir = (pos - ent:GetPos())
			dir:Normalize()
			
			WingTool.SetPos( ent, ent:GetPos() )
			
			local velsqrd = (ent:GetForward():Dot( pos - ent:GetPos() ) / delta) ^ 2
			local density = ent:WaterLevel() >= 2 and WingTool.WATER_DESITY or WingTool.AIR_DENSITY
			local val = 0.5 * density * velsqrd * area * delta
			
			lift = lift * val -- L = (1/2) * p * v^2 * A * C  http://en.wikipedia.org/wiki/Lift_(force)
			drag = drag * val -- F = (1/2) * p * v^2 * A * C  http://en.wikipedia.org/wiki/Drag_equation
			
			local force = (ent:GetUp() * lift) + (dir * drag)
			ent:GetPhysicsObject():ApplyForceCenter( force )
		end
	end
	hook.Add( "Think", "WingToolThink", WingTool.Think )
end
