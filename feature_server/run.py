# Copyright (c) Mathias Kaerlev 2011.

# This file is part of pyspades.

# pyspades is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# pyspades is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with pyspades.  If not, see <http://www.gnu.org/licenses/>.

"""
pyspades - default/featured server
"""

import sys

frozen = hasattr(sys, 'frozen')

if frozen:
    CLIENT_VERSION = int(open('client_version', 'rb').read())
else:
    sys.path.append('..')
    from pyspades.common import crc32
    CLIENT_VERSION = crc32(open('../data/client.exe', 'rb').read())

if sys.platform == 'win32':
    # install IOCP
    try:
        from twisted.internet import iocpreactor 
        iocpreactor.install()
    except ImportError:
        print '(dependencies missing for fast IOCP, using normal reactor)'

if sys.version_info < (2, 7):
    try:
        import psyco
        psyco.full()
    except ImportError:
        print '(optional: install psyco for optimizations)'

import pyspades.debug
from pyspades.server import (ServerProtocol, ServerConnection,
                            position_data, orientation_data, grenade_packet,
                            block_action, set_color, intel_action)
from pyspades.serverloaders import PositionData
from map import Map
from twisted.internet import reactor
from twisted.internet.task import LoopingCall
from twisted.python import log
from pyspades.common import encode, decode, make_color, coordinates
from pyspades.constants import *
from pyspades.collision import distance_3d_vector

import json
import random
import time
import commands
import copy

def writelines(fp, lines):
    for line in lines:
        fp.write(line + "\r\n")

class FeatureConnection(ServerConnection):
    admin = False
    last_votekick = None
    mute = False
    login_retries = None
    god = False
    follow = None
    followable = True
    aux = None
    streak = 0
    best_streak = 0
    airstrike = False
    
    def on_join(self):
        if self.protocol.motd is not None:
            self.send_lines(self.protocol.motd)
    
    def on_login(self, name):
        self.protocol.send_chat('%s entered the game!' % name)
        print '%s (%s) entered the game!' % (name, self.address[0])
        self.protocol.irc_say('* %s entered the game' % name)
    
    def disconnect(self):
        self.drop_followers()
        if self.name is not None:
            self.protocol.send_chat('%s left the game' % self.name)
            print self.name, 'disconnected!'
            self.protocol.irc_say('* %s disconnected' % self.name)
            if self.protocol.votekick_player is self:
                self.protocol.end_votekick(False, 'Player left the game')
        ServerConnection.disconnect(self)
    
    def on_spawn(self, pos, name):
        if self.follow is not None:
            self.set_location(self.get_follow_location())
    
    def on_command(self, command, parameters):
        log_message = '<%s> /%s %s' % (self.name, command, 
            ' '.join(parameters))
        result = commands.handle_command(self, command, parameters)
        if result is not None:
            log_message += ' -> %s' % result
            self.send_chat(result)
        print log_message
    
    def on_block_build(self, x, y, z):
        if self.god:
            self.refill()
        elif not self.protocol.building:
            return False
        elif self.protocol.user_blocks is not None:
            self.protocol.user_blocks.add((x, y, z))
    
    def on_block_destroy(self, x, y, z, mode):
        if not self.god:
            if not self.protocol.building:
                return False
            elif (self.protocol.indestructable_blocks or
                self.protocol.user_blocks is not None):
                is_indestructable = self.protocol.is_indestructable
                if mode == DESTROY_BLOCK:
                    if is_indestructable(x, y, z):
                        return False
                elif mode == SPADE_DESTROY:
                    if (is_indestructable(x, y, z) or
                    is_indestructable(x, y, z + 1) or
                    is_indestructable(x, y, z - 1)):
                        return False
                elif mode == GRENADE_DESTROY:
                    for nade_x in xrange(x - 1, x + 2):
                        for nade_y in xrange(y - 1, y + 2):
                            for nade_z in xrange(z - 1, z + 2):
                                if is_indestructable(nade_x, nade_y, nade_z):
                                    return False
    
    def on_block_color(self, (r, g, b)):
        if (self.protocol.rollback_in_progress and
            self.protocol.rollbacking_player is self):
            return False
    
    def on_hit(self, hit_amount, player):
        if not self.protocol.killing:
            self.send_chat("You can't kill anyone right now! Damage is turned OFF")
            return False
        elif player.god:
            self.send_chat("You can't hurt %s! That player is in *god mode*" %
                player.name)
            return False
        if self.god:
            self.protocol.send_chat("%s, killing in god mode is forbidden!" %
                self.name, irc = True)
            self.protocol.send_chat('%s returned to being a mere human.' %
                self.name, irc = True)
            self.god = False
    
    def on_grenade(self, time_left):
        if not self.protocol.killing:
            return False
        if self.god:
            self.refill()
    
    def on_team_join(self, team):
        if team.locked:
            self.send_chat('Team is locked.')
            return False
        balanced_teams = self.protocol.balanced_teams
        if balanced_teams:
            other_team = team.other
            if other_team.count() < team.count() + 1 - balanced_teams:
                self.send_chat('Team is full. Please join the other team')
                return False
        if self.team is not team:
            self.drop_followers()
            self.follow = None
            self.respawn_time = self.protocol.respawn_time
    
    def on_chat(self, value, global_message):
        message = '<%s> %s' % (self.name, value)
        if self.mute:
            message = '(MUTED) %s' % message
        elif global_message:
            self.protocol.irc_say('<%s> %s' % (self.name, value))
        print message
        if self.mute:
            self.send_chat('(Chat not sent - you are muted)')
            return False
    
    def on_kill(self, killer):
        self.streak = 0
        self.airstrike = False
        if killer is None:
            return
        killer.streak += 1
        killer.best_streak = max(killer.streak, killer.best_streak)
    
    def add_score(self, score):
        self.kills += score
        if not self.protocol.airstrikes:
            score_met = (self.kills >= self.protocol.airstrike_min_score_req)
            streak_met = (self.streak >= self.protocol.airstrike_streak_req)
            give_strike = False
            if not score_met:
                return
            if self.kills - score < self.protocol.airstrike_min_score_req:
                self.send_chat('You have unlocked airstrike support!')
                self.send_chat('Each 10-kill streak will clear you for one '
                               'airstrike.')
                if streak_met:
                    give_strike = True
            if not streak_met:
                return
            if (self.streak % self.protocol.airstrike_streak_req == 0 or
                give_strike):
                self.send_chat('Airstrike support ready! Launch with e.g. '
                                 '/airstrike B4')
                self.airstrike = True
                intel_action.action_type = 4
                self.send_contained(intel_action)
    
    def get_followers(self):
        return [player for player in self.protocol.players.values()
            if player.follow is self]
    
    def drop_followers(self):
        for player in self.get_followers():
            player.follow = None
            player.respawn_time = player.protocol.respawn_time
            player.send_chat('You are no longer following %s.' % self.name)
    
    def get_follow_location(self):
        x, y, z = (self.follow.position.get() if self.follow.hp else
            self.team.get_random_location())
        z -= 2
        return x, y, z
    
    def kick(self, reason = None, silent = False):
        if not silent:
            if reason is not None:
                message = '%s was kicked: %s' % (self.name, reason)
            else:
                message = '%s was kicked' % self.name
            self.protocol.send_chat(message, irc = True)
        self.disconnect()
    
    def ban(self, reason = None):
        if reason is not None:
            message = '%s banned: %s' % (self.name, reason)
        else:
            message = '%s banned' % self.name
        self.protocol.send_chat(message, irc = True)
        self.protocol.add_ban(self.address[0])
    
    def send_lines(self, lines):
        current_time = 0
        for line in lines:
            reactor.callLater(current_time, self.send_chat, line)
            current_time += 2
    
    # position methods
    
    def get_location(self):
        position = self.position
        return position.x, position.y, position.z
    
    def set_location(self, (x, y, z)):
        position_data.x = x
        position_data.y = y
        position_data.z = z
        position_data.player_id = self.player_id
        self.protocol.send_contained(position_data)
    
    def desync_grenade(self, x, y, z, orientation_x, fuse):
        """Gives the appearance of a grenade appearing from thin air by moving
        an auxiliary player to the target location and then back"""
        new_position = PositionData()
        new_position.set((x, y, z), self.player_id)
        orientation_data.set((orientation_x, 0.0, 0.0), self.player_id)
        grenade_packet.value = fuse
        grenade_packet.player_id = self.player_id
        old_position = PositionData()
        old_position.set(self.get_location(), self.player_id)
        packets = [new_position, orientation_data, grenade_packet, old_position]
        if self.aux is None:
            self.aux = self.find_aux_connection()
        if self.aux is not self:
            for packet in packets:
                self.protocol.send_contained(packet, sender = self)
            for packet in packets:
                packet.player_id = self.aux.player_id
                self.protocol.send_contained(packet, target = self)
        else:
            for packet in packets:
                self.protocol.send_contained(packet)
    
    def find_aux_connection(self):
        """Attempts to find an allied player far away, preferrably dead,
        so that we don't see it flipping out right in front of us"""
        best = None
        best_distance = 0.0
        for player in self.team.get_players():
            distance = distance_3d_vector(self.position, player.position)
            if best is None or player.hp <= 0 and best.hp > 0:
                best, best_distance = player, distance
                continue
            if player.hp > 0 and best.hp <= 0:
                continue
            if distance > best_distance:
                best, best_distance = player, distance
        return best
    
    # airstrike
    
    def start_airstrike(self, value = None):
        if not self.protocol.airstrikes:
            return
        if value is None and (self.god or self.airstrike):
            return 'Airstrike support ready! Use with e.g. /airstrike A1'
        if not self.god:
            if self.kills < self.protocol.airstrike_min_score_req:
                return ('You need a total score of %s to unlock airstrikes!' %
                    self.protocol.airstrike_min_score_req)
            elif not self.airstrike:
                kills_left = self.protocol.airstrike_streak_req - (self.streak %
                    self.protocol.airstrike_streak_req)
                return ('%s kills left for airstrike clearance!' % kills_left)
        try:
            x, y = coordinates(value)
        except (ValueError):
            return "Bad coordinates: should be like 'A4', 'G5'. Look them up in the map."
        self.airstrike = False
        self.protocol.send_chat('Ally %s called in an airstrike on '
            'location %s' % (self.name, value.upper()), global_message = False,
            team = self.team)
        self.protocol.send_chat('[WARNING] Enemy air support heading to %s!' %
            value.upper(), global_message = False, team = self.team.other)
        reactor.callLater(3.0, self.do_airstrike, x, y)
    
    def do_airstrike(self, start_x, start_y):
        z = 1
        self.aux = self.find_aux_connection()
        orientation_x = [1.0, -1.0][self.team.id]
        start_x = max(0, min(512, start_x + [-64, 64][self.team.id]))
        increment_x = [5, -5][self.team.id]
        for round in xrange(12):
            x = start_x + random.randrange(64)
            y = start_y + random.randrange(64)
            fuse = self.protocol.map.get_height(x, y) * 0.036
            for i in xrange(5):
                x += increment_x
                time = round * 0.7 + i * 0.14
                reactor.callLater(time, self.desync_grenade, x, y, z,
                    orientation_x, fuse)

def encode_lines(value):
    if value is not None:
        lines = []
        for line in value:
            lines.append(encode(line))
        return lines

def make_range_object(value):
    if len(value) == 1:
        return xrange(value, value + 1)
    return xrange(value[0], value[1])

class FeatureProtocol(ServerProtocol):
    connection_class = FeatureConnection
    version = CLIENT_VERSION
    admin_passwords = None
    bans = None
    temp_bans = None
    irc_relay = None
    balanced_teams = None
    timestamps = None
    building = True
    killing = True
    remote_console = None
    
    # votekick
    votekick_time = 60 # 1 minute
    votekick_interval = 3 * 60 # 3 minutes
    votekick_percentage = 25.0
    votekick_max_percentage = 40.0 # too many no-votes?
    votes_left = None
    votekick_player = None
    voting_player = None
    votes = None
    
    # rollback
    rollback_in_progress = False
    rollback_max_rows = 10 # per 'cycle', intended to cap cpu usage
    rollback_max_packets = 180 # per 'cycle' cap for (unique packets * players)
    rollback_max_unique_packets = 12 # per 'cycle', each block op is at least 1
    rollback_time_between_cycles = 0.06
    rollback_time_between_progress_updates = 10.0
    rollbacking_player = None
    rollback_map = None
    rollback_start_time = None
    rollback_last_chat = None
    rollback_rows = None
    rollback_total_rows = None
    # debug
    rollback_hit_max_rows = None
    rollback_hit_max_unique_packets = None
    rollback_hit_max_packets = None
    
    # airstrike
    airstrikes = True
    airstrike_min_score_req = 15
    airstrike_streak_req = 6
    
    map_info = None
    indestructable_blocks = None
    spawns = None
    user_blocks = None
    
    def __init__(self):
        try:
            config = json.load(open('config.txt', 'rb'))
        except IOError, e:
            raise SystemExit('no config.txt file found')
        try:
            self.bans = set(json.load(open('bans.txt', 'rb')))
        except IOError:
            self.bans = set([])
        self.temp_bans = set([])
        self.config = config
        self.name = config.get('name', 
            'pyspades server %s' % random.randrange(0, 2000))
        try:
            map = Map(config['map'])
            self.map = map.data
            self.map_info = map
            self.rollback_map = Map(config['map']).data
        except KeyError:
            raise SystemExit('no map specified!')
            return
        except IOError:
            raise SystemExit('map not found!')
            return
        
        self.indestructable_blocks = indestructable_blocks = []
        for r, g, b in map.indestructable_blocks:
            r = make_range_object(r)
            g = make_range_object(g)
            b = make_range_object(b)
            indestructable_blocks.append((r, g, b))
        
        self.max_scores = config.get('cap_limit', None)
        self.respawn_time = config.get('respawn_time', 5)
        self.follow_respawn_time = config.get('follow_respawn_time',
            self.respawn_time)
        self.master = config.get('master', True)
        self.friendly_fire = config.get('friendly_fire', True)
        self.motd = self.format_lines(config.get('motd', None))
        self.help = self.format_lines(config.get('help', None))
        self.tips = self.format_lines(config.get('tips', None))
        self.tip_frequency = config.get('tip_frequency', 0)
        if self.tips is not None and self.tip_frequency > 0:
            reactor.callLater(self.tip_frequency * 60, self.send_tip)
        self.max_players = config.get('max_players', 20)
        passwords = config.get('passwords', {})
        self.admin_passwords = passwords.get('admin', [])
        self.server_prefix = encode(config.get('server_prefix', '[*]'))
        self.balanced_teams = config.get('balanced_teams', None)
        self.rules = self.format_lines(config.get('rules', None))
        self.login_retries = config.get('login_retries', 1)
        self.votekick_ban_duration = config.get('votekick_ban_duration', 5)
        if config.get('user_blocks_only', False):
            self.user_blocks = set()
        self.rollback_on_game_end = config.get('rollback_on_game_end', False)
        self.max_followers = config.get('max_followers', 3)
        logfile = config.get('logfile', None)
        ssh = config.get('ssh', {})
        if ssh.get('enabled', False):
            from ssh import RemoteConsole
            self.remote_console = RemoteConsole(self, ssh)
        irc = config.get('irc', {})
        if irc.get('enabled', False):
            from irc import IRCRelay
            self.irc_relay = IRCRelay(self, irc)
        status = config.get('status_server', {})
        if status.get('enabled', False):
            from statusserver import StatusServerFactory
            self.status_server = StatusServerFactory(self, status)
                    
        if logfile is not None and logfile.strip():
            observer = log.FileLogObserver(open(logfile, 'a'))
            log.addObserver(observer.emit)
            log.msg('pyspades server started on %s' % time.strftime('%c'))
        log.startLogging(sys.stdout) # force twisted logging
            
        for password in self.admin_passwords:
            if password == 'replaceme':
                print 'REMEMBER TO CHANGE THE DEFAULT ADMINISTRATOR PASSWORD!'
                break
        ServerProtocol.__init__(self)
        # locked teams
        self.blue_team.locked = False
        self.green_team.locked = False
    
    def is_indestructable(self, x, y, z):
        if self.user_blocks is not None:
            if (x, y, z) not in self.user_blocks:
                return True
        if self.indestructable_blocks:
            r, g, b = self.map.get_point(x, y, z)[1][:-1]
            for r_range, g_range, b_range in self.indestructable_blocks:
                if r in r_range and g in g_range and b in b_range:
                    return True
        return False
    
    def format_lines(self, value):
        if value is None:
            return
        map = self.map_info
        format_dict = {
            'server_name' : self.name,
            'map_name' : map.name,
            'map_author' : map.author,
            'map_description' : map.description
        }
        lines = []
        for line in value:
            lines.append(encode(line % format_dict))
        return lines
        
    def got_master_connection(self, *arg, **kw):
        print 'Master connection established.'
        ServerProtocol.got_master_connection(self, *arg, **kw)
    
    def master_disconnected(self, *arg, **kw):
        print 'Master connection lost, reconnecting...'
        ServerProtocol.master_disconnected(self, *arg, **kw)
    
    def add_ban(self, ip, temporary = False):
        for connection in self.connections.values():
            if connection.address[0] == ip:
                connection.kick(silent = True)
        if not temporary:
            self.bans.add(ip)
            json.dump(list(self.bans), open('bans.txt', 'wb'))
    
    def datagramReceived(self, data, address):
        if address[0] in self.bans or address[0] in self.temp_bans:
            return
        ServerProtocol.datagramReceived(self, data, address)
        
    def irc_say(self, msg):
        if self.irc_relay:
            self.irc_relay.send(msg)
    
    def send_tip(self):
        line = self.tips[random.randrange(len(self.tips))]
        self.send_chat(line)
        reactor.callLater(self.tip_frequency * 60, self.send_tip)
    
    # votekick
    
    def start_votekick(self, connection, player):
        if self.votes is not None:
            return 'Votekick in progress.'
        last_votekick = connection.last_votekick
        if (last_votekick is not None and 
        reactor.seconds() - last_votekick < self.votekick_interval):
            return "You can't start a votekick now."
        votes_left = int((len(self.players) / 100.0
            ) * self.votekick_percentage)
        if votes_left == 0:
            return 'Not enough players on server.'
        self.votes_left = votes_left
        self.votes = {connection : True}
        votekick_time = self.votekick_time
        self.votekick_call = reactor.callLater(votekick_time, 
            self.end_votekick, False, 'Votekick timed out')
        self.send_chat('%s initiated a VOTEKICK against player %s. '
            'Say /y to agree and /n to decline.' % (connection.name, 
            player.name), sender = connection)
        self.irc_say(
            '* %s initiated a votekick against player %s.' % (connection.name, 
            player.name))
        self.votekick_player = player
        self.voting_player = connection
        return 'You initiated a votekick. Say /cancel to stop it at any time.'
    
    def votekick(self, connection, value):
        if self.votes is None or connection in self.votes:
            return
        if value:
            self.votes_left -= 1
        else:
            self.votes_left += 1
        max = int((len(self.players) / 100.0) * self.votekick_max_percentage)
        if self.votes_left >= max:
            self.votekick_call.cancel()
            self.end_votekick(False, 'Too many negative votes')
            return
        self.votes[connection] = value
        if self.votes_left > 0:
            self.send_chat('%s voted %s. %s more players required.' % (
                connection.name, ['NO', 'YES'][int(value)], self.votes_left))
        else:
            self.votekick_call.cancel()
            self.end_votekick(True, 'Player kicked')
    
    def cancel_votekick(self, connection):
        if self.votes is None:
            return 'No votekick in progress.'
        if not connection.admin and connection is not self.voting_player:
            return 'You did not start the votekick.'
        self.votekick_call.cancel()
        self.end_votekick(False, 'Cancelled by %s' % connection.name)
    
    def end_votekick(self, enough, result):
        victim = self.votekick_player
        self.votekick_player = None
        self.send_chat('Votekick for %s has ended. %s.' % (victim.name, result),
            irc = True)
        if enough:
            if self.votekick_ban_duration:
                self.add_ban(victim.address[0], temporary = True)
                self.temp_bans.add(victim.address[0])
                reactor.callLater(self.votekick_ban_duration * 60,
                    self.temp_bans.discard, victim.address[0])
            else:
                victim.kick(silent = True)
        elif not self.voting_player.admin: # admins are powerful, yeah
            self.voting_player.last_votekick = reactor.seconds()
        self.votes = self.votekick_call = None
        self.voting_player = None
    
    # rollback
    
    def start_rollback(self, connection, filename,
                       start_x, start_y, end_x, end_y):
        if self.rollback_in_progress:
            return 'Rollback in progress.'
        map = self.rollback_map if filename is None else Map(filename).data
        self.send_chat('%s commenced a rollback...' %
            (connection.name if connection is not None else 'Map'), irc = True)
        if connection is None:
            for player in self.players.values():
                connection = player
                if player.admin:
                    break
        packet_generator = self.create_rollback_generator(connection,
            self.map, map, start_x, start_y, end_x, end_y)
        self.rollbacking_player = connection
        self.rollback_in_progress = True
        self.rollback_start_time = time.time()
        self.rollback_last_chat = self.rollback_start_time
        self.rollback_rows = 0
        self.rollback_total_rows = end_x - start_x
        self.rollback_hit_max_rows = 0
        self.rollback_hit_max_unique_packets = 0
        self.rollback_hit_max_packets = 0
        self.rollback_cycle(packet_generator)
    
    def cancel_rollback(self, connection):
        if not self.rollback_in_progress:
            return 'No rollback in progress.'
        self.end_rollback('Cancelled by %s' % connection.name)
    
    def end_rollback(self, result):
        self.rollback_in_progress = False
        self.update_entities()
        self.send_chat('Rollback ended. %s' % result, irc = True)
        self.send_chat('Caps hit: Rows %s, Packets %s, Unique %s' %
            (self.rollback_hit_max_rows, self.rollback_hit_max_packets,
            self.rollback_hit_max_unique_packets))
    
    def rollback_cycle(self, packet_generator):
        if not self.rollback_in_progress:
            return
        try:
            sent = rows = 0
            while (True):
                if rows > self.rollback_max_rows:
                    self.rollback_hit_max_rows += 1
                    break
                if sent > self.rollback_max_unique_packets:
                    self.rollback_hit_max_unique_packets += 1
                    break
                if sent * len(self.connections) > self.rollback_max_packets:
                    self.rollback_hit_max_packets += 1
                    break
                
                sent_packets = packet_generator.next()
                sent += sent_packets
                rows += (sent_packets == 0)
            self.rollback_rows += rows
            if (time.time() - self.rollback_last_chat >
                self.rollback_time_between_progress_updates):
                self.rollback_last_chat = time.time()
                progress = (float(self.rollback_rows) /
                    self.rollback_total_rows * 100.0)
                self.send_chat('Rollback progress %s%%' % int(progress),
                    irc = True)
        except (StopIteration):
            self.end_rollback('Time taken: %.2fs' % 
                float(time.time() - self.rollback_start_time))
            return
        reactor.callLater(self.rollback_time_between_cycles,
            self.rollback_cycle, packet_generator)
    
    def create_rollback_generator(self, connection, mapdata, mapdata_new,
                                  start_x, start_y, end_x, end_y):
        last_color = None
        for x in xrange(start_x, end_x):
            for y in xrange(start_y, end_y):
                for z in xrange(63):
                    packets_sent = 0
                    block_action.value = None
                    old_solid = mapdata.get_solid(x, y, z)
                    new_solid = mapdata_new.get_solid(x, y, z)
                    if old_solid and not new_solid:
                        block_action.value = DESTROY_BLOCK
                        mapdata.remove_point_unsafe(x, y, z, user = False)
                    elif not old_solid and new_solid:
                        block_action.value = BUILD_BLOCK
                        new_color = mapdata_new.get_color(x, y, z)
                        set_color.value = new_color & 0xFFFFFF
                        set_color.player_id = connection.player_id
                        if new_color != last_color:
                            last_color = new_color
                            self.send_contained(set_color, save = True)
                            packets_sent += 1
                        else:
                            connection.send_contained(set_color, save = True)
                        mapdata.set_point_unsafe_int(x, y, z, new_color)
                    
                    if block_action.value is not None:
                        block_action.x = x
                        block_action.y = y
                        block_action.z = z
                        block_action.player_id = connection.player_id
                        self.send_contained(block_action, save = True)
                        packets_sent += 1
                        yield packets_sent
            yield 0
    
    def on_reset_game(self):
        if not self.rollback_on_game_end:
            return
        self.start_rollback(self.players[0], None, 0, 0, 512, 512)
    
    def send_chat(self, value, global_message = True, sender = None,
                  team = None, irc = False):
        if irc:
            self.irc_say('* %s' % value)
        ServerProtocol.send_chat(self, value, global_message, sender, team)

PORT = 32887

reactor.listenUDP(PORT, FeatureProtocol())
print 'Started server on port %s...' % PORT
reactor.run()