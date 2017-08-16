// Use this file to write queries to test your data connector
let
    result = Meetup.Contents("London-PUG"){[Key="Events"]}[Data]
    in
        result 