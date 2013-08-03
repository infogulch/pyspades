--[[
	Copyright (c) Mathias Kaerlev 2011-2012.
	Copyright (c) Ben "GreaseMonkey" Russell, 2013.

	This file is a part of pyspades.

	pyspades is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation, either version 3 of the License, or
	(at your option) any later version.

	pyspades is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with pyspades.  If not, see <http://www.gnu.org/licenses/>.
]]

-- it also depends on some iceball stuff which is LGPLv3,
-- and lib_sdlkey.lua which is LGPLv2.1.

nick = ...

if not nick then error("Set your nickname on the commandline!") end

BASEDIR = "pkg/aostun"
TMPDIR = "clsave/vol"

-- TODO: autodetect
-- true == 0.75, false == 0.76
COMPAT075 = false

-- settings
	-- COMPAT_SHOT_ORDER: (TODO)
	--   Set to true to shoot the first player you see in the player list.
	--   Set to false to shoot the player nearest to you.
	COMPAT_SHOT_ORDER = true

	-- COMPAT_SHOTGUN_SPREAD: (TODO)
	--   Set to true to set pallet spread based on previous pallet.
	--   Set to false to set pallet spread based on firing vector.
	COMPAT_SHOTGUN_SPREAD = true

-- constants

PHY_TICK = 1/62.5
MAXZDIM = 64
PI = 3.141592653589793
VSID = 512 -- maximum .VXL dimensions in both x & y direction
VSIDM = (VSID-1)
VSIDSQ = (VSID*VSID)
CHUNK = 1023 --zlib buffer size
VSIDSQM = (VSIDSQ-1)
MAXSCANDIST = 128
MAXSCANSQ = (MAXSCANDIST*MAXSCANDIST)
VOXSIZ = (VSIDSQ*MAXZDIM)
SCPITCH = 128
ONE_OVER_SQRT_2 = 0.70710678 -- better name for this variable -GM
MINERANGE = 3
MAXZDIM = 64 --Maximum .VXL dimensions in z direction (height)
MAXZDIMM = (MAXZDIM-1)
MAXZDIMMM = (MAXZDIM-2)
PORT = 32887
GRID_SIZE = 64
FALL_SLOW_DOWN = 0.24
FALL_DAMAGE_VELOCITY = 0.58
FALL_DAMAGE_SCALAR = 4096
MINERANGE = 3
WEAPON_PRIMARY = 1

JERK_SPEED = 40

-- weapon data
weapons = {
	[0] = {
		name = "Rifle",
		delay = 0.6,
		ammo = 8,
		stock = 48,
		reload_time = 2.5,
		slow_reload = false,
		m_tracer = "semitracer",
		spread = 0.004, -- still only a 79% accuracy within a 0.5 block radius at the fogline --GM
		recoil_y = -0.075,
		recoil_x = 0.0002,
		shot_count = 1,
	},
	[1] = {
		name = "SMG",
		delay = 0.1, -- we are going to be doing AoS-style scheduling.
		ammo = 30,
		stock = 150,
		reload_time = 2.5,
		slow_reload = false,
		m_tracer = "smgtracer",
		spread = 0.012,
		recoil_y = -0.0125,
		recoil_x = 0.00005,
		shot_count = 1,
	},
	[2] = {
		name = "Shotgun",
		delay = 0.8,
		ammo = 8,
		stock = 48,
		reload_time = 0.4,
		slow_reload = true,
		m_tracer = "shotguntracer",
		spread = 0.036, -- unless he made the spread pattern not suck in 0.76, this is actually really, really bad.
		recoil_y = -0.075,
		recoil_x = 0.0002,
		shot_count = 8,
	},
}

-- includes
dofile(BASEDIR.."/lib_sdlkey.lua")
dofile(BASEDIR.."/lib_collect.lua")
dofile(BASEDIR.."/lib_map.lua")
dofile(BASEDIR.."/lib_vector.lua")

-- some stubs so the iceball libs can work properly
function bhealth_clear() end
function new_particle() end
function particles_add() end
function client.wav_play_global() end

function parsekv6(pkt, name, ptsize, ptspacing)
	if pkt:sub(1,4) ~= "Kvxl" then
		print("not a KV6 model")
	end
	local _

	-- load header
	local xsiz, ysiz, zsiz
	_, xsiz, ysiz, zsiz, pkt = common.net_unpack("IIII", pkt)
	local xpivot, ypivot, zpivot
	xpivot, ypivot, zpivot, pkt = common.net_unpack("fff", pkt)
	local blklen
	blklen, pkt = common.net_unpack("I", pkt)

	-- load blocks
	local l = {}
	local i
	for i=1,blklen do
		local r,g,b,z
		b,g,r,_,z,_,_,pkt = common.net_unpack("BBBBHBB", pkt)
		l[i] = {
			radius = ptsize,
			x = nil, z = nil, y = (z-zpivot)*ptspacing,
			r = r, g = g, b = b,
		}
	end

	-- skip x offsets
	pkt = pkt:sub(4*xsiz+1)

	-- load xy offsets
	-- TODO: check order
	local x,y,i,j
	i=1
	for x=1,xsiz do
	for y=1,ysiz do
		local ct
		ct, pkt = common.net_unpack("H", pkt)
		for j=1,ct do
			l[i].x = (x-xpivot)*ptspacing
			l[i].z = (y-ypivot)*ptspacing
			i = i + 1
		end
	end
	end

	-- create model
	local mdl, mdl_bone
	mdl = common.model_new(1)
	mdl, mdl_bone = common.model_bone_new(mdl, #l)
	common.model_bone_set(mdl, mdl_bone, name, l)

	print("model data len:", #l)

	return mdl
end

function loadkv6(fname, name, ptsize, ptspacing)
	return parsekv6(common.bin_load(fname), name, ptsize, ptspacing)
end

function stripnul(s)
	local ret = ""
	local i
	for i=1,s:len() do
		local c = s:sub(i,i)
		if c:byte() == 0 then
			return ret
		end
		ret = ret..c
	end
	return ret
end

function recolor_model(mdl, r, g, b, reuse)
	local nmdl = reuse or common.model_new(1)
	local nmdl_bone = 0
	if not reuse then
		nmdl, nmdl_bone = common.model_bone_new(nmdl)
	end

	local name, l 
	name, l = common.model_bone_get(mdl, 0)
	local i
	for i=1,#l do
		local c = l[i]
		if c.r == 0 and c.g == 0 and c.b == 0 then
			c.r, c.g, c.b = r, g, b
		end
	end
	common.model_bone_set(nmdl, 0, name, l)

	return nmdl
end

function setfog(r, g, b)
	local plr = players and players[players.current]
	if plr and plr.team >= 0 then
		client.map_fog_set(r, g, b, 127.5*((client.renderer == "gl" and 1.1) or 1.0))
	else
		client.map_fog_set(r, g, b, 511.5)
	end
end
setfog(0,0,0)

print("Load models...")
MODEL_NAMES = {
	"block", "cp", "grenade", "intel",
	"playerarms", "playerdead", "playerhead", "playerlegc", "playerleg", "playertorsoc", "playertorso",
	"semicasing", "semi", "semitracer",
	"shotguncasing", "shotgun", "shotguntracer",
	"smgcasing", "smg", "smgtracer",
	"spade",
}

MODELS = {}
do
	local i
	for i=1,#MODEL_NAMES do
		local mdl
		print("model:", MODEL_NAMES[i])
		mdl = loadkv6(BASEDIR.."/data/kv6/"..MODEL_NAMES[i]..".kv6", MODEL_NAMES[i], 9, 16)
		MODELS[MODEL_NAMES[i]] = mdl
	end
end

-- have to code this one myself as pyspades uses raw while iceball essentially uses vxl -GM
function get_solid(x, y, z)
	local l = common.map_pillar_get(x, z)
	local i = 1
	while true do
		local n,s,e = l[i+0], l[i+1], l[i+2]
		if y < s then return false end
		if n == 0 then return true end
		i = i + 4*n
		local a = l[i+3]
		if y < a then return true end
	end
end

--same as isvoxelsolid but water is empty && out of bounds returns true
function clipbox(x, z, y)
	local sy

	if (x < 0 or x >= 512 or z < 0 or z >= 512) then
		return true
	elseif (y < 0) then
		return false
	end
	sy = math.floor(y)
	if(sy == 63) then
		sy=62
	elseif (sy >= 64) then
		return true
	end
	return get_solid(math.floor(x), sy, math.floor(z))
end


print("Load map...")
map_main = common.map_load("*MAP", "vxl")
print("READY!")
common.map_set(map_main)

g_sec_current, g_sec_delta = nil, nil
g_sec_delay = 4

camay, camax = 0, 0
fwx, fwy, fwz = 0, 0, 1
skx, sky, skz = 0, -1, 0
camx, camy, camz = 255.5, 32, 255.5

tracers = {}

function new_tracer(x, y, z, vx, vy, vz, model)
	local this = {
		x = x, y = y, z = z,
		vx = vx, vy = vy, vz = vz,
		model = model,
		speed = 140.0,
		expiry = nil,
		dead = false,
	}

	function this.tick(sec_current, sec_delta)
		this.expiry = this.expiry or (sec_current + 1.0)
		local mvspeed = this.speed * sec_delta
		this.x = this.x + vx * mvspeed
		this.y = this.y + vy * mvspeed
		this.z = this.z + vz * mvspeed

		this.dead = (sec_current >= this.expiry)
	end

	function this.render()
		local invy = math.sqrt(1 - this.vy)
		local xa = -math.asin(this.vy)
		local ya = math.atan2(this.vx/invy, this.vz/invy)

		client.model_render_bone_global(this.model, 0,
			this.x, this.y, this.z, 0.0, xa, ya, 2.0)
	end

	tracers[#tracers+1] = this

	return this
end

function tracers_tick(sec_current, sec_delta)
	local i = 1
	while i <= #tracers do
		if tracers[i].dead then
			tracers[i] = tracers[#tracers]
			tracers[#tracers] = nil
		else
			tracers[i].tick(sec_current, sec_delta)
			i = i + 1
		end
	end
end

function tracers_render()
	local i
	for i=1,#tracers do
		tracers[i].render()
	end
end

function new_player(pid)
	local this = {
		pid = pid,
		alive = false, spawned = false,
		fwx = 0, fwy = 0, fwz = 1,
		camx = 0, camy = 0, camz = 0,
		jerkoffs = 0,
		lcamx = 0, lcamy = 0, lcamz = 0,
		ltick = nil,
		tool = 2, gun = 0,
		team = -2,
		score = 0,
		r = 127, g = 127, b = 127,
		name = nil,
		vx = 0, vy = 0, vz = 0,
		mvu = false, mvd = false, mvl = false, mvr = false,
		jumping = false, crouching = false, sneaking = false, sprinting = false,
		lmb = false, rmb = false,
		upd_key = false, upd_mouse = false,
		airborne = false, wade = false,
		lastclimb = nil,
		lastflags = 0,
		lastwflags = 0,
		last_time_phy = nil,
		lfwx = nil, lfwy = nil, lfwz = nil,
	}

	function this.set_crouch(new_crouch)
		if new_crouch and not this.crouching then
			if not this.airborne then
				this.camy = this.camy + 0.9
				this.jerkoffs = this.jerkoffs - 0.9
			end
			this.crouching = new_crouch
		elseif this.crouching and not new_crouch then
			-- TODO: ceiling check
			if not this.airborne then
				this.camy = this.camy - 0.9
				this.jerkoffs = this.jerkoffs + 0.9
			end
			this.crouching = new_crouch
		end
	end

	function this.updateflags(sec_current)
		local b = 0
		local wb = 0

		if this.sprinting then b = b + 128 end
		if this.sneaking then b = b + 64 end
		if this.crouching then b = b + 32 end
		if this.jumping then b = b + 16 end
		if this.mvr then b = b + 8 end
		if this.mvl then b = b + 4 end
		if this.mvd then b = b + 2 end
		if this.mvu then b = b + 1 end

		if this.rmb then wb = wb + 2 end
		if this.lmb then wb = wb + 1 end

		local queue_flags = (this.lastflags ~= b)
		local queue_wflags = (this.lastwflags ~= wb)
		this.lastflags = b
		this.lastwflags = wb

		if not this.last_time_phy then
			this.last_time_phy = sec_current
		end
		
		if sec_current >= this.last_time_phy + 0.1 then
			this.last_time_phy = this.last_time_phy + 0.1
			if sec_current >= this.last_time_phy + 0.1 then
				this.last_time_phy = sec_current
			end
			if this.fwx and (this.lfwx ~= this.fwx or this.lfwy ~= this.fwy or this.lfwz ~= this.fwz) then
				if this.team >= 0 then
					common.net_send(nil, common.net_pack("Bfff", 0x01, this.fwx, this.fwz, this.fwy))
				end
				this.lfwx = this.fwx
				this.lfwy = this.fwy
				this.lfwz = this.fwz
			end
			if this.camx and this.team >= 0 then
				common.net_send(nil, common.net_pack("Bfff", 0x00, this.camx, this.camz, this.camy))
			end
		end

		if queue_flags and this.team >= 0 then
			common.net_send(nil, common.net_pack("BBB", 0x03, this.pid, b))
		end
		if queue_wflags and this.team >= 0 then
			common.net_send(nil, common.net_pack("BBB", 0x04, this.pid, wb))
		end
	end

	function this.setflags(b)
		this.sprinting = (b >= 128); b = b % 128
		this.sneaking = (b >= 64); b = b % 64
		local new_crouch = (b >= 32); b = b % 32
		this.jumping = (b >= 16); b = b % 16
		this.mvr = (b >= 8); b = b % 8
		this.mvl = (b >= 4); b = b % 4
		this.mvd = (b >= 2); b = b % 2
		this.mvu = (b >= 1); b = b % 1

		this.set_crouch(new_crouch)
		this.crouching = new_crouch
	end

	function this.setwpnflags(b)
		b = b % 4
		this.rmb = (b >= 2); b = b % 2
		this.lmb = (b >= 1); b = b % 1
	end

	-- player movement with autoclimb
	function this.boxclipmove(ftotclk, fsynctics)
		local offset, m, f, nx, ny, nz, y
		local climb = false

		f = fsynctics*32
		nx = f*this.vx+this.camx
		nz = f*this.vz+this.camz

		if this.crouching then
			offset = 0.45
			m = 0.9
		else
			offset = 0.9
			m = 1.35
		end

		ny = this.camy + offset

		if(this.vx < 0) then f = -0.45
		else f = 0.45
		end

		y=m

		while y>=-1.36 and (not clipbox(nx+f, this.camz-0.45, ny+y)) and (not clipbox(nx+f, this.camz+0.45, ny+y)) do
			y = y - 0.9
		end
		if(y<-1.36) then this.camx = nx
		elseif((not this.crouching) and this.fwy<0.5 and (not this.sprinting)) then
			y=0.35
			while(y>=-2.36 and (not clipbox(nx+f, this.camz-0.45, ny+y)) and (not clipbox(nx+f, this.camz+0.45, ny+y))) do
				y = y - 0.9
			end
			if(y<-2.36) then
				this.camx = nx
				climb=true
			else this.vx = 0
			end
		else this.vx = 0
		end

		if(this.vy < 0) then f = -0.45
		else f = 0.45
		end

		y=m
		while(y>=-1.36 and (not clipbox(this.camx-0.45, nz+f, ny+y)) and (not clipbox(this.camx+0.45, nz+f, ny+y))) do
			y = y - 0.9
		end
		if(y<-1.36) then this.camz = nz
		elseif((not this.crouching) and this.fwy<0.5 and (not this.sprinting) and (not climb)) then
			y=0.35
			while(y>=-2.36 and (not clipbox(this.camx-0.45, nz+f, ny+y)) and (not clipbox(this.camx+0.45, nz+f, ny+y))) do
				y = y - 0.9
			end
			if(y<-2.36) then
				this.camz = nz
				climb=true
			else this.vz = 0
			end
		elseif (not climb) then
			this.vz = 0
		end

		if(climb) then
			this.vx = this.vx * 0.5
			this.vz = this.vz * 0.5
			this.jerkoffs = this.jerkoffs + 1
			this.lastclimb = ftotclk
			ny = ny - 1
			m = -1.35
		else
			if(this.vy < 0) then
				m=-m
			end
			ny = ny + this.vy*fsynctics*32
		end

		this.airborne = true

		if(clipbox(this.camx-0.45, this.camz-0.45, ny+m) or
			clipbox(this.camx-0.45, this.camz+0.45, ny+m) or
			clipbox(this.camx+0.45, this.camz-0.45, ny+m) or
			clipbox(this.camx+0.45, this.camz+0.45, ny+m))
		then
			if(this.vy >= 0) then
				this.wade = this.camy > 61
				this.airborne = false
			end
			this.vy = 0
		else
			this.camy = ny-offset
		end
	end

	function this.move_player(ftotclk, fsynctics)
		local f, f2

		-- unlike pyspades we don't store the side/down vectors,
		-- so we have to calculate them on the fly...
		-- not like it's particularly CPU intensive at all -GM

		-- get forward vector
		local fwx, fwy, fwz = this.fwx, this.fwy, this.fwz
		local sdx, sdy, sdz
		local upx, upy, upz

		-- calculate side vector
		sdx = fwy * skz - fwz * sky
		sdy = fwz * skx - fwx * skz
		sdz = fwx * sky - fwy * skx

		-- calculate up vector
		upx = fwy * sdz - fwz * sdy
		upy = fwz * sdx - fwx * sdz
		upz = fwx * sdy - fwy * sdx

		-- calculate vector lengths
		local sdd = math.sqrt(sdx*sdx + sdy*sdy + sdz*sdz)
		local upd = math.sqrt(upx*upx + upy*upy + upz*upz)

		-- normalise vectors
		sdx = -sdx / sdd
		sdy = -sdy / sdd
		sdz = -sdz / sdd
		upx = upx / upd
		upy = upy / upd
		upz = upz / upd

		--move player and perform simple physics (gravity, momentum, friction)
		if this.jumping then
			this.jumping = false
			this.vy = -0.36
		end

		f = fsynctics --player acceleration scalar
		if this.airborne then
			f = f * 0.1
		elseif this.crouching then
			f = f * 0.3
		elseif (this.rmb and this.tool == 2) or this.sneaking then
			f = f * 0.5
		elseif this.sprinting then
			f = f * 1.3
		end

		if (this.mvu or this.mvd) and (this.mvl or this.mvr) then
			f = f * ONE_OVER_SQRT_2 --if strafe + forward/backwards then limit diagonal velocity
		end

		if this.mvu then
			this.vx = this.vx + this.fwx*f
			this.vz = this.vz + this.fwz*f
		elseif this.mvd then
			this.vx = this.vx - this.fwx*f
			this.vz = this.vz - this.fwz*f
		end

		if this.mvl then
			this.vx = this.vx - sdx*f
			this.vz = this.vz - sdz*f
		elseif this.mvr then
			this.vx = this.vx + sdx*f
			this.vz = this.vz + sdz*f
		end

		f = fsynctics + 1
		this.vy = this.vy + fsynctics
		this.vy = this.vy / f --air friction
		if this.wade then
			f = fsynctics*6 + 1 --water friction
		elseif not this.airborne then
			f = fsynctics*4 + 1 --ground friction
		end
		this.vx = this.vx / f
		this.vz = this.vz / f
		f2 = this.vy
		this.boxclipmove(ftotclk, fsynctics)
		--hit ground... check if hurt
		if (this.vy == 0) and (f2 > FALL_SLOW_DOWN) then
			--slow down on landing
			this.vx = this.vx * 0.5
			this.vz = this.vz * 0.5

			--return fall damage
			if f2 > FALL_DAMAGE_VELOCITY then
				f2 = f2 - FALL_DAMAGE_VELOCITY
				return(math.floor(f2*f2*FALL_DAMAGE_SCALAR))
			end

			return(-1) -- no fall damage but play fall sound
		end

		return(0) --no fall damage
	end

	function this.fire_shot(sec_current, sec_delta)
		-- get forward vector
		local fwx, fwy, fwz

		fwx = this.fwx
		fwy = this.fwy
		fwz = this.fwz

		-- apply spread
		local spread = weapons[this.gun].spread
		local sx = (2*math.random()-1)*spread
		local sy = (2*math.random()-1)*spread
		local sz = (2*math.random()-1)*spread

		fwx = fwx + sx
		fwy = fwy + sy
		fwz = fwz + sz

		-- normalise
		local fwd = 1.0 / math.sqrt(fwx*fwx + fwy*fwy + fwz*fwz)
		fwx = fwx * fwd
		fwy = fwy * fwd
		fwz = fwz * fwd

		-- trace against players
		-- TODO!

		-- apply recoil
		-- TODO!

		-- add tracer
		new_tracer(this.camx, this.camy, this.camz, fwx, fwy, fwz, MODELS[weapons[this.gun].m_tracer])

		-- play sound
		-- TODO!
	end

	function this.update_gun(sec_current, sec_delta)
		if this.t_nexttrig and sec_current >= this.t_nexttrig then
			this.t_nexttrig = nil
		end
		if this.lmb then
			if this.t_nextshot and sec_current >= this.t_nextshot then
				this.t_nextshot = nil
			end
			if not this.t_nextshot then
				this.fire_shot(sec_current, sec_delta)
				this.t_nextshot = sec_current + weapons[this.gun].delay
				this.t_nexttrig = sec_current + weapons[this.gun].delay
			end
		else
			this.t_nextshot = nil
		end
	end

	function this.tick(sec_current, sec_delta)
		if not this.spawned then return end
		if this.team < -1 then return end
		if this.team == -1 and this.pid ~= players.current then return end

		if this.team == -1 then
			-- get forward vector
			local fwx, fwy, fwz = this.fwx, this.fwy, this.fwz
			local sdx, sdy, sdz
			local upx, upy, upz

			-- calculate side vector
			sdx = fwy * skz - fwz * sky
			sdy = fwz * skx - fwx * skz
			sdz = fwx * sky - fwy * skx

			-- calculate up vector
			upx = fwy * sdz - fwz * sdy
			upy = fwz * sdx - fwx * sdz
			upz = fwx * sdy - fwy * sdx

			-- calculate vector lengths
			local sdd = math.sqrt(sdx*sdx + sdy*sdy + sdz*sdz)
			local upd = math.sqrt(upx*upx + upy*upy + upz*upz)

			-- normalise vectors
			sdx = sdx / sdd
			sdy = sdy / sdd
			sdz = sdz / sdd
			upx = upx / upd
			upy = upy / upd
			upz = upz / upd

			local mvspeed = 30.0 * sec_delta
			if this.sneaking then mvspeed = mvspeed * 0.5 end
			if this.sprinting then mvspeed = mvspeed * 3.0 end
			if this.mvu then
				this.camx = this.camx + fwx * mvspeed
				this.camy = this.camy + fwy * mvspeed
				this.camz = this.camz + fwz * mvspeed
			end
			if this.mvd then
				this.camx = this.camx - fwx * mvspeed
				this.camy = this.camy - fwy * mvspeed
				this.camz = this.camz - fwz * mvspeed
			end
			if this.mvl then
				this.camx = this.camx + sdx * mvspeed
				this.camy = this.camy + sdy * mvspeed
				this.camz = this.camz + sdz * mvspeed
			end
			if this.mvr then
				this.camx = this.camx - sdx * mvspeed
				this.camy = this.camy - sdy * mvspeed
				this.camz = this.camz - sdz * mvspeed
			end
			if this.crouching then
				this.camx = this.camx + upx * mvspeed
				this.camy = this.camy + upy * mvspeed
				this.camz = this.camz + upz * mvspeed
			end
			if this.jumping then
				this.camx = this.camx - upx * mvspeed
				this.camy = this.camy - upy * mvspeed
				this.camz = this.camz - upz * mvspeed
			end
		elseif this.team >= 0 then
			this.jerkoffs = math.exp(-sec_delta*JERK_SPEED) * this.jerkoffs
			if math.abs(this.jerkoffs) > 5 then
				this.jerkoffs = 0
			end
			this.update_gun(sec_current, sec_delta)
			local fdmg = this.move_player(sec_current, sec_delta)
			--print(this.vx, this.vy, this.vz)
		end
	end

	return this
end

function new_team(tid, name, r, g, b)
	local this = {
		tid = tid,
		name = name,
		r = r, g = g, b = b,
		score = 0,
		models = {
			playerarms = recolor_model(MODELS["playerarms"], r, g, b),
			playerdead = recolor_model(MODELS["playerdead"], r, g, b),
			playerhead = recolor_model(MODELS["playerhead"], r, g, b),
			playerlegc = recolor_model(MODELS["playerlegc"], r, g, b),
			playerleg = recolor_model(MODELS["playerleg"], r, g, b),
			playertorsoc = recolor_model(MODELS["playertorsoc"], r, g, b),
			playertorso = recolor_model(MODELS["playertorso"], r, g, b),
		},
	}

	function this.setcolor(r, g, b)
		this.r, this.g, this.b = r, g, b
	end

	function this.setname(name)
		this.name = name
	end

	return this
end

function new_ent(typ, team, x, y, z, pid)
	local this = {
		typ = typ,
		team = team,
		x = x, y = y, z = z,
		pid = pid,
	}
end

function block_set(x, y, z, r, g, b)
	map_block_set(x, y, z, 1, r, g, b)
end

function block_del(x, y, z)
	map_block_break(x, y, z)
end

players = {}
teams = {}
ents = {}
do
	local i
	for i=0,80-1 do -- allocating a fuckton because the block action packet SUCKS
		players[i] = new_player(i)
	end
	teams[-1] = new_team(i, "Spectator", 0, 0, 0)
	teams[0] = new_team(i, "Blue", 0, 0, 255)
	teams[1] = new_team(i, "Green", 0, 255, 0)
end

game_mode = -1
cap_limit = 0
players.current = -1

ktab = {}

is_typing = false
chat_text = nil
chat_type = nil

chat_backlog = {}

font_mini = common.img_load(BASEDIR.."/font-mini.tga")

function draw_text(x, y, c, s)
	if s and s ~= "" then
		local ch = s:byte(1)
		client.img_blit(font_mini, x, y, 6, 8, (ch-32)*6, 0, c)
		return draw_text(x+6, y, c, s:sub(2))
	end
end

function client.hook_key(key, state, modif, uni)
	if is_typing then
		if state then
			if key == SDLK_RETURN then
				if chat_text and chat_text ~= "" then
					if chat_text:sub(1,1) == "~" then
						local r, f = pcall(loadstring, chat_text:sub(2))
						if r then
							print("CALL:", pcall(f))
						else
							print("ERR:", f)
						end
					else
						common.net_send(nil, common.net_pack("BBBz", 0x11,
							players.current, chat_type, chat_text))
					end
				end
				is_typing = false
				chat_text = nil
				chat_type = nil
			elseif key == SDLK_ESCAPE then
				is_typing = false
				chat_text = nil
				chat_type = nil
			elseif key == SDLK_BACKSPACE then
				if chat_text ~= "" then
					chat_text = chat_text:sub(1,chat_text:len()-1)
				end
			elseif uni >= 32 and uni <= 126 then
				chat_text = chat_text..(string.char(uni))
			end
		end
	else
		ktab[key] = state or nil
		if state then
			if key == SDLK_ESCAPE then
				client.hook_tick = nil
			elseif key == SDLK_t then
				is_typing = true
				chat_text = ""
				chat_type = 0
			elseif key == SDLK_y then
				is_typing = true
				chat_text = ""
				chat_type = 1
			elseif key == SDLK_p then
				if spec_player then
					spec_player = nil
				else
					local i
					local tplr = players[players.current]
					local td = nil
					local ti = nil
					for i=0,31 do
						local plr = players[i]
						if i ~= players.current and plr then
							local dx = plr.camx - tplr.camx
							local dy = plr.camy - tplr.camy
							local dz = plr.camz - tplr.camz
							local d = dx*dx + dy*dy + dz*dz
							if (not td) or d < td then
								ti = i
								td = d
							end
						end
					end
					if ti then
						spec_player = ti
					end
				end
			end
		end
	end
end

function handle_network(sec_current, sec_delta)
	while true do
		local pkt, neth
		pkt, neth = common.net_recv()
		if pkt == false then error("Connection terminated!") end
		if not pkt then return end

		local typ
		typ, pkt = common.net_unpack("B", pkt)

		if typ == 0x00 then
			-- position data
			local pid, camx, camy, camz
			camx, camz, camy, pkt = common.net_unpack("fff", pkt)
			local dx,dy,dz
			local plr = players[players.current]
			if plr then
				dx = (camx - plr.camx)
				dy = (camy - plr.camy)
				dz = (camz - plr.camz)
				if dx*dx + dz*dz > 2*2 or dy*dy > 2*2 then
					plr.camx = camx
					plr.camy = camy
					plr.camz = camz
					plr.lcamx = camx
					plr.lcamy = camy
					plr.lcamz = camz
					plr.ltick = sec_current
				end
			end
		elseif typ == 0x02 then
			-- world update
			local i
			local entlen = 25
			if COMPAT075 then entlen = 24 end
			local plen = math.floor(pkt:len()/entlen+0.001)
			for i=0,plen-1 do
				if i ~= players.current then
					local idx = i
					if not COMPAT075 then
						idx, pkt = common.net_unpack("B", pkt)
					end
					local plr = players[idx]
					local nx,ny,nz
					local dx,dy,dz
					nx, nz, ny, pkt = common.net_unpack("fff", pkt)
					dx = (nx - plr.camx)
					dy = (ny - plr.camy)
					dz = (nz - plr.camz)
					plr.camx = nx
					plr.camy = ny
					plr.camz = nz
					if plr.ltick then
						local diff = sec_current - plr.ltick
						if diff > 0.04 then
							local vx, vy, vz
							vx = (plr.camx - plr.lcamx) / diff * PHY_TICK
							vy = (plr.camy - plr.lcamy) / diff * PHY_TICK
							vz = (plr.camz - plr.lcamz) / diff * PHY_TICK
							if vx*vx + vy*vy + vz*vz < 20.0^2 then
								plr.vx = vx
								plr.vy = vy
								plr.vz = vz
							end
						end
					end
					plr.lcamx = nx
					plr.lcamy = ny
					plr.lcamz = nz
					plr.ltick = sec_current
					plr.fwx, plr.fwz, plr.fwy, pkt = common.net_unpack("fff", pkt)
				else
					pkt = pkt:sub(entlen+1)
				end
			end
		elseif typ == 0x03 then
			-- input data
			local pid, b
			pid, b, pkt = common.net_unpack("BB", pkt)
			local plr = players[pid]
			plr.setflags(b)
		elseif typ == 0x04 then
			-- weapon input data
			local pid, b
			pid, b, pkt = common.net_unpack("BB", pkt)
			local plr = players[pid]
			plr.setwpnflags(b)
		elseif typ == 0x07 then
			-- set tool
			local pid
			pid, pkt = common.net_unpack("B", pkt)
			local plr = players[pid]
			plr.tool, pkt = common.net_unpack("B", pkt)
			--print("set tool #"..pid.." = ["..plr.name.."]", plr.tool)
		elseif typ == 0x08 then
			-- set colour
			local pid
			pid, pkt = common.net_unpack("B", pkt)
			local plr = players[pid]
			plr.b, plr.g, plr.r, pkt = common.net_unpack("BBB", pkt)
			--print("set colour #"..pid.." = ["..plr.name.."]", plr.r, plr.g, plr.b)
		elseif typ == 0x09 then
			-- existing player
			local pid
			pid, pkt = common.net_unpack("B", pkt)
			local plr = players[pid]
			plr.team, plr.gun, plr.tool, plr.score, pkt = common.net_unpack("bBBI", pkt)
			plr.alive = true
			plr.spawned = true
			plr.b, plr.g, plr.r, pkt = common.net_unpack("BBB", pkt)
			plr.name = pkt:sub(1,pkt:len()-1)
			print("existing player #"..pid.." = ["..plr.name.."] - team "..plr.team..", gun = "..plr.gun..", score = "..plr.score)
		elseif typ == 0x0A then
			-- short player data
			local pid
			pid, pkt = common.net_unpack("B", pkt)
			local plr = players[pid]
			plr.team, plr.gun, pkt = common.net_unpack("bB", pkt)
			print("short player data #"..pid.." = ["..plr.name.."] - team "..plr.team..", gun = "..plr.gun)
		elseif typ == 0x0C then
			-- create player
			local pid
			pid, pkt = common.net_unpack("B", pkt)
			local plr = players[pid]
			plr.gun, plr.team, pkt = common.net_unpack("Bb", pkt)
			if pid == players.current then
				setfog(client.map_fog_get())
			end
			plr.camx, plr.camz, plr.camy, pkt = common.net_unpack("fff", pkt)
			plr.fwx, plr.fwz, plr.fwy = ((plr.team == 0 and 1) or -1), 0, 0
			plr.tool = 2
			plr.alive = true
			plr.spawned = true
			plr.name = pkt:sub(1,pkt:len()-1)
			print("create player #"..pid.." = ["..plr.name.."] - team "..plr.team..", gun = "..plr.gun)
		elseif typ == 0x0D then
			-- block action
			local pid
			pid, typ, x, z, y, pkt = common.net_unpack("BBiii", pkt)
			local plr = players[pid]
			if typ == 0 then
				-- NO. we BUILD.
				block_set(x, y, z, plr.r, plr.g, plr.b)
			else
				-- DIGGY DIGGY HOLE
				block_del(x, y, z)
			end
		elseif typ == 0x0F then
			-- state data
			local r, g, b
			players.current, pkt = common.net_unpack("B", pkt)
			print("player ID = "..players.current)
			b, g, r, pkt = common.net_unpack("BBB", pkt)
			setfog(r, g, b)
			b, g, r, pkt = common.net_unpack("BBB", pkt)
			teams[0].setcolor(r, g, b)
			b, g, r, pkt = common.net_unpack("BBB", pkt)
			teams[1].setcolor(r, g, b)
			teams[0].setname(stripnul(pkt:sub(1, 10)))
			teams[1].setname(stripnul(pkt:sub(11, 20)))
			pkt = pkt:sub(21)
			if game_mode ~= -1 then
				-- load new map
				common.map_set(nil)
				common.map_free(map_main)
				map_main = common.map_load("*MAP", "vxl")
				common.map_set(map_main)
				players[players.current].team = -2
			end
			game_mode, pkt = common.net_unpack("B", pkt)
			print("game mode = "..game_mode)
			if game_mode == 0 then
				print("Game Mode: CTF")
				teams[0].score, teams[1].score, pkt = common.net_unpack("BB", pkt)
				local iflags
				cap_limit, iflags = common.net_unpack("BB", pkt)

				local x, y, z, pid
				-- intels
				if math.floor((iflags/1)%2) ~= 0 then
					pid = common.net_unpack("B", pkt)
					pkt = pkt:sub(13)
					ents[0] = new_ent(1, 0, -1, -1, -1, pid)
				else
					x, y, z, pkt = common.net_unpack("fff", pkt)
					ents[0] = new_ent(1, 0, x, y, z, nil)
				end
				if math.floor((iflags/2)%2) ~= 0 then
					pid = common.net_unpack("B", pkt)
					pkt = pkt:sub(13)
					ents[1] = new_ent(1, 1, -1, -1, -1, pid)
				else
					x, y, z, pkt = common.net_unpack("fff", pkt)
					ents[1] = new_ent(1, 1, x, y, z, nil)
				end
				x, y, z, pkt = common.net_unpack("fff", pkt)
				ents[2] = new_ent(0, 0, x, y, z, nil)
				x, y, z, pkt = common.net_unpack("fff", pkt)
				ents[3] = new_ent(0, 1, x, y, z, nil)
				print("cap limit:", cap_limit)
				print("team scores:", teams[0].score, teams[1].score)
			elseif game_mode == 1 then
				print("Game Mode: TC")
				-- TODO: LOAD DEM FUKKEN TENTS
			else
				error("Unexpected game mode!")
			end
		elseif typ == 0x10 then
			-- kill action
			local pid, kpid
			pid, kpid, pkt = common.net_unpack("BB", pkt)
			local plr = players[pid]
			local kplr = players[kpid]
			local ktyp, rtime
			ktyp, rtime, pkt = common.net_unpack("BB", pkt)
			plr.alive = false
		elseif typ == 0x11 then
			-- chat message
			local pid, mtyp
			pid, mtyp, pkt = common.net_unpack("BB", pkt)
			local msg, col
			if mtyp == 2 then
				msg = "[SYS/"..mtyp.."]: "..stripnul(pkt)
				col = 0xFFFF0000
			else
				msg = "["..((players[pid] and players[pid].name and (players[pid].name.." #"..pid)) or pid).."/"..mtyp.."]: "..stripnul(pkt)
				local plr = players[pid]
				if mtyp == 0 then
					col = 0xFFFFFFFF
				elseif pid >= 32 or not plr then
					col = 0xFFFFFF00
				elseif plr.team == 0 then
					col = 0xFF0000FF
				elseif plr.team == 1 then
					col = 0xFF00FF00
				else
					col = 0xFF000000
				end
			end
			local i
			for i=1,10-1 do
				chat_backlog[i] = chat_backlog[i+1]
			end
			chat_backlog[10] = {col, msg}
		elseif typ == 0x12 then
			-- map start
			-- TODO: start loading the map gradually - this'll need a fixup in the tunnel
		elseif typ == 0x14 then
			-- player left
			local pid
			pid, pkt = common.net_unpack("B", pkt)
			local plr = players[pid]
			plr.alive = false
			plr.spawned = false
			plr.team = -2
			print("player #"..pid.." \""..(plr.name or "<NONE>").."\" disconnected")
		else
			print(string.format("packet id %02X length %i bytes", typ, #pkt))
		end
	end
end

function client.hook_tick(sec_current, sec_delta)
	if g_sec_delay > 0 then
		g_sec_delay = g_sec_delay - 1
	else
		g_sec_current = g_sec_current
		g_sec_delta = g_sec_delta
	end

	-- handle network
	handle_network(sec_current, sec_delta)

	-- handle players
	last_tick = last_tick or sec_current
	while last_tick <= sec_current do
		local i
		for i=0,63 do
			local plr = players[i]
			if plr then
				plr.tick(last_tick, PHY_TICK)
			end
		end
		last_tick = last_tick + PHY_TICK
	end

	-- send more stuff if necessary
	local plr = nil
	if players.current ~= -1 and players[players.current].team == -2 then
		plr = players[players.current]
		plr.team = -3
		local cteam = -1
		common.net_send(nil, common.net_pack("BBbBBIBBBz", 0x09,
			players.current, cteam, 0, 2, 0x1CEBA11, 255, 0, 255, nick))
	end

	-- update tracers
	tracers_tick(sec_current, sec_delta)

	-- get player
	plr = players[players.current]
	camx, camy, camz = plr.camx, plr.camy, plr.camz

	-- set keys
	plr.mvu = ktab[SDLK_w]
	plr.mvd = ktab[SDLK_s]
	plr.mvl = ktab[SDLK_a]
	plr.mvr = ktab[SDLK_d]
	plr.set_crouch(ktab[SDLK_LCTRL])
	plr.jumping = (plr.team == -1 or not plr.airborne) and ktab[SDLK_SPACE]
	plr.sprinting = ktab[SDLK_LSHIFT]
	plr.sneaking = ktab[SDLK_v]

	-- update flags and other things
	plr.updateflags(sec_current)

	-- adjust angle
	local spda = math.pi*2*sec_delta
	if ktab[SDLK_DOWN] then camax = camax + spda/2 end
	if ktab[SDLK_UP] then camax = camax - spda/2 end
	if ktab[SDLK_LEFT] then camay = camay + spda end
	if ktab[SDLK_RIGHT] then camay = camay - spda end

	camax = math.max(-math.asin(0.99), math.min(math.asin(0.99), camax))

	-- calculate forward vector
	fwx = math.sin(camay) * math.cos(camax)
	fwy = math.sin(camax)
	fwz = math.cos(camay) * math.cos(camax)

	if plr then
		plr.fwx, plr.fwy, plr.fwz = fwx, fwy, fwz
	end

	-- set camera
	local splr = spec_player and players[spec_player]
	if splr and splr.camx then
		client.camera_point_sky(splr.fwx, splr.fwy, splr.fwz, 1.0, skx, sky, skz)
		client.camera_move_to(splr.camx, splr.camy + splr.jerkoffs, splr.camz)
	else
		client.camera_point_sky(fwx, fwy, fwz, 1.0, skx, sky, skz)
		client.camera_move_to(camx, camy + plr.jerkoffs, camz)
	end

	return 0.005
end

function client.hook_render()
	-- get camera vars
	local camx, camy, camz
	local fwx, fwy, fwz
	camx, camy, camz = client.camera_get_pos()
	fwx, fwy, fwz = client.camera_get_forward()

	-- show heads
	local i
	for i=0,31 do
		local plr = players[i]
		local invy = math.sqrt(1 - plr.fwy)
		local xa = -math.asin(plr.fwy)
		local ya = math.atan2(plr.fwx/invy, plr.fwz/invy)
		if plr.team >= 0 and plr.team <= 1 and plr.spawned then
			local team = teams[plr.team]
			local camy = plr.camy + plr.jerkoffs
			if plr.alive then
				if i ~= players.current and i ~= spec_player then
					--print(plr.camx, camy, plr.camz)
					client.model_render_bone_global(team.models.playerhead, 0,
						plr.camx, camy, plr.camz, 0.0, xa, ya, 2.0)
					if plr.crouching then
						client.model_render_bone_global(team.models.playertorsoc, 0,
							plr.camx, camy, plr.camz, 0.0, 0.0, ya, 2.0)
						client.model_render_bone_global(team.models.playerlegc, 0,
							plr.camx-plr.fwz*0.2/invy-plr.fwx*0.5/invy, camy+0.5, plr.camz+plr.fwx*0.2/invy-plr.fwz*0.5/invy, 0.0, 0.0, ya, 2.0)
						client.model_render_bone_global(team.models.playerlegc, 0,
							plr.camx+plr.fwz*0.2/invy-plr.fwx*0.5/invy, camy+0.5, plr.camz-plr.fwx*0.2/invy-plr.fwz*0.5/invy, 0.0, 0.0, ya, 2.0)
					else
						client.model_render_bone_global(team.models.playertorso, 0,
							plr.camx, camy, plr.camz, 0.0, 0.0, ya, 2.0)
						client.model_render_bone_global(team.models.playerleg, 0,
							plr.camx-plr.fwz*0.2/invy, camy+1.0, plr.camz+plr.fwx*0.2/invy, 0.0, 0.0, ya, 2.0)
						client.model_render_bone_global(team.models.playerleg, 0,
							plr.camx+plr.fwz*0.2/invy, camy+1.0, plr.camz-plr.fwx*0.2/invy, 0.0, 0.0, ya, 2.0)
					end
					client.model_render_bone_global(team.models.playerarms, 0,
						plr.camx, camy+0.5, plr.camz, 0.0, xa, ya, 2.0)
				end

				local mdl = nil

				if plr.tool == 0 then mdl = MODELS.spade
				elseif plr.tool == 1 then mdl = MODELS.block
				elseif plr.tool == 2 then
					if plr.gun == 0 then mdl = MODELS.semi
					elseif plr.gun == 1 then mdl = MODELS.smg
					elseif plr.gun == 2 then mdl = MODELS.shotgun
					end
				elseif plr.tool == 3 then mdl = MODELS.grenade
				end

				if mdl then
					client.model_render_bone_global(mdl, 0,
						plr.camx+plr.fwx*1.0-plr.fwz*0.5/invy, camy+plr.fwy*1.0+0.5, plr.camz+plr.fwz*1.0+plr.fwx*0.5/invy, 0.0, xa, ya, 1.0)
				end
			else
				client.model_render_bone_global(team.models.playerdead, 0,
					plr.camx, camy+2.0, plr.camz, 0.0, 0.0, ya, 2.0)
			end
		end
	end

	-- show tracers
	tracers_render()

	local w,h
	w,h = client.screen_get_dims()

	local sdx, sdy, sdz
	local upx, upy, upz
	-- calculate side vector
	sdx = fwy * skz - fwz * sky
	sdy = fwz * skx - fwx * skz
	sdz = fwx * sky - fwy * skx

	-- calculate up vector
	upx = fwy * sdz - fwz * sdy
	upy = fwz * sdx - fwx * sdz
	upz = fwx * sdy - fwy * sdx

	-- calculate vector lengths
	local sdd = math.sqrt(sdx*sdx + sdy*sdy + sdz*sdz)
	local upd = math.sqrt(upx*upx + upy*upy + upz*upz)

	-- normalise vectors
	sdx = sdx / sdd
	sdy = sdy / sdd
	sdz = sdz / sdd
	upx = upx / upd
	upy = upy / upd
	upz = upz / upd

	-- names
	local i
	local cplr = players[players.current]
	for i=0,63 do
		local plr = players[i]
		if i ~= players.current and plr.spawned and plr.camx and (cplr.team == -1 or cplr.team == plr.team) and plr.team >= 0 then
			local name = "["..plr.name.." #"..i.."]"

			local x,y,z
			x,y,z = plr.camx, plr.camy, plr.camz
			if not plr.alive then y = y + 2.0 end
			y = y - 0.8

			x = x - camx
			y = y - camy
			z = z - camz

			-- get on-screen pos
			local nx,ny,nz
			--[[
			nx = sdx * x + upx * y + fwx * z
			ny = sdy * x + upy * y + fwy * z
			nz = sdz * x + upz * y + fwz * z
			]]
			nx = sdx * x + sdy * y + sdz * z
			ny = upx * x + upy * y + upz * z
			nz = fwx * x + fwy * y + fwz * z

			if nz > 0.01 then
				local sx, sy
				sx = -nx/nz*w/2 + w/2
				sy = ny/nz*w/2 + h/2
				
				draw_text(sx-4*#name, sy, 0xFFAAAAAA, name)
			end
		end
	end

	-- GUI!

	if is_typing then
		draw_text(8, h-20, 0xFFFFFFFF, (chat_type == 1 and "Team:") or "Global:")
		draw_text(8, h-20+8, 0xFFFFFFFF, chat_text.."_")
	end

	if spec_player then
		local plr = players[spec_player]
		local m = "Specating: #"..spec_player.." ["..((plr and plr.name) or "UNDEF!").."]"
		draw_text(w/2-4*#m, 4, 0xFFFFFFFF, m)
	end

	local i
	for i=1,10 do
		local l,c,m
		l = chat_backlog[i]
		if l then
			c, m = l[1], l[2]
			draw_text(8, h-30-(i-1)*8, c, m)
		end
	end
end

