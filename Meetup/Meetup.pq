// Meetup Trademark guidelines https://www.meetup.com/help/article/1744546/ 
// This custom connector is not intended for sale

section Meetup;

[DataSource.Kind="Meetup", Publish="Meetup.Publish"]
 shared Meetup.Contents = Value.ReplaceType ( Meetup.Navigation, ConnectorParams);

 ConnectorParams = type function (
 group_url as (type text meta [
   Documentation.FieldCaption = "The url part name of your Meetup group",
   Documentation.SampleValues = {"Vancouver-Power-BI-User-Group"} ]) ) as 
   table meta [Documentation.Name = "Meetup API",
               Documentation.LongDescription = "Returns a table with key Meetup API data",
        Documentation.Examples = {[
            Description = "Returns a table with key Meetup API data",
            Code = "Meetup.Contents() ",
            Result = "A table with key Meetup API data"]}]; 

 Meetup.Navigation = ( group_url as text) =>
       let
        objects = #table(
            {"Name",       "Key",  "Data",                "ItemKind", "ItemName", "IsLeaf"},{
             {"Group",   "Group",  GroupInfo(group_url)  , "Table",    "Table",    true},
            {"Members",   "Members",  GetAllPagesByNextLink( GroupMembersUrl(group_url) ) , "Table",    "Table",    true},
             {"Events",   "Events", GetAllPagesByNextLinkV3 ( GroupEvents(group_url)  ), "Table",    "Table",    true}
        }),
        NavTable = Table.ToNavigationTable(objects, {"Key"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        NavTable;


GroupEvents = (group_url as text) as text  =>
    let 
        apiKey = Extension.CurrentCredential()[Key],
        Headers =  [format="json",
          page="50",
          status = "past,upcoming",
          key=  apiKey],
       url = "https://api.meetup.com/" & group_url & "/events"  &"?"&  Uri.BuildQueryString( Headers)  
        in
            url; 
            
GroupInfo = (group_url as text) as table =>
    let 
        apiKey = Extension.CurrentCredential()[Key],
        Headers =  [format="json", 
          key=  apiKey],
       response = Json.Document(Web.Contents("https://api.meetup.com", 
                 [RelativePath = group_url])),
       toTable = Table.FromRecords ( {response}),
       dataTypes =  Table.TransformColumnTypes(toTable,{{"id", Int64.Type}, {"name", type text}, {"status", type text}, {"link", type text}, {"urlname", type text}, {"description", type text}, {"country", type text}, {"city", type text}, {"localized_country_name", type text}, {"localized_location", type text}, {"join_mode", type text}, {"visibility", type text}, {"who", type text}, {"timezone", type text}, {"members", Int64.Type}, {"lon", type number}, {"lat", type number}, {"state", type text}}),
    output = Table.TransformColumns(dataTypes, {{"created", each #datetime(1970,1,1,0,0,0)+#duration(0,0,0,_/1000), type datetime}})
        in
            output; 

GroupMembersUrl= (group_url as text) as text =>
    let
        apiKey = Extension.CurrentCredential()[Key],
        Headers =  [group_urlname= group_url, 
          format="json", 
          page="200",
          key=  apiKey],
       url = Uri.Combine("https://api.meetup.com","2/members") &"?"&  Uri.BuildQueryString( Headers)                                                                                              
    in
        url;

// Data Source Kind description
Meetup = [
    Authentication = [
        Key = []
    ]
];

// Data Source UI publishing description
Meetup.Publish = [
    Beta = true,
    Category = "Other",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://powerbi.microsoft.com/",
    SourceImage = Meetup.Icons,
    SourceTypeImage = Meetup.Icons
];

Meetup.Icons = [
    Icon16 = { Extension.Contents("Meetup16.png"), Extension.Contents("Meetup20.png"), Extension.Contents("Meetup24.png"), Extension.Contents("Meetup32.png") },
    Icon32 = { Extension.Contents("Meetup32.png"), Extension.Contents("Meetup40.png"), Extension.Contents("Meetup48.png"), Extension.Contents("Meetup64.png") }
];

/////////// Functions for pagination

// The getNextPage function takes a single argument and is expected to return a nullable table
Table.GenerateByPage = (getNextPage as function) as table =>
    let        
        listOfPages = List.Generate(
            () => getNextPage(null),            // get the first page of data
            (lastPage) => lastPage <> null,     // stop when the function returns null
            (lastPage) => getNextPage(lastPage) // pass the previous page to the next function call
        ),
        // concatenate the pages together
        firstRow = listOfPages{0}?
    in
        // if we didn't get back any pages of data, return an empty table
        // otherwise set the table type based on the columns of the first page
        if (firstRow = null) then
            Table.FromRows({})
        else        
              Table.Combine(listOfPages) 
            ;

// Read all pages of data.
// After every page, we check the "NextLink" record on the metadata of the previous request.
// Table.GenerateByPage will keep asking for more pages until we return null.
GetAllPagesByNextLink = (url as text) as table =>
    Table.GenerateByPage((previous) => 
        let
            // if previous is null, then this is our first page of data
            nextLink = if (previous = null) then url else Value.Metadata(previous)[NextLink]?,
            // if NextLink was set to null by the previous call, we know we have no more data
            page = if (nextLink <> null and nextLink <> "") then GetPage(nextLink) else null
        in
            page
    );

//// Function to get the pages based on the API v3
GetAllPagesByNextLinkV3 = (url as text) as table =>
    Table.GenerateByPage((previous) => 
        let
            // if previous is null, then this is our first page of data
            nextLink = if (previous = null) then url else Value.Metadata(previous)[NextLink]?,
            // if NextLink was set to null by the previous call, we know we have no more data
            page = if (nextLink <> null and nextLink <> "") then GetPageV3(nextLink) else null
        in
            page
    );

GetPage = (url as text) as table =>
    let
        response = Web.Contents(url),
        body = Json.Document(response),
        nextLink = GetNextLink(body),
        dataHeaders = Record.FieldNames ( Record.Combine( body[results]) ),
        data =  Table.FromList( body[results], Splitter.SplitByNothing(), {"Column1"}),
        dataToTable =  Table.ExpandRecordColumn( data, "Column1", dataHeaders),
        path = Record.Field( Uri.Parts(url), "Path")               
    in
        if Text.Split(path, "/"){2} = "members" then MembersDataTypes(dataToTable) meta [NextLink = nextLink] else 
                    if Text.Split(path, "/"){2} = "events" then EventsDataTypes(dataToTable) meta [NextLink = nextLink] else null;

//// Function to get the query a page and create the correct response
GetPageV3 = (url as text) as table =>
    let
        response = Web.Contents(url),
        body = Json.Document(response),
        nextLink = GetNextLinkV3(response),
        dataHeaders = Record.FieldNames ( Record.Combine(body) ),
        data =  Table.FromList( body, Splitter.SplitByNothing(), {"Column1"}),
        dataToTable =  Table.ExpandRecordColumn( data, "Column1", dataHeaders) as table,
        path = Record.Field( Uri.Parts(url), "Path")
    in
        if Text.Split(path, "/"){2} = "members" then MembersDataTypes(dataToTable) meta [NextLink = nextLink] else 
                    if Text.Split(path, "/"){2} = "events" then EventsDataTypes(dataToTable) meta [NextLink = nextLink] else null;

// In this implementation, 'response' will be the parsed body of the response after the call to Json.Document.
// We look for the '@odata.nextLink' field and simply return null if it doesn't exist.
GetNextLink = (response) as nullable text => Record.FieldOrDefault(response, "meta")[next]?;

//// Function to get the next events based on the API v3 of Meetup
GetNextLinkV3 = (response) as nullable text =>
    let
        // extract the "Link" header if it exists
        link =  Record.Field( Value.Metadata(response), "Headers")[Link]? ,
        links = Text.Split(link, ","),
        splitLinks = List.Transform(links, each Text.Split(Text.Trim(_), ";")),
        next = List.Select(splitLinks, each Text.Trim(_{1}) = "rel=""next"""),
        first = List.First(next),
        removedBrackets = try Text.Range(first{0}, 1, Text.Length(first{0}) - 2) otherwise null
    in
        removedBrackets ;


Table.ToNavigationTable = (
    table as table,
    keyColumns as list,
    nameColumn as text,
    dataColumn as text,
    itemKindColumn as text,
    itemNameColumn as text,
    isLeafColumn as text
) as table =>
    let
        tableType = Value.Type(table),
        newTableType = Type.AddTableKey(tableType, keyColumns, true) meta 
        [
            NavigationTable.NameColumn = nameColumn, 
            NavigationTable.DataColumn = dataColumn,
            NavigationTable.ItemKindColumn = itemKindColumn, 
            Preview.DelayColumn = dataColumn, 
            NavigationTable.IsLeafColumn = isLeafColumn
        ],
        navigationTable = Value.ReplaceType(table, newTableType)
    in
        navigationTable;

/////// Defining Data Types functions

EventsDataTypes = (input as table) as table =>
    let
        OriginalColumnNames = Table.ColumnNames(input),
        HardCodedKnownColumns = {"id","name","status","link","description","visibility","duration","yes_rsvp_count","waitlist_count","utc_offset"},
        ColumnsToExpand = List.Distinct( List.Combine({OriginalColumnNames, HardCodedKnownColumns})),
        TableToTable = #table({"Column1"},{{input}}),
        ExpandColumns = Table.ExpandTableColumn(TableToTable, "Column1", ColumnsToExpand),
        #"Changed Type" = Table.TransformColumnTypes(ExpandColumns,{{"id", Int64.Type}, {"name", type text}, {"status", type text}, {"link", type text}, {"description", type text}, {"visibility", type text}, {"duration", Int64.Type}, {"yes_rsvp_count", Int64.Type}, {"waitlist_count", Int64.Type}, {"utc_offset", Int64.Type}}),
    epochConversion = Table.TransformColumns(#"Changed Type", {{"created", each #datetime(1970,1,1,0,0,0)+#duration(0,0,0,_/1000), type datetime}, {"time", each #datetime(1970,1,1,0,0,0)+#duration(0,0,0,_/1000), type datetime}, {"updated", each #datetime(1970,1,1,0,0,0)+#duration(0,0,0,_/1000), type datetime}})
    in
        epochConversion;

MembersDataTypes = (input as table) as table => 
    let
        OriginalColumnNames = Table.ColumnNames(input),
        HardCodedKnownColumns = {"bio","joined","hometown","status","state","visited","name","link","city","country","lat","lon","id"},
         ColumnsToExpand = List.Distinct( List.Combine({OriginalColumnNames, HardCodedKnownColumns})),
         TableToTable = #table({"Column1"},{{input}}),
         ExpandColumns = Table.ExpandTableColumn(TableToTable, "Column1", ColumnsToExpand),
        #"Changed Type" =  Table.TransformColumnTypes(ExpandColumns,{{"bio", type text},{"joined", type number}, {"hometown", type text}, {"status", type text}, {"state", type text}, {"visited",  type number}, {"name", type text}, {"link", type text}, {"city", type text}, {"country", type text}, {"lat", type number}, {"lon", type number},{"id", Int64.Type}}),
    #"Reordered Columns" = Table.ReorderColumns(#"Changed Type",{"country", "city", "topics", "joined", "link", "other_services", "name", "visited", "self", "id", "state", "lat", "lon", "status", "photo", "hometown", "bio"}),
   epochConversion = Table.TransformColumns(#"Reordered Columns",{{"joined", each #datetime(1970,1,1,0,0,0)+#duration(0,0,0,_/1000), type datetime}, {"visited", each #datetime(1970,1,1,0,0,0)+#duration(0,0,0,_/1000), type datetime}})
        in
        epochConversion;
