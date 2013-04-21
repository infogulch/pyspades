from pyspades.argspec import ArgCountError

def apply_script(events):
    def command(conn, command, args):
        log_message = '<%s> /%s %s' % (conn.name, command, ' '.join(args))
        args = (conn,) + tuple(args)
        try:
            result = events.invoke('command_' + command, *args, strict = True)
        except ArgCountError:
            result = 'Invalid arg count for %s' % command
            log_message += ' -> %s' % result
        except Exception as e:
            result = 'Command %s failed' % command
            log_message += ' -> Error: %r' % e
        else:
            log_message += ' -> %s' % result
        if result:
            conn.send_chat(result)
        print log_message.encode('ascii', 'replace')
    
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
    
    events.subscribe(command)
