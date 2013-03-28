# Copyright (c) Mathias Kaerlev 2011-2012.

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
pyspades - featured server
"""

import sys
import os
import json
import random
import shutil

for index, name in enumerate(('config.txt', 'config.txt.default')):
    try:
        config = json.load(open(name, 'rb'))
        if index != 0:
            print '(creating config.txt from %s)' % name
            shutil.copy(name, 'config.txt')
        break
    except IOError, e:
        pass
else:
    raise SystemExit('no config.txt file found')

if len(sys.argv) > 1:
    json_parameter = ' '.join(sys.argv[1:])
    config.update(eval(json_parameter))

profile = config.get('profile', False)

def get_hg_rev():
    import subprocess
    pipe = subprocess.Popen(
        ["hg", "log", "-l", "1", "--template", "{node}"],
        stdout=subprocess.PIPE, stderr = subprocess.PIPE)
    ret = pipe.stdout.read()[:12]
    if not ret:
        return '?'
    return ret

if hasattr(sys, 'frozen'):
    path = os.path.dirname(unicode(sys.executable, sys.getfilesystemencoding()))
    sys.path.append(path)
    try:
        SERVER_VERSION = 'win32 bin - rev %s' % (open('version', 'rb').read())
    except IOError:
        SERVER_VERSION = 'win32 bin'
else:
    sys.path.append('..')
    SERVER_VERSION = '%s - rev %s' % (sys.platform, get_hg_rev())

if sys.platform == 'linux2':
    try:
        from twisted.internet import epollreactor
        epollreactor.install()
    except ImportError:
        print '(dependencies missing for epoll, using normal reactor)'

if sys.version_info < (2, 7):
    try:
        import psyco
        psyco.full()
    except ImportError:
        print '(optional: install psyco for optimizations)'

from twisted.internet import reactor
from feature import FeatureConnection, FeatureProtocol, FeatureTeam

FeatureProtocol.server_version = SERVER_VERSION

# apply scripts

protocol_class = FeatureProtocol
connection_class = FeatureConnection

script_objects = []
script_names = config.get('scripts', [])
game_mode = config.get('game_mode', 'ctf')
if game_mode not in ('ctf', 'tc'):
    # must be a script with this game mode
    script_names.append(game_mode)

script_names = config.get('scripts', [])

for script in script_names[:]:
    try:
        module = __import__('scripts.%s' % script, globals(), locals(), 
            [script])
        script_objects.append(module)
    except ImportError, e:
        print "(script '%s' not found: %r)" % (script, e)
        script_names.remove(script)

for script in script_objects:
    protocol_class, connection_class = script.apply_script(protocol_class,
        connection_class, config)

protocol_class.connection_class = connection_class

protocol_instance = protocol_class(config)
print 'Started server...'

if profile:
    import cProfile
    cProfile.run('reactor.run()', 'profile.dat')
else:
    reactor.run()
