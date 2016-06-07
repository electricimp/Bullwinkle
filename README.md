# Bullwinkle Framework v2.3.0

Bullwinkle is an easy to use framework for asynchronous agent and device communication. The Bullwinkle library consists of two classes:

- [Bullwinkle](#bullwinkle) - The core application - used to add/remove handlers, and send messages.
  - [Bullwinkle.send](#bullwinkle_send) - Sends a message to the partner application.
  - [Bullwinkle.on](#bullwinkle_on) - Adds a message listener for the specified messageName.
    - [message](#bullwinkle_on_message) - The message table passed into .on handlers.
    - [reply](#bullwinkle_on_reply) - A method passed into .on handlers that is used to reply to the message.
  - [Bullwinkle.remove](#bullwinkle_remove) - Removes a message listener for the specified messageName.
- [Bullwinkle.Package](#bullwinklepackage) - A packaged message with event handlers.
  - [Package.onSuccess](#onsuccesscallback) - Adds a handler that will be invoked if the message is successfully delivered and acknowledged.
  - [Package.onReply](#onreplycallback) - Adds a handler that will be invoked if the message is replied to.
  - [Package.onFail](#onfailcallback) - Adds an onFail handler that will be invoked if the send failed.
    - [retry](#retrytimeout) - A method passed into .onFail handlers that is used to retry sending the message.

**To add this library to your project, add** `#require "bullwinkle.class.nut:2.3.0"` **to the top of your agent and device code.**

**Note** You must `#require` and instantiate Bullwinkle in **both** the agent and device code.

## Bullwinkle Usage ##

<div id="bullwinkle"><h3>Constructor: Bullwinkle(<i>[options]</i>)</h3></div>

Calling the Bullwinkle constructor creates a new Bullwinkle application. An optional *options* table can be passed into the constructor to override default behaviors.

<div id="bullwinkle_options"><h4>options</h4></div>

A table containing any of the following keys may be passed into the Bullwinkle constructor to modify the default behavior:

| Key | Data Type | Default Value | Description |
| ----- | -------------- | ------------------ | --------------- |
| *messageTimeout* | Integer | 10 | Changes the default timeout required before a message is considered failed. |
| *retryTimeout* | Integer | 60 | Changes the default timeout parameter passed to the [retry](#retrytimeout) method. |
| *maxRetries* | Integer | 0 | Changes the default number of times the [retry](#retrytimeout) method will function. After this number the [retry](#retrytimeout) method will do nothing. If set to 0 there is no limit to the number of retries. |
| *autoRetry* | Boolean | `false` | If set to `true`, Bullwinkle will automatically continue to retry sending a message until *maxRetries* has been reached when no [onFail](#onfailcallback) is supplied. Please note if *maxRetries* is set to 0, *autoRetry* will have no limit to the number of times it will retry. |

#### Examples

```squirrel
// Initialize using default settings
bull <- Bullwinkle();
```

```squirrel
options <- { "messageTimeout": 5,   // If there is no response from a message in 5 seconds,
                                    // consider it failed
             "retryTimeout": 30,    // Calling package.retry() with no parameter will retry 
                                    // in 30 seconds
             "maxRetries": 10,      // Limit to the number of retries to 10
             "autoRetry": true      // Automatically retry 10 times
           }
// Initialize using custom settings
bull <- Bullwinkle(options);
```

## Bullwinkle Methods

<div id="bullwinkle_send"><h3>send(<i>messageName[, data]</i>)</h3></div>

Sends a named message to the partner’s Bullwinkle application, and returns a [Bullwinkle.Package](#package). The *data* parameter can be a basic Squirrel type (`1`, `true`, `"A String"`) or more complex data structures such as an array or table, but it must be [a serializable Squirrel value](https://electricimp.com/docs/resources/serialisablesquirrel/).

```squirrel
bull.send("setLights", true);   // Turn the lights on
```

The *send()* method returns a [Bullwinkle.Package](#package) object that can be used to attach [onFail](#onfailcallback),  [onSuccess](#onsuccesscallback) and [onReply](#onreplycallback) handlers.

<div id="bullwinkle_on"><h3>on(<i>messageName, callback</i>)</h3></div>

Adds a message listener (the *callback*) for the specified *messageName*. The callback method takes two parameters: *message* (the message) and *reply* (a method that can be called to reply to the message).

```squirrel
// Get a message, and do something with it
bull.on("setLights", function(message, reply) {
    led.write(message.data);
});
```

<div id="bullwinkle_on_message"><h4>message</h4></div>

The *message* parameter is a table that contains some or all of the following keys:

| Key         | Data Type | Description |
| ------------ | -------------  | --------------- |
| *type*        | Integer              | Bullwinkle message type |
| *tries*        | Integer              | Number of attempts made to deliver the message |
| *name*      | String         | Name of the message |
| *id*            | Integer              | ID of the message |
| *ts*            | Integer              | Timestamp when message was created |
| *data*        | [Serializable Squirrel value](https://electricimp.com/docs/resources/serialisablesquirrel/) | data passed into the #send method |
| *retry*        | Table          | A table containing *ts* the timestamp of the latest retry and *sent* a boolean |
| *latency*    | Float           | Seconds taken to deliver the message |

<div id="bullwinkle_on_reply"><h4>reply(<i>data</i>)</h4></div>

The second parameter, *reply*, is a method that can be invoked to reply to the message caught by the .on handler. The reply method takes a parameter, *data*, representing the information we want to pass back to the partner. The *data* parameter can be [any serializable Squirrel value](https://electricimp.com/docs/resources/serialisablesquirrel/).

```squirrel
// Get a message, and respond to it
bull.on("temp", function(message, reply) {
    // Read the temperature and humidity sensor
    local data = tempHumid.read();

    // Reply to the message
    reply(data);
});
```

<div id="bullwinkle_remove"><h3>remove(<i>messageName</i>)</h3></div>

The *remove()* method removes a message listener that was added with the [.on](#bullwinkle_on) method.

```squirrel
bull.remove("test");     // Don't listen for 'test' messages any more.
```

<div id="package"><h2>Bullwinkle.Package</h2></div>

A Bullwinkle.Package object represents a message that has been sent to the partner, and has event handlers attached to it. Bullwinkle.Package objects should never be manually constructed: the [Bullwinkle.send()](#bullwinkle_send) method returns a Bullwinkle.Package object.

<div id="onsuccesscallback"><h3>onSuccess(<i>callback</i>)</h3></div>

The *onSuccess()* method adds an event listener (the *callback*) that will execute if the partner *.on* handler receives the message. The callback’s *message* parameter contains the successfully delivered message, including a *tries* count and a round-trip *latency* float in seconds.

```squirrel
bull.send("importantMessage")
    .onSuccess(function(message) {
        server.log("Done!");
    })
    .onFail(function(err, message, retry) {
        retry();
    });
```

<div id="onreplycallback"><h3>onReply(<i>callback</i>)</h3></div>

The *onReply()* method adds an event listener (the *callback*) that will execute if the partner *.on* handler replies to the message with the [*reply()*](#bullwinkle_on_reply) method. The callback takes a single parameter, *message*, which contains the message information, including a *tries* count and a round-trip *latency* float in seconds.

The following example demonstrates how to get real time sensor information with [Rocky](https://github.com/electricimp/rocky) and Bullwinkle:

```squirrel
// Agent Code
#require "Rocky.class.nut:1.2.3"
#require "Bullwinkle.class.nut:2.3.0"

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
#require "Bullwinkle.class.nut:2.3.0"

bull <- Bullwinkle();

i2c <- hardware.i2c89;
i2c.configure(CLOCK_SPEED_400_KHZ);
tempHumid <- Si702x(i2c);

bull.on("temp", function(message, reply){
    local result = tempHumid.read();
    reply(result);
});
```

<div id="onfailcallback"><h3>onFail(<i>callback</i>)</h3></div>

The *onFail()* method adds an event listener (the *callback*) that will execute if the partner application does not have a handler for the specified message name, or if the partner fails to respond within a specified period of time (the [*messageTimeout*](#bullwinkle_options)). The callback method requires three parameters: *err*, *message* and *retry*.  If *onFail()* is used the *autoRetry* setting will not be envoked.  To resend the message you must use the *retry* callback parameter.

The *err* parameter describes the error, and will either be `BULLWINKLE_ERR_NO_HANDLER` (in the event the partner application does not have a handler for the specified message name), or `BULLWINKLE_ERR_NO_RESPONSE` (in the event the partner application fails to respond in the specified timeout period).

The *message* parameter contains the failed message, including a *tries* count and a *latency* float in seconds.

The *retry* parameter is a method that can be invoked to retry sending the message in a specified period of time. This method must be called synchronously if it is to be called at all. If the *retry()* method is not called the message will be expired.

```squirrel
bull.send("importantMessage")
    .onFail(function(err, message, retry) {
        // Try sending the message again in 60 seconds
        if (!retry(60)) {
            server.error("No more retry attempts are allowed");
        }
    }).onReply(function(message) {
        server.log("Done!");
    });
```

<div id="retrytimeout"><h4>retry(<i>[timeout]</i>)</h4></div>

The *retry()* method is passed into onFail handler, and can be used to try sending the failed message again after the specified timeout has elapsed. If no timeout is specified, the retry message will use the default [retryTimeout](#bullwinkle_options) setting. If the maximum number of retries have been attempted then this function will return `false` and no more retries will be attempted, otherwise it will return `true`. See [onFail](#onfailcallback) for example usage.

## License

Bullwinkle is licensed under the [MIT License](./LICENSE).
