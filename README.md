# Bullwinkle Framework

Bullwinkle is an easy to use framework for asynchronous agent and device communication. The Bullwinkle library consists of two classes:

- [Bullwinkle](#bullwinkle) - The core application - used to add/remove handlers, and send messages.
  - [Bullwinkle.send](#bullwinkle_send) - Sends a message to the partner application.
  - [Bullwinkle.on](#bullwinkle_on) - Adds a message listener for the specified messageName.
    - [reply](#bullwinkle_on_reply) - A method passed into .on handlers that is used to reply to the message.
  - [Bullwinkle.remove](#bullwinkle_remove) - Removes a message listener for the specified messageName.
- [Bullwinkle.Package](#package) - A packaged message with event handlers.
  - [Package.onReply](#package_onreply) - Adds a handler that will be invoked if the message is replied to.
  - [Package.onFail](#package_onfail) - Adds an onFail handler that will be invoked if the send failed.
    - [retry](#package_onfail_retry) - A method passed into .onFail handlers that is used to retry sending the message.

<div id="bullwinkle"><h2>Bullwinkle([options])</h2></div>

Calling the Bullwinkle constructor creates a new Bullwiunkle application.  An optional *options* table can be passed into the constructor to override default behaviours:

```squirrel
#require "bullwinkle.class.nut:2.0.1"

bull <- Bullwinkle();
```

**NOTE:** You must `require` and instantiate Bullwinkle in both the agent and device code.

<div id="bullwinkle_options"><h4>options</h4></div>
A table containing any of the following keys may be passed into the Bullwinkle constructor to modify the default behaviour:

- ```messageTimeout``` - Changes the default timeout required before a message is considered failed.
- ```retryTimeout``` - Changes the default timeout parameter passed to the [retry](#retry) method.

The default settings are listed below:

```squirrel
{
    "messageTimeout": 10.0,  // If there is no response from a message in 10 seconds, consider it failed
    "retryTimeout": 60.0     // Calling package.retry() with no parameter will retry in 60 seconds
}
```

<div id="bullwinkle_send"><h3>send(messageName, [data])</h3></div>

Sends a named message to the partner's Bullwinkle application, and returns a [Bullwinkle.Package](#package). The *data* parameter can be a basic Squirrel type (`1`, `true`, `"A String"`) or more complex data structures such as an array or table.

```squirrel
bull.send("setLights", true);   // Turn the lights on
```

The send method returns a [Bullwinkle.Package](#package) object that can be used to attach [onFail](#package_onfail) and [onReply](#package_onreply) handlers.

<div id="bullwinkle_on"><h3>on(messageName, callback)</h3></div>

Adds a message listener (the *callback*) for the specified *messageName*. The callback method takes two parameters: *message* (the message), and *reply* (a method that can be called to reply to the message).

```squirrel
// Get a message, and do something with it
bull.on("setLights", function(message, reply) {
    led.write(message.data);
});
```

<div id="bullwinkle_on_reply"><h4>reply(data)</h4></div>

The second parameter, *reply*, is a method that can be invoked to reply to the message caught by the .on handler. The reply method takes a parameter - *data* - representing the information we want to pass back to the partner. The *data* parameter can be a basic Squirrel type (`1`, `true`, `"A String"`) or more complex data structures such as an array or table.

```squirrel
// Get a message, and respond to it
bull.on("temp", function(message, reply) {
    // Read the temperature and humidity sensor
    local data = tempHumid.read();

    // Reply to the message
    reply(data);
});
```

<div id="bullwinkle_remove"><h3>remove(messageName)</h3></div>

The *remove* method removes a message listener that was added with the [.on](#bullwinkle_on) method.

```squirrel
bull.remove("test");     // Don't listen for 'test' messages anymore.
```

<div id="package"><h2>Bullwinkle.Package</h2></div>

A Bullwinkle.Package object represents a message that has been sent to the partner, and has event handlers attached to it. Bullwinkle.Package objects should never be manually constructed (the [Bullwinkle.send](#bullwinkle_send) method returns a Bullwinkle.Package object).

<div id="package_onreply"><h3>onReply(callback)</h3></div>

The onReply method adds an event listener (the *callback*) that will execute if the partner *.on* handler replies to the message with the [reply](#bullwinkle_on_reply) method. The callback takes a single parameter, *message*, which contains the message information.

The following example demonstrates how to get real time sensor information with [Rocky](https://github.com/electricimp/rocky) and Bullwinkle:

```squirrel
// Agent Code
#require "Rocky.class.nut:1.2.0"
#require "Bullwinkle.class.nut:2.0.0"

app <- Rocky();
bull <- Bullwinkle();

app.get("/data", function(context) {
    bull.send("temp").onReply(function(message) {
        context.send(200, message.data);
    });
});
```

```squirrel
// Device Code
#require "Si702x.class.nut:1.0.0"
#require "Bullwinkle.class.nut:1.0.0"

bull <- Bullwinkle();

i2c <- hardware.i2c89;
i2c.configure(CLOCK_SPEED_400_KHZ);
tempHumid <- Si702x(i2c);

bull.on("temp", function(message, reply){
    local result = tempHumid.read();
    reply(result)
});
```

<div id="package_onfail"><h3>onFail(callback)</h3></div>

The onFail method adds an event listener (the *callback*) that will  execute if the partner application does not have a handler for the specified messageName, or if the partner fails to respond within a specified period of time (the [messageTimeout](#bullwinkle_options)). The callback method requires three parameters: *err*, *message*, and *retry*.

The *err* parameter describes the error, and will either be `Bullwinkle.NO_HANDLER` (in the event the partner application does not have a handler for the specified messageName), or `Bullwinkle.NO_RESPONSE` (in the event the partner application fails to respond in the specified timeout period).

The *message* parameter contains the failed message.

The *retry* parameter is a method that can be invoked to retry sending the message in a specified period of time.

```squirrel
bull.send("importantMessage")
    .onFail(function(err, message, retry) {
        if (err == Bullwinkle.NO_RESPONSE) {
            retry(60);     // Try sending the message again in 60 seconds
        } else {
            server.error("Forgot the setup handler for " + message.name);
        }
    }).onReply(function(message) {
        server.log("Done!");
    });
```

<div id="package_onfail_retry"><h4>retry([timeout])</h4></div>

The *retry* method is passed into onFail handler, and can be used to try sending the failed message again after the specified timeout has elapsed. If no timeout is specified, the retry message will use the default [retryTimeout](#bullwinkle_options) setting. See [onFail](#package_onfail) for example usage.

## License

Bullwinkle is licensed under the [MIT License](./LICENSE).
