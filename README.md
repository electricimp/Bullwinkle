# Bullwinkle Framework

Bullwinkle is a [Squirrel](http://squirrel-lang.org)/[Electric Imp](http://electricimp.com) framework designed to extend agent and device communication. It allows developers to send and receive messages in a similar way to the built in [**agent.send()**](http://electricimp.com/docs/api/agent/send)/[**device.on()**](http://electricimp.com/docs/api/device/on) and [**device.send()**](http://electricimp.com/docs/api/device/send)/[**agent.on()**](http://electricimp.com/docs/api/agent/on) methods, but adds timeouts, retries and responses.

## Usage

### Constructor

Instantiate Bullwinkle objects in both the agent *and* the device, and initialize the objects with timeout and retry count settings:

```squirrel
bullwinkle <- Bullwinkle()    // create bullwinkle object
bullwinkle.set_timeout(5)     // set default timeout (seconds)
bullwinkle.set_retries(3)     // set default number of retries
```

### Class Methods

### send(*commandName*, *data*)

You can send data with Bullwinkle in the same way you would [**agent.send()**](http://electricimp.com/docs/api/agent/send) or [**device.send()**](http://electricimp.com/docs/api/device/send). The *send()* method will return a Bullwinkle.Session object that you can attach multiple handlers to: *ontimeout()*, *onexception()* and *onreply()*.

```squirrel
bullwinkle.send("temperatureData", temp)
    .onreply(function(context) {
        // This function executes if the receiver calls 'context.reply(reply)'
        server.log("Received reply from command '" + context.command + "': " + context.reply)
    })
    
    .ontimeout(function(context) {
        // This function executes if the sending fails after the # of retries + timeout
        server.log("Received reply from command '" + context.command + "' after " + context.latency + "s")
    })

    .onexception(function(context) {
        // This function executes if there was an error in the receiver's callback
        server.log("Received exception from command '" + context.command + ": " + context.exception)
    })
```

### on(*commandName*, *callback*)

Create a callback function for a specific command. The callback function takes a single parameter, *context*, which contains the command name and data from the device/agent (as well as internal information used by Bullwinkle). The context object can also be used to send a reply to the sender, which will trigger the sender’s *.onreply()* method (if it exists):

```squirrel
bullwinkle.on("temperatureData", function(context) {
	// Pull out the data
	
	local data = context.params
	
	// Do something with the data
	// ...

	context.reply("OK!")
})
```

## Example

The [example](/example) details how to send basic messages (in this case from the device to the agent), as well as how you can use Bullwinkle to asynchronously fetch data from the device in an HTTP handler.

## License

Bullwinkle is licensed under the [MIT License](./LICENSE).
