local Bus         = require("reactive/observable/bus")
local Ev          = require("reactive/event")
local EventStream = require("reactive/observable/event-stream")
local Observable  = require("reactive/observable")
local Property    = require("reactive/observable/property")
local Reply       = require("reactive/reply")
local readonly    = require("readonly")

--
-- A reactive programming framework, heavily inspired by Bacon.js
-- (https://baconjs.github.io/)
--
return readonly {
    Bus         = Bus,
    EventStream = EventStream,
    End         = Ev.End,
    Error       = Ev.Error,
    Event       = Ev.Event,
    Initial     = Ev.Initial,
    Next        = Ev.Next,
    NoValue     = Ev.NoValue,
    Observable  = Observable,
    Property    = Property,
    Value       = Ev.Value,
    noMore      = Reply.noMore,
}, true
