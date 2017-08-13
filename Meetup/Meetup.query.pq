// Use this file to write queries to test your data connector
let
    result = Value.Metadata(Meetup.GetPageV3 ("https://api.meetup.com/Club-Power-BI/events?page=2&status=past,upcoming&key=666024583e466b226a19112d696e756c"))
in
    result