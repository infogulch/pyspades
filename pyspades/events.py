from itertools import chain

import argspec

S_INVOKE = '(Error invoking event %s on %r with args %r: %r)'

# events:          dict of (event_name:handler_levels)
# handler_levels:  3-tuple of sets of functions

class Events(object):
    EVENT_LEVELS = BLOCK, CONSUME, NOTIFY = range(3)
    
    def __init__(self, default = NOTIFY):
        self.default = default
        self.events = {}
    
    @property
    def default(self):
        return self._default[0] if hasattr(self, "_default") else self.NOTIFY
    
    @default.setter
    def default(self, value):
        if not hasattr(self, "_default"):
            self._default = [self.NOTIFY]
        if value in self.EVENT_LEVELS:
            self._default[0] = value
    
    def _subscribe(self, func, name, level):
        argspec.set(func)
        self.events[name][level].add(func)
    
    # def subscribe(self, func, name = None, level = None):
    def subscribe(self, *args):
        args = list(args)
        func = args.pop(0) if len(args) and hasattr(args[0], "__call__") else None
        cname = args.pop(0) if len(args) else None
        level = args.pop(0) if len(args) and args[0] in self.EVENT_LEVELS else self.default
        def sub(func):
            name = (cname or func.__name__).lower()
            if not self.events.has_key(name):
                self.events.setdefault(name, (set(), set(), set()))
            self._subscribe(func, name, level)
            return func
        return sub(func) if func else sub
    
    def _unsubscribe(self, func, name, level):
        self.events[name][level].discard(func)
        if not any(self.events[name]):
            self.events.pop(name)
    
    def unsubscribe(self, func, name = None, level = None):
        name = name.lower()
        if level not in self.EVENT_LEVELS:
            level = self.default
        if self.events.has_key(name):
            self._unsubscribe(func, name, level)
    
    def invoke(self, name, *args, **kwargs):
        strict = bool(kwargs.get('strict', False))
        if not self.events.has_key(name):
            return None
        for level in self.EVENT_LEVELS:
            for func in self.events[name][level]:
                if not argspec.iscompat(func, len(args)):
                    if strict:
                        raise argspec.ArgCountError(func, len(args))
                    print S_INVOKE % (name, func, args, 'Invalid number of args')
                    continue
                try:
                    result = func(*args)
                except Exception as e:
                    if strict:
                        raise
                    print S_INVOKE % (name, func, args, e)
                else:
                    if level < self.NOTIFY and result is not None:
                        return result
                result = None
        return None
    
    def recorder(self):
        class Recorder(Events):
            def __init__(self, existing):
                # all properties are objects, so when they are copied
                # only references are made; so changes to one apply to all
                self.events = existing.events
                self._default = existing._default
                self.recorded = set()
            
            def _subscribe(self, func, name, level):
                Events._subscribe(self, func, name, level)
                self.recorded.add((func, name, level))
            
            def _unsubscribe(self, func, name, level):
                Events._unsubscribe(self, func, name, level)
                self.recorded.discard((func, name, level))
            
            def unsubscribe_all(self):
                for args in self.recorded.copy():
                    self._unsubscribe(*args)
        
        return Recorder(self)