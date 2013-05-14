/*
Because of compatibility issues I cannot licence this under GPL.

Copyright (c) 2013, GreaseMonkey + other pysnip contributors

This software is provided 'as-is', without any express or implied
warranty. In no event will the authors be held liable for any damages
arising from the use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it
freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not
claim that you wrote the original software. If you use this software
in a product, an acknowledgment in the product documentation would be
appreciated but is not required.

2. Altered source versions must be plainly marked as such, and must not be
misrepresented as being the original software.

3. This notice may not be removed or altered from any source
distribution.
*/

void main(int tmp_pid)
{
	// The player ID isn't set at this stage.
	print("Player ID = " + tmp_pid + "\n");
	player_t @p = player_get(tmp_pid);

	/*
	// Don't do this unless you properly update the information in the server scripts
	gun_t @rifle = gun_get(3);
	rifle.ammo_clip = 50;
	rifle.ammo_reserve = 200;
	rifle.shot_time = 0.05;
	rifle.recoil_x *= 0.1;
	rifle.recoil_y *= 0.1;
	*/
}

void set_name(int plrid, string &in s)
{
	player_t @p = player_get(plrid);
	print("* Player " + p.name + " is now known as " + s + "\n");
	p.name = s;
}

// TODO: implement zoom
void point_forward(player_t @p, float fx, float fy, float fz, float zoom, float sx = 0.0, float sy = 0.0, float sz = -1.0)
{
	float hx,hy,hz;
	float vx,vy,vz;
	float fd,hd,vd;

	hx = fy*sz - fz*sy;
	hy = fz*sx - fx*sz;
	hz = fx*sy - fy*sx;

	vx = fy*hz - fz*hy;
	vy = fz*hx - fx*hz;
	vz = fx*hy - fy*hx;

	fd = sqrt(fx*fx + fy*fy + fz*fz);
	hd = sqrt(hx*hx + hy*hy + hz*hz);
	vd = sqrt(vx*vx + vy*vy + vz*vz);

	fx /= fd; fy /= fd; fz /= fd;
	hx /= hd; hy /= hd; hz /= hd;
	vx /= vd; vy /= vd; vz /= vd;

	p.camyx = fx; p.camyy = fy; p.camyz = fz;
	p.camxx = hx; p.camxy = hy; p.camxz = hz;
	p.camzx = vx; p.camzy = vy; p.camzz = vz;
}

void point_at(player_t @p, float tx, float ty, float tz, float zoom)
{
	float dx = tx - p.p1x;
	float dy = ty - p.p1y;
	float dz = tz - p.p1z;

	float l = sqrt(dx*dx + dy*dy + dz*dz);
	if(l < 0.0001)
		return; // this will break if we do it.
	
	point_forward(p, dx, dy, dz, zoom);
}

void on_spawn()
{
	print("SPAWN\n");
}

// roughly the BPM of the "fr-025: the.popular.demo" soundtrack
bool popmod = false;
float cycspeed = 3.14159265358979323846264 * 1.0 * 130.5 / 60.0;

int plrrot = 0;
void syh_tick(float tick)
{
	player_t @p = player_get(curplr);

	// If you like to make people feel sick, try this! --GM
	float drunk_strength = (100 - (p.health < 0 ? 0 : p.health > 100 ? 100 : p.health))/100.0;
	if(p.alive != 0)
		point_forward(p, p.camyx, p.camyy, p.camyz, 1.0, -p.camzx+sin(tick*drunk_strength*3.0)*drunk_strength, -p.camzy+cos(tick*drunk_strength*3.0)*drunk_strength, -p.camzz-1.0);
	
	// Hack for 64 player support to work fully
	// Note, this WILL mean that the tools will probably show up wrong first time.
	player_t @m0 = null;
	player_t @m1 = null;
	for(int i = 0; i < 64; i++)
	{
		player_t @p = player_get(i);
		if(p.exists != 0)
		{
			bool ok = true;
			for(int j = 0; ok && j < 8; j++)
				if(@p.bones[j].kv6 == null)
				{
					if(p.team == 0)
						@p.bones[j].kv6 = @m0.bones[j].kv6;
					else if(p.team == 1)
						@p.bones[j].kv6 = @m1.bones[j].kv6;
					else
						ok = false;
				}

			if(ok)
			{
				if(p.team == 0 && @m0 == null)
					@m0 = @p;
				else if(p.team == 1 && @m1 == null)
					@m1 = @p;
			}
		}
	}

	if(popmod)
	{
		// LET'S ALL BOB HEADS (model 6)
		// size: 6, 6, 6
		// pivot: 2.5, 5.5, 5.5

		float ang = cycspeed*tick;
		float sa = sin(ang);
		if(sa < 0.0) sa = -sa;
		sa = 1.0 - (1.0 - sa)*(1.0 - sa);
		float px = 2.5;
		float py = 2.5 - 3.0 + 3.0*sa;
		float pz = 2.5 + 3.0*sa;
		
		if(@m0 != null)
		{
			m0.bones[6].kv6.xpiv = px;
			m0.bones[6].kv6.ypiv = py;
			m0.bones[6].kv6.zpiv = pz;
		}
		
		if(@m1 != null)
		{
			m1.bones[6].kv6.xpiv = px;
			m1.bones[6].kv6.ypiv = py;
			m1.bones[6].kv6.zpiv = pz;
		}

		// The Popular Model
		for(int i = 1; i < 7; i++)
		{
			if(@m0 != null)
				for(uint j = 0; j < m0.bones[i].kv6.numvoxs; j++)
					m0.bones[i].kv6.vox[j].col = 0x807777AA;
			if(@m1 != null)
				for(uint j = 0; j < m1.bones[i].kv6.numvoxs; j++)
					m1.bones[i].kv6.vox[j].col = 0x8077AA77;
		}
	}
}

void syh_chat(int type, const string &in msg)
{
	if(msg == "/$popmod")
	{
		popmod = true;
	} else {
		chat(type, msg);
	}
}

