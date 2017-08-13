// Use this file to write queries to test your data connector
let
    result = GetPage("https://api.meetup.com/2/members?offset=6&format=json&group_urlname=Vancouver-Power-BI-User-Group&page=40&key=666024583e466b226a19112d696e756c&order=name")
in
    result