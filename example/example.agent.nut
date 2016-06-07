#require "Rocky.class.nut:1.2.3"
#require "Bullwinkle.class.nut:2.3.0"

// Create the Rocky application
app <- Rocky();
// Create the Bullwinkle application
bull <- Bullwinkle();

// Setup a handler for the agent's root URL
app.get("/", function(context) {
    context.send({ "message": "Hello World!" });
});

// When we get a request to /temp
app.get("/temp", function(context) {
    // Send a request for the temperature
    bull.send("temp")
        .onReply(function(message) {
            // When we get a reply, send a response with the data
            context.send(message.data);
        })
        .onFail(function(err, message, retry) {
            // If it failed, send a 500 response with the error
            context.send(500, { "error": err });
        });
});
