from pyspades.argspec import ArgCountError

def apply_script(events):
    def command(conn, command, args):
        try:
            result = events.invoke('command_'+command, conn, *args, strict=True)
        except ArgCountError:
            result = 'Invalid arg count for %s' % command
        except Exception as e:
            result = 'Command %s failed' % command
            print "Command error: %r" % e
        return result
    
    def command_loadscript(connection, name, module = None):
        args = (name,)
        if module:
            args += (module,)
        events.invoke('load_script', *args)
    
    def command_unloadscript(connection, name, module = None):
        args = (name,)
        if module:
            args += (module,)
        events.invoke('unload_script', *args)
    
    events.subscribe(command, None, events.CONSUME)
    events.subscribe(command_loadscript, None, events.CONSUME)
    events.subscribe(command_unloadscript, None, events.CONSUME)
