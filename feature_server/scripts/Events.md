Events is the interface for scripting Pyspades. This document outlines how it is used.

The goal of the event system is to provide a unified, extensible, error-tolerant, and dynamic interface for scripts to interact with the underlying pyspades system and with other scripts. 

### Contents
* [Script Format](#script-format)
* Usage
  * [Overview](#overview)
  * [Subscribing](#subscribing)
* Loading
  * [Startup](#startup)
  * [Built in Events](#built-in-events)
  * [Dynamic Script Loading](#dynamic-script-loading)
  * [Script to Script Interface](#script-to-script-interface)


## [Script Format](#contents)
Script requirements:
* It must be a python file that resides in `feature_server/scripts`. (Or `feature_server/core` for core scripts; more on that later.)
* It must contain a function named `apply_script` in the module namespace that has a single parameter (usually named `events`), which will be an Events object.
* `apply_script` should define functions and call methods on the passed `events` arg.
* In general a script should *not* import any other scripts directly.


# Usage
### [Overview](#contents)
The event system is the single interface for all actions that a script can take, and there are two sides to it.

An event is similar to a function call in that 1. it has a *name* and 2. it accepts *arguments*. But you don't "call" an event, you **invoke** it. Why the terminology difference? Because any number of scripts may receive the same event. To receive an event, a script can **subscribe** to it by name. When an event is invoked by name, all subscribed scripts are called with the same arguments passed when it was invoked.

All of this is done through the `events` object passed to `apply_script`.

To subscribe to an event call the `subscribe` method and pass a function and the name of the event.
```python
def hello(param):
    print "Hello, " + param

events.subscribe(my_subscriber, 'my_event')
```

To invoke an event, call the `invoke` method with a **string** for the event name, followed by any parameters to be passed along to any subscribers.
```python
events.invoke('my_event', 'John')        # Prints "Hello, John"
```

Important notes for this default case: 
* Any script can subscribe to, unsubscribe from, or invoke any event at any time.
* Subscribers are called in **arbitrary order**.
* If the number of arguments passed to `invoke` does not match the required arguments of a subscriber, an error will be printed and that subscriber will be skipped.
* If a subscriber raises an Exception during execution, the exception will be printed to the console, and the remaining subscribers will still be called.

*The idea is that a single mistake or badly coded script should not be able to bring down the whole system.*


### [Subscribing](#contents)
The default settings mentioned above doesn't really cover all use cases for events. For example, a script wouldn't be able to override the default behavior of an event. Also the old system often had multiple "events" for the same action, one as a way to block an event and a second for the actual event itself, requiring the caller to call both of them which complicated code. (E.g. if calling `block_place_attempt` returned something then `block_place` was skipped.) It would be nice if these redundancies could be removed.

Remember just above where I said that subscribers are called in arbitrary order? Well, I lied (sort of). There are actually 3 groups of subscribers for each event. The groups (called **levels**) are called in order (but subscriptions within each level are still called in arbitrary order). *Levels exist to cover the other use-cases and as a replacement for depending on the order scripts are called.*

Level 0: **BLOCK** A subscriber in this level that returns any value immediately returns the value to the invoker and doesn't call any more subscribers, effectively blocking the event. Subscribers that block shouldn't do anything else to avoid problems with order.

Level 1: **CONSUME** Similar to BLOCK. Override the default functionality in the NOTIFY level by doing something else instead.

Level 2: **NOTIFY (default)** Return values are ignored and all subscribers are called once it gets past the BLOCK and CONSUME levels. Most built-in subscribers reside here.

To subscribe at a specific level, pass the level number as the third parameter to `events.subscribe`. There are named constants in the `events` object.
```python
def no_hello(param):
    if param == 'John':
        return "No hello for you!"

events.subscribe(no_hello, 'my_event', events.BLOCK)

events.invoke('my_event', 'John')    # Nothing is printed, it was BLOCKed!
events.invoke('my_event', 'Jenny')   # Prints "Hello, Jenny"
```


# Loading
### [Startup](#contents)
After the server is finished loading it loads the scripts. First *all* core scripts are loaded (all scripts in the `feature_server/core` directory), then the user scripts listed in `config.txt` are loaded from `feature_server/scripts`.  After scripts are finished loading, the `init` event is fired with `protocol` as the single argument. So do all initialization in a subscription to the `init` event.


### [Built in Events](#contents)
Built in events include:
* `load_script('script-name')`, `unload_script('script_name'`: This is the proper method for scripts to [un]load other scripts at run-time.
* `reload_logins()`: Reloads login data for the login system.
* `login(conn, username, password)`: Attempts to login the connection using the username and password pair.
* `command_[command_name](conn, args)`: Invoked when the user types a command. If there are no subscribers for this command, it is ignored.

TODO:
* Player events.
* Game events.
* System events.

### [Dynamic Script Loading](#contents)
If all interfaces are kept in the event system, and scripts don't import each other, scripts can be dynamically loaded and unloaded at any time. 

### [Script to Script Interface](#contents)
Scripts should communicate with eachother by using events. To recieve information from another script, subscribe to an event and have the other script invoke the event. This keeps the system flexible. For example, either of your scripts could be reloaded on the fly without affecting eachother, or another script could modify the behavior by blocking the event.
