import shlex
from pyspades.common import *

class InvalidPlayer(Exception):
    pass

class InvalidSpectator(InvalidPlayer):
    pass

class InvalidTeam(Exception):
    pass

def parse_command(input):
    value = encode(input)
    try:
        splitted = shlex.split(value)
    except ValueError:
        # shlex failed. let's just split per space
        splitted = value.split(' ')
    if splitted:
        command = splitted.pop(0)
    else:
        command = ''
    splitted = [decode(value) for value in splitted]
    return decode(command), splitted

def get_player(protocol, value, spectators = True):
    ret = None
    try:
        if value.startswith('#'):
            value = int(value[1:])
            ret = protocol.players[value]
        else:
            players = protocol.players
            try:
                ret = players[value]
            except KeyError:
                value = value.lower()
                for player in players.values():
                    name = player.name.lower()
                    if name == value:
                        return player
                    if name.count(value):
                        ret = player
    except (KeyError, IndexError, ValueError):
        pass
    if ret is None:
        raise InvalidPlayer()
    elif not spectators and ret.world_object is None:
        raise InvalidSpectator()
    return ret

def get_team(connection, value):
    value = value.lower()
    if value == 'blue':
        return connection.protocol.blue_team
    elif value == 'green':
        return connection.protocol.green_team
    elif value == 'spectator':
        return connection.protocol.spectator_team
    raise InvalidTeam()

def join_arguments(arg, default = None):
    if not arg:
        return default
    return ' '.join(arg)

def parse_maps(pre_maps):
    maps = []
    for n in pre_maps:
        if n[0]=="#" and len(maps)>0:
            maps[-1] += " "+n
        else:
            maps.append(n)
    
    return maps, ', '.join(maps)
