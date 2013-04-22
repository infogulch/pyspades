import json, string, os, random

random.seed = os.urandom(1024)
length = 8
chars = string.ascii_lowercase + string.digits
default_admin_password = ''.join(random.choice(chars) for i in range(length))

class LoadLoginsError(Exception):
    pass

def eval_rights(logins, user):
    user.setdefault('rights', set())
    user.setdefault('passwords', set())
    groups = user.get('groups', None)
    while groups:
        group = groups.pop()
        if group in logins:
            user['rights'].update(eval_rights(logins, logins[group]))
    return user['rights']

def get_logins(filename):
    logins = json.load(open(filename, 'rb'))
    # validate the structure of the logins dict &
    # convert arrays to sets for easier member checking
    if type(logins) != dict:
        raise LoadLoginsError("logins.txt must be a dict")
    logins.setdefault('admin', {})
    for name, login in logins.iteritems():
        if type(login) != dict:
            raise LoadLoginsError("login '%s' must be a dict" % name)
        for key in login:
            if key not in ('passwords', 'rights', 'groups'):
                raise LoadLoginsError("login '%s' has invalid key: %s" % (name, key))
            if type(login[key]) != list:
                raise LoadLoginsError("login '%s' key '%s' must be an array" % (name, key))
            login[key] = set(login[key])
    # expand rights from group membership recursively
    for name in logins:
        eval_rights(logins, logins[name])
    if 'replaceme' in logins['admin']['passwords']:
        logins['admin']['passwords'].remove('replaceme')
        logins['admin']['passwords'].add(default_admin_password)
        print "Admin password changed to: %s" % default_admin_password
    return logins

logins_file = 'logins.txt'

def apply_script(events):
    def init(protocol):
        protocol.logins = {}
        events.invoke('reload_logins', protocol)
    
    def reload_logins(protocol):
        try:
            protocol.logins = get_logins(logins_file)
        except Exception as e:
            print "Error loading logins.txt: %r" % e
            return repr(e)
    
    events.subscribe(init)
    events.subscribe(reload_logins, None, events.CONSUME)
    
    def login(connection, username, password):
        if username in connection.user_types:
            return "User already logged in"
        login = connection.protocol.logins.get(username, None)
        if not login:
            return "Invalid username"
        if password not in login['passwords']:
            return "Invalid password"
        connection.user_types.add(username)
        return "Successfully logged in as %s" % username
    
    def command(connection, command, args):
        logins = connection.protocol.logins
        for type in connection.user_types:
            if command in logins[type]['rights']:
                return    # allow it
        return "You can't use this command."
    
    events.subscribe(command, None, events.BLOCK)
    events.subscribe(login, None, events.CONSUME)
    
    # commands
    def command_reloadlogins(connection):
        return events.invoke('reload_logins', connection.protocol)
    
    def command_login(connection, username, password):
        return events.invoke('login', connection, username, password)
    
    events.subscribe(command_login, None, events.CONSUME)
    events.subscribe(command_reloadlogins, None, events.CONSUME)
