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

// let's get some decent weapons going on here
// TODO: an actual API for stuff

// here's a quick test, by the way
void main(int plrid, string &in s)
{
	print("This is a test script that prints things.\nIt's a placeholder for when we can finally script this thing.\n");
	print("By the way, you are player #" + plrid + ".\n");
	print("MOTD: [" + s + "]\n");
	// TODO: document all this stuff:
	int i;

	/* not recommended (it sets off the rapid hack detector) but it CAN be done!
	for(i = 0; i < 6; i++)
		gun_set_field(i, "block_dmg", 100);
	*/
}

void on_spawn()
{
	print("Spawning! Yay!\n");
}

