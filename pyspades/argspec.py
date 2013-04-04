import inspect

def set(func):
    if not hasattr(func, 'argspec'):
        if inspect.ismethod(func):
            func = func.__func__
        func.argspec = inspect.getargspec(func)

def iscompat(func, lenargs):
    spec = func.argspec
    lenspec = len(spec.args) - int(inspect.ismethod(func))
    minargs = lenspec - len(spec.defaults or ())
    maxargs = lenspec if spec.varargs is None else float("infinity")
    return minargs <= lenargs <= maxargs

class ArgCountError(Exception):
    pass
