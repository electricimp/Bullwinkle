# Bullwinkle Framework
Bullwinkle is a [Squirrel](http://squirrel-lang.org)/[Electric Imp](http://electricimp.com) framework aimed at extending agent and device communication. It allows developers to send and receive messages in a similar way to the built in [agent.send](http://electricimp.com/docs/api/agent/send)/[device.on](http://electricimp.com/docs/api/device/on) and [device.send](http://electricimp.com/docs/api/device/send)/[agent.on](http://electricimp.com/docs/api/agent/on), but adds in timeouts, retries, and responses.

# Usage

## Instantiating the class
Create Bullwinkle objects in both the agent *and* the device:

```
bullwinkle <- Bullwinkle();	// create bullwinkle object
bullwinkle.set_timeout(5);	// set default timeout (seconds)
bullwinkle.set_retries(3);	// set default number of retries
```

## bullwinkle.send(commandName, data)

You can send data with bullwinkle in the same way you would *agent.send* or *device.send*. The .send() function will return a Bullwinkle.Session object that you can attach multiple handlers to: *.ontimeout(context)*, *.onexception(context)*, *.onreply(context)*.

```
bullwinkle.send("temperatureData", temp)
    .onreply(function(context) {
    	// this function executes if the receiver calls 'context.reply(reply)'
  	    server.log("Received reply from command '" + context.command + "': " + context.reply);
    })
  	.ontimeout(function(context) {
    	// this function executes if the sending fails after the # of retries + timeout
        server.log("Received reply from command '" + context.command + "' after " + context.latency + "s");
  	})
    .onexception(function(context) {
    	// this function executes if there was an error in the receiver's callback
  	    server.log("Received exception from command '" + context.command + ": " + context.exception);
    })
```

## bullwinkle.on(commandName, callback)

Create a callback function for a specific command. The callback function takes a single parameter - context - which contains the commandName and data from the device/agent (as well as internal information used by bullwinkle). The context object can also be used to send a reply to the sender, which will trigger the sender's *.onreply(context)* function (if it exists):

```
bullwinkle.on("temperatureData", function(context) {
	// pull out the data:
	local data = context.params;
	// do something with the data
	// ...

	context.reply("OK!");
});
```

## Example
The [example](/example) details how to send basic messages (in this case from the device to the agent), as well as how you can use Bullwinkle to asynchronously fetch data from the device in an http handler.

# License
Bullwinkle is licensed under the [MIT License](./LICENSE).
