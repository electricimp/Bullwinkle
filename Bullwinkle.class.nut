// Copyright (c) 2015-2016 Electric Imp
// This file is licensed under the MIT License
// http://opensource.org/licenses/MIT


// Message Types
enum BULLWINKLE_MESSAGE_TYPE {
    SEND,
    REPLY,
    ACK,
    NACK,
    FAILED,
    DONE
}

// Error messages
const BULLWINKLE_ERR_NO_HANDLER = "No handler for Bullwinkle message";
const BULLWINKLE_ERR_NO_RESPONSE = "No Response from partner";
const BULLWINKLE_ERR_LOW_MEMORY = "imp running below low memory threshold";
const BULLWINKLE_ERR_NO_CONNECTION = "server.isconnected() == false"
const BULLWINKLE_ERR_TOO_MANY_TIMERS = "Too many timers";
const BULLWINKLE_WATCHDOG_TIMER = 0.5;


class Bullwinkle {
    static version = [2,3,2];

    // The bullwinkle message
    static BULLWINKLE = "bullwinkle";

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

    _watchdogTimer = null;

    constructor(settings = {}) {
        // Initialize settings
        _settings = {
            "messageTimeout":     ("messageTimeout" in settings) ? settings["messageTimeout"].tostring().tointeger() : 10,
            "retryTimeout":       ("retryTimeout" in settings) ? settings["retryTimeout"].tostring().tointeger() : 60,
            "maxRetries":         ("maxRetries" in settings) ? settings["maxRetries"].tostring().tointeger() : 0,
            "autoRetry" :	        ("autoRetry" in settings) ? settings["autoRetry"] : false,
            "lowMemoryThreshold": ("lowMemoryThreshold" in settings) ? settings["lowMemoryThreshold"].tointeger() : 15000,
            "firstMessageID":     ("firstMessageID" in settings) ? settings["firstMessageID"].tointeger() : 0
            "onError" :           ("onError" in settings) ? settings["onError"] : null
        };

        // Initialize out message handlers
        _handlers = {};

        // Initialize list of packages
        _packages = {};

        // Initialize the ID counter (can be set to math.rand() or the last message ID you have in nv to prevent ID collisions with something like impPager)
        _nextId = settings.firstMessageID;

        // Setup the agent/device.on handler
        _partner = _isAgent() ? device : agent;
        _partner.on(BULLWINKLE, _onReceive.bindenv(this));
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
    //      ts              Optional timestamp for the data
    //
    // Returns:             Bullwinkle.Package object
    function send(name, data = null, ts = null) {
        local message = _messageFactory(BULLWINKLE_MESSAGE_TYPE.SEND, name, data, ts);
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
    //      type            BULLWINKLE_MESSAGE_TYPE.SEND, BULLWINKLE_MESSAGE_TYPE.REPLY, BULLWINKLE_MESSAGE_TYPE.ACK, BULLWINKLE_MESSAGE_TYPE.NACK
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
            "data": data,
            "ts": ts,
        };
    }

    // Sends a prebuild message
    //
    // Parameters:
    //      message         The message to send
    //
    // Returns:             nothing
    function _sendMessage(message) {
        // Start the watchdog if not already running
        if (_watchdogTimer == null) _watchdog();

        // Increment the tries
        if (message.type == BULLWINKLE_MESSAGE_TYPE.SEND && message.id in _packages) {
		        _packages[message.id]._tries++;
        }

        if(imp.getmemoryfree() > _settings.lowMemoryThreshold && (_isAgent() || server.isconnected())){
          _partner.send(BULLWINKLE, message); // Send the message
        } else if(message.id in _packages){ //run the failure flow (if the package exists)
          local reason = imp.getmemoryfree() <= _settings.lowMemoryThreshold ? BULLWINKLE_ERR_LOW_MEMORY : BULLWINKLE_ERR_NO_CONNECTION

          local timer = imp.wakeup(0.0, function(){ // run on the "next tick" so that the onFail handler can have a chance to register itself
              _packageFailed(_packages[message.id], reason)
          }.bindenv(this));
          _checkTimer(timer)
        }
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

    // _onReceive is the agent/device.on handler for all bullwinkle message
    //
    // Parameters:
    //      data            A bullwinkle message (created by Bullwinkle._messageFactory)
    //
    // Returns:             nothing
    function _onReceive(data) {
        switch (data.type) {
            case BULLWINKLE_MESSAGE_TYPE.SEND:
                _sendHandler(data);
                break;
            case BULLWINKLE_MESSAGE_TYPE.REPLY:
                _replyHandler(data);
                break;
            case BULLWINKLE_MESSAGE_TYPE.ACK:
                _ackHandler(data);
                break;
            case BULLWINKLE_MESSAGE_TYPE.NACK:
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
            _respond(message, BULLWINKLE_MESSAGE_TYPE.NACK)
            return;
        }

        // Otherwise ACK the message
        _respond(message, BULLWINKLE_MESSAGE_TYPE.ACK);

        // Grab the handler and create a reply method
        local handler = _handlers[message.name];
        local reply = _replyFactory(message);

        // Invoke the handler
        local timer = imp.wakeup(0, function() { handler(message, reply); });
        _checkTimer(timer);
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
        local latency = _packages[message.id].getLatency();
        local handler = _packages[message.id].getHandler("onReply");

        // If the handler is there:
        if (handler != null) {

            // Invoke the handler and delete the package when done
            local timer = imp.wakeup(0, function() {
                delete __bull._packages[message.id];
                message.latency <- latency;
                handler(message);
            });
            _checkTimer(timer);

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

        // Check if there's a success handler
        local latency = _packages[message.id].getLatency();
        local handler = _packages[message.id].getHandler("onSuccess");

        // If the handler is there:
        if (handler != null) {

            // Invoke the handler
            local timer = imp.wakeup(0, function() {
                message.latency <- latency;
                handler(message);
            });
            _checkTimer(timer);
        }

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

        // Build the retry method for onFail
        local retry = _retryFactory(message);

        // If we don't have a handler, delete the package (we're done)
        if (handler == null) {
            //server.error("Received NACK from Bullwinkle.send(\"" + message.name + "\", ...)");
            if (_settings["autoRetry"]) { // if autoRetry is set true
            	if (!retry(_settings["retryTimeout"])) { // when the number of retry is equal to maxRetries
            		server.log("done retrying");
            	}
            } else {
            	delete _packages[message.id];
            }
            return;
        }

        // Invoke the handler and delete the package when done
        local timer = imp.wakeup(0, function() {
            handler(BULLWINKLE_ERR_NO_HANDLER, message, retry);

            // Delete the message if the dev didn't retry
            if (message.type == BULLWINKLE_MESSAGE_TYPE.NACK) {
            	delete __bull._packages[message.id];
            }
        });
        _checkTimer(timer);
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
            message.type = BULLWINKLE_MESSAGE_TYPE.REPLY;
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

        	// Check the message is still valid
            if (!(message.id in _packages)) {
        	       // server.error(format("Bullwinkle message id=%d has expired", message.id))
          	       message.type = BULLWINKLE_MESSAGE_TYPE.DONE;
                   return false;
          	}

          	// Check there are more retries available
          	if (_settings.maxRetries > 0 && _packages[message.id]._tries >= _settings.maxRetries) {
                   // server.error(format("Bullwinkle message id=%d has no more retries", message.id))
          	       message.type = BULLWINKLE_MESSAGE_TYPE.DONE;
          	       delete _packages[message.id];
                   return false;
          	}

            // Set timeout if required
            if (timeout == null) { timeout = _settings.retryTimeout; }

            // Reset the type
            message.type = BULLWINKLE_MESSAGE_TYPE.SEND;

            // Add the retry information
            message.retry <- {
                "ts": ( Bullwinkle._isAgent() ? time() : hardware.micros()/1000000 )  + timeout,
                "sent": false
            };

            // Update it's package so the _watchdog will catch it
            _packages[message.id]._message = message;

            return true;

        }.bindenv(this);
    };

    // Call the onFail handler when a timeout occurs
    //
    // Parameters:
    //      package         The Bullwinkle.Package that has timed out
    //
    function _packageFailed(package, reason) {
        // Grab the onFail handler
        local handler = package.getHandler("onFail");
        local message = package._message

        // If the handler doesn't exists
        if (handler == null) {
            // Delete the package, and move to next package
            delete _packages[message.id];
        }

        // Grab a reference to this
        local __bull = this;

        // Build the retry method for onFail
        local retry = _retryFactory(message);

        // Invoke the handlers
        message.type = BULLWINKLE_MESSAGE_TYPE.FAILED
        handler(reason, message, retry);
        // Delete the message if there wasn't a retry attempt
        if (message.type == BULLWINKLE_MESSAGE_TYPE.FAILED) {
            delete __bull._packages[message.id];
        }
    }

    // checks that TIMER was set, calls onError callback if needed
    //
    // Parameters:
    //      timer         The value returned by calling imp.wakeup
    //
    // Returns:             nothing
    function _checkTimer(timer) {
        if (timer == null && "onError" in _settings) {
            _settings.onError(BULLWINKLE_ERR_TOO_MANY_TIMERS);
        }
    }

    // The _watchdog function brings all timer functionality into a single
    // imp.wakeup. _watchdog is responsible for sending retries and handling
    // message timeouts.
    function _watchdog() {
        // Get the current time
        local t = time()

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
            local ts = "retry" in message ? message.retry.ts : split(package._ts, ".")[0].tointeger(); //Use either the retry ts or the package ts time(), but NOT the message ts so that it can be set for whenever the data was generated, instead of when Bullwinkle attempted to send it
            if (t >= (ts + _settings.messageTimeout) || t == 946684800) { //RTC is invalid, which implies we have no connection and should retry immediately.
                local timer = imp.wakeup(0.0, function(){
                    _packageFailed(package, BULLWINKLE_ERR_NO_RESPONSE)
                }.bindenv(this));
                _checkTimer(timer)
            }
        }

        // If packages still pending schedule next run
        if ( _packages.len() > 0 ) {
            _watchdogTimer = imp.wakeup(BULLWINKLE_WATCHDOG_TIMER, _watchdog.bindenv(this));
            _checkTimer(_watchdogTimer);
        } else {
            _watchdogTimer = null;
        }
    }
}

class Bullwinkle.Package {

    // The event handlers
    _handlers = null;

    // The message we're wrapping
    _message = null;

    // The timestamp of the original message
    _ts = null;

    // the number of attempts we have made to send the message
    _tries = null;

    // Class constructor
    //
    // Parameters:
    //      message         The message we're wrapping
    constructor(message) {
        _message = message;
        _handlers = {};
        _ts = _timestamp();
        _tries = 0;
    }

    // Sets an onSuccess callback that will be invoked if the message is successfully
    // received from the other side.
    //
    // Parameters:
    //      callback        The onSuccess callback (1 parameter)
    //
    // Returns:             this
    function onSuccess(callback) {
        _handlers["onSuccess"] <- callback;
        return this;
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
    //      callback        The onFail callback (3 parameters)
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
        return (handlerName in _handlers) ? _handlers[handlerName] : null;
    }

    // Returns the time since the message was sent
    //
    // Parameters:
    //
    // Returns:         The time difference in seconds (float) between the packages timestamp and now()
    function getLatency() {
      local t0 = split(_ts, ".");
      local t1 = split(_timestamp(), ".");

      if (Bullwinkle._isAgent()) {
        local diff = (t1[0].tointeger() - t0[0].tointeger()) + ( (t1[1].tointeger() - t0[1].tointeger()) / 1000000.0);
        return math.fabs(diff);
      } else {
        return (t1[1].tointeger() - t0[1].tointeger()) / 1000000.0;
      }
    }

    // Returns the time in a string format that can be used for calculating latency
    //
    // Parameters:
    //
    // Returns:             The time in a string format
    function _timestamp() {
        if (Bullwinkle._isAgent()) {
            local d = date();
            return format("%d.%06d", d.time, d.usec);
        } else {
            return format("%d.%06d", time(), hardware.micros());  //this can be a bit of an ugly _ts but it allows us to calculate latencies up to 36 minutes long...
        }
    }
}
