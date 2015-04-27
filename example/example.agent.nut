#require "Bullwinkle.class.nut:1.0.0"

// Copyright (c) 2015 Electric Imp
// This file is licensed under the MIT License
// http://opensource.org/licenses/MIT

/******************************** Sample Code ********************************/

bullwinkle <- Bullwinkle();
bullwinkle.set_timeout(5);  // bullwinkle will wait for an ack for up to 5 seconds before retrying
bullwinkle.set_retries(3);  // bullwinkle will retry 3 times before considering a message "failed"

// we can use .send and .on in the same way as agent/device.send/on
bullwinkle.on("testMessage", function(context) {
    // pull out the data
    local data = context.params;

    // log the data
    server.log(http.jsonencode(data));
});

// fetch "live data" from device in an http handler:
http.onrequest(function(req, resp) {
    if (req.path == "/temp") {
        // fetch the current temperature from the device, then return:
        bullwinkle.send("getTemp", null)
            .onreply(function(context) {
                server.log("got a getTemp reply: " + context.reply);

                // when we get a reply, send the response to the http client
                resp.send(200, http.jsonencode({ temp = context.reply }));
            })
            .ontimeout(function(context) {
                // if it timed out, send a timeout response
                resp.send(500, "Internal Server Error: Device timed out after " + context.latency + " seconds");
            })
            .onerror(function(context) {
                // if there was an error getting the temp from the device, return the error
                resp.send(500, "Internal Server Error: " + context.exception);
            })
    }
    else {
        resp.send(200, "OK");
    }
});

server.log("Browse to " + http.agenturl() + "/temp");
