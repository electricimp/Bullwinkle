// Copyright (c) 2015 Electric Imp
// This file is licensed under the MIT License
// http://opensource.org/licenses/MIT

class Bullwinkle {
    static version = [2,0,0];

    // The bullwinkle message
    static BULLWINKLE = "bullwinkle";

    static NO_HANDLER = "No handler for Bullwinkle message";
    static NO_RESPONSE = "No Response from partner";

    // Message Types
    static SEND = 0;
    static REPLY = 1;
    static ACK = 2;
    static NACK = 3;
    static TIMEOUT = 4;

    // ID Generator
    _nextId = null;

    // The message handlers
    _handlers = null;

    // Packages awaiting send/reply
    _packages = null;

    // The device or agent object
    _partner = null;

    // Bullwinkle Settings
    _settings = null;

    constructor(settings = {}) {
        // Initialize settings
        _settings = {
            "messageTimeout":   ("messageTimeout" in settings) ? settings["messageTimeout"] : 10,
            "retryTimeout":     ("retryTimeout" in settings) ? settings["retryTimeout"] : 60
        };

        // Initialize out message handlers
        _handlers = {};

        // Initialize list of packages
        _packages = {};

        // Initialize the ID counter
        _nextId = 0;

        // Setup the agent/device.on handler
        _partner = _isAgent() ? device : agent;
        _partner.on(Bullwinkle.BULLWINKLE, _onReceive.bindenv(this));

        // Start the watchdog (since imp.wakeups are limited, we only use 1)
        _watchdog();
    }

    // Adds a message handler to the Bullwinkle instance
    //
    // Parameters:
    //      name            The name we're listening for
    //      callback        The message handler (1 parameter)
    //
    // Returns:             this
    function on(name, callback) {
        _handlers[name] <- callback;
        return this;
    }

    // Removes a message handler from the Bullwinkle instance
    //
    // Parameters:
    //      name            The name we're removing the handler for
    //
    // Returns:             this
    function remove(name) {
        if (name in _handlers) { delete _handlers[name]; }
        return this;
    }

    // Sends a bullwinkle message
    //
    // Parameters:
    //      name            The message name
    //      data            Optional data
    //
    // Returns:             Rocky.Package object
    function send(name, data = null) {
        local message = _messageFactory(Bullwinkle.SEND, name, data);
        local package = Bullwinkle.Package(message);
        _packages[message.id] <- package;
        _sendMessage(message);

        return package;
    }

    //-------------------- PRIVATE METHODS --------------------//

    // _isAgent is used to determine if we're an agent or device instance
    //
    // Returns:             true: if we're an agent
    //                      false: if we're a device
    function _isAgent() {
        return imp.environment() == ENVIRONMENT_AGENT;
    }

    // Generates and returns a unique ID
    //
    // Returns:             integer
    function _generateId() {
        // Get the next ID
        while (++_nextId in _packages) {
            _nextId = (_nextId + 1) % RAND_MAX;
        }

        // Return the generated ID
        return _nextId;
    }

    // Builds Bullwinkle context objects / data message
    //
    // Parameters:
    //      type            Bullwinkle.SEND, Bullwinkle.REPLY, Bullwinkle.ACK, Bullwinkle.NACK
    //      name            The message name
    //      data            Optional data
    //      ts              The timestamp (or null to autogenerate as now)
    //
    // Returns:             Table with all the information packed up
    function _messageFactory(type, command, data, ts = null) {
        if (ts == null) { ts = time() };

        return {
            "id": _generateId(),
            "type": type,
            "name": command,
            "data": data
            "ts": ts
        };
    }

    // Sends a prebuild message
    //
    // Parameters:
    //      message         The message to send
    //
    // Returns:             nothing
    function _sendMessage(message) {
        _partner.send(Bullwinkle.BULLWINKLE, message);
    }

    // Sends a response (ACK, NACK, REPLY) to a message
    //
    // Parameters:
    //      data            The bullwinkle message to respond to
    //      state           The new state
    //
    // Returns:             nothing
    function _respond(message, state) {
        message.type = state;
        _sendMessage(message);
    }

    // _onRecieve is the agent/device.on handler for all bullwinkle message
    //
    // Parameters:
    //      data            A bullwinkle message (created by Bullwinkle._messageFactory)
    //
    // Returns:             nothing
    function _onReceive(data) {
        switch (data.type) {
            case Bullwinkle.SEND:
                _sendHandler(data);
                break;
            case Bullwinkle.REPLY:
                _replyHandler(data);
                break;
            case Bullwinkle.ACK:
                _ackHandler(data);
                break;
            case Bullwinkle.NACK:
                _nackHandler(data);
                break;
        }
    }

    // Processes a SEND messages
    //
    // Parameters:
    //      message         The message we're processing
    //
    // Returns:             nothing
    function _sendHandler(message) {
        // If we don't have a handler, send a NACK
        if (!(message.name in _handlers)) {
            _respond(message, Bullwinkle.NACK)
            return;
        }

        // Otherwise ACK the message
        _respond(message, Bullwinkle.ACK);

        // Grab the handler and create a reply method
        local handler = _handlers[message.name];
        local reply = _replyFactory(message);

        // Invoke the handler
        imp.wakeup(0, function() { handler(message, reply); });
    }

    // Processes a REPLY messages
    //
    // Parameters:
    //      message         The message we're processing
    //
    // Returns:             nothing
    function _replyHandler(message) {
        // If we don't have a session for this id, we're done
        if (!(message.id in _packages)) return;

        // Check if there's a reply handler
        local __bull = this;
        local handler = _packages[message.id].getHandler("onReply");

        // If the handler is there:
        if (handler != null) {
            // Invoke the handler and delete the package when done
            imp.wakeup(0, function() {
                delete __bull._packages[message.id];
                handler(message);
            });
        } else {
            // If we don't have a handler, delete the package (we're done)
            delete _packages[message.id];
        }
    }

    // Processes an ACK messages
    //
    // Parameters:
    //      message         The message we're processing
    //
    // Returns:             nothing
    function _ackHandler(message) {
        // If we don't have a session for this id, we're done
        if (!(message.id in _packages)) return;

        // Check if there's a reply handler
        local handler = _packages[message.id].getHandler("onReply");

        // If there isn't - delete the package (we're done)
        if (handler == null) {
            delete _packages[message.id];
        }
    }

    // Processes a NACK messages
    //
    // Parameters:
    //      message         The message we're processing
    //
    // Returns:             nothing
    function _nackHandler(message) {
        // If we don't have a session for this id, we're done
        if (!(message.id in _packages)) return;

        // Grab the handler
        local __bull = this;
        local handler = _packages[message.id].getHandler("onFail");

        // If we don't have a handler, delete the package (we're done)
        if (handler == null) {
            delete _packages[message.id];
            return;
        }

        // Build the retry method for onFail
        local retry = _retryFactory(message);

        // Invoke the handler and delete the package when done
        imp.wakeup(0, function() {
            handler(Bullwinkle.NO_HANDLER, message, retry);

            // Delete the message if the dev didn't retry
            if (message.type == Bullwinkle.NACK) {
                delete __bull._packages[message.id];
            }
        });
    }

    // Create a reply method for a .on handler
    //
    // Parameters:
    //      message         The message we're replying to
    //
    // Returns:             A callback that when invoked, will send a reply
    function _replyFactory(message) {
        return function(data = null) {
            // Set the type and data
            message.type = Bullwinkle.REPLY;
            message.data = data;
            // Send the data
            this._sendMessage(message)
        }.bindenv(this);
    }

    // Create a retry method for a .onFail handler
    //
    // Parameters:
    //      message         The message we're retrying
    //
    // Returns:             A callback that when invoked, will send a retry
    function _retryFactory(message) {
        return function(timeout = null) {
            // Set timeout if required
            if (timeout == null) { timeout = _settings.retryTimeout; }

            // Reset the type
            message.type = SEND;
            // Add the retry information
            message["retry"] <- {
                "ts": time() + timeout,
                "sent": false
            };

            // Update it's package so the _watchdog will catch it
            _packages[message.id]._message = message;
        }.bindenv(this);
    };

    // The _watchdog function brings all timer functionality into a single
    // imp.wakeup. _watchdog is responsible for sending retries and handling
    // message timeouts.
    function _watchdog() {
        // Schedule next run
        imp.wakeup(0.5, _watchdog.bindenv(this));

        // Get the current time
        local t = time();

        // Loop through all the cached packages
        foreach(idx, package in _packages) {
            local message = package._message;

            // if it's a message queued for retry
            if ("retry" in message && !message.retry.sent) {
                // Check if we need to send it
                if (t >= message.retry.ts) {
                    // Send and update sent flag
                    this._sendMessage(message);
                    _packages[idx]._message.retry.sent = true;
                }

                // Move to next package
                continue;
            }

            // if it's a message awaiting a reply
            local ts = "retry" in message ? message.retry.ts : message.ts;
            if (t >= (ts + _settings.messageTimeout)) {
                // Grab the onFail handler
                local handler = package.getHandler("onFail");

                // If the handler doesn't exists
                if (handler == null) {
                    // Delete the package, and move to next package
                    delete _packages[message.id];
                    continue;
                }

                // Grap a reference this this
                local __bull = this;

                // Build the retry method for onFail
                local retry = _retryFactory(message);

                // Invoke the onFail handler
                imp.wakeup(0, function() {
                    // Invoke the handlers
                    message.type = Bullwinkle.TIMEOUT
                    handler(Bullwinkle.NO_RESPONSE, message, retry);
                    // Delete the message if there wasn't a retry attempt
                    if (message.type == Bullwinkle.TIMEOUT) {
                        delete __bull._packages[message.id];
                    }
                });
            }
        }
    }
}

class Bullwinkle.Package {
    // The event handlers
    _handlers = null;

    // The message we're wrapping
    _message = null;

    // Class constructor
    //
    // Parameters:
    //      message         The message we're wrapping
    constructor(message) {
        _message = message;
        _handlers = {};
    }

    // Sets an onReply method that will be called when the message
    // is replied to.
    //
    // Parameters:
    //      callback        The onReply callback (1 parameter)
    //
    // Returns:             this
    function onReply(callback) {
        _handlers["onReply"] <- callback;
        return this;
    }

    // Sets an onFail callback that will be invoked if the message cannot
    // be sent, or if there was no handler for the message
    //
    // Parameters:
    //      callback        The onFail callback (1 parameter)
    //
    // Returns:             this
    function onFail(callback) {
        _handlers["onFail"] <- callback;
        return this;
    }

    // Returns the specified handler (or null if the handler is not found)
    //
    // Parameters:
    //      handlerName     The name of the handler we're looking for
    //
    // Returns:             The handler, or null (if it doesn't exist)
    function getHandler(handlerName) {
        if (!(handlerName in _handlers)) { return null; }

        return _handlers[handlerName];
    }
}
