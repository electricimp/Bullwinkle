#require "Bullwinkle.class.nut:1.0.0"

// Copyright (c) 2015 Electric Imp
// This file is licensed under the MIT License
// http://opensource.org/licenses/MIT

/******************************** Sample Code ********************************/

bullwinkle <- Bullwinkle();
bullwinkle.set_timeout(5);  // bullwinkle will wait for an ack for up to 5 seconds before retrying
bullwinkle.set_retries(3);  // bullwinkle will retry 3 times before considering a message "failed"


// we can use .send and .on in the same way as agent/device.send/on
bullwinkle.send("testMessage", { a = 1, b = 2, c = "3"});


temp <- 23.0; // make some fake data
bullwinkle.on("getTemp", function(context) {
    server.log("got a getTemp message")

    // send the temperature as the response
    context.reply(temp);
})
