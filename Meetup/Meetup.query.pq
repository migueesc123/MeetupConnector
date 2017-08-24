// Use this file to write queries to test your data connector
let
    result = Meetup.Contents("power-bi-manchester-meetup"){[Key="Group"]}[Data]
    in
        result 