// Meetup Trademark guidelines https://www.meetup.com/help/article/1744546/ 
// This custom connector is not intended for sale

section Meetup;

[DataSource.Kind="Meetup", Publish="Meetup.Publish"]
 shared Meetup.Contents = Value.ReplaceType ( Meetup.Navigation, ConnectorParams);

 ConnectorParams = type function (
 group_url as (type text meta [
   Documentation.FieldCaption = "The url part name of your Meetup group",
   Documentation.SampleValues = {"Vancouver-Power-BI-User-Group"} ]) ) as table; 

 Meetup.Navigation = ( group_url as text) =>
       let
        objects = #table(
            {"Name",       "Key",  "Data",                "ItemKind", "ItemName", "IsLeaf"},{
            {"Members",   "Members",  GetAllPagesByNextLink( GroupMembersUrl(group_url) ) , "Table",    "Table",    true}
        }),
        NavTable = Table.ToNavigationTable(objects, {"Key"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        NavTable;
 

GroupMembersUrl= (group_url as text) as text =>
    let
        apiKey = Extension.CurrentCredential()[Key],
        Headers =  [group_urlname= group_url, 
          format="json", 
          page="40",
          key=  apiKey],
       url = Uri.Combine("https://api.meetup.com","2/members") &"?"&  Uri.BuildQueryString( Headers)                                                                                              
    in
        url;

// Data Source Kind description
Meetup = [
    Authentication = [
        Key = []
    ],
    Label = Extension.LoadString("DataSourceLabel")
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
        tableOfPages = Table.FromList(listOfPages, Splitter.SplitByNothing(), {"Column1"}),
        firstRow = tableOfPages{0}?
    in
        // if we didn't get back any pages of data, return an empty table
        // otherwise set the table type based on the columns of the first page
        if (firstRow = null) then
            Table.FromRows({})
        else        
            Value.ReplaceType(
                Table.ExpandTableColumn(tableOfPages, "Column1", Table.ColumnNames(firstRow[Column1])),
                Value.Type(firstRow[Column1])
            );

// Read all pages of data.
// After every page, we check the "NextLink" record on the metadata of the previous request.
// Table.GenerateByPage will keep asking for more pages until we return null.
GetAllPagesByNextLink = (url as text) as table =>
    Table.GenerateByPage((previous) => 
        let
            // if previous is null, then this is our first page of data
            nextLink = if (previous = null) then url else Value.Metadata(previous)[NextLink]?,
            // if NextLink was set to null by the previous call, we know we have no more data
            page = if (nextLink <> null) then GetPage(nextLink) else null
        in
            page
    );
 DefaultRequestHeaders = 
         [format="json",
          key = Extension.CurrentCredential()[Key]];


GetPage = (url as text) as table =>
    let
        response = Web.Contents(url),        
        body = Json.Document(response),
        nextLink = GetNextLink(body),
        data = Table.FromRecords(body[results])
    in
        data meta [NextLink = nextLink];

// In this implementation, 'response' will be the parsed body of the response after the call to Json.Document.
// We look for the '@odata.nextLink' field and simply return null if it doesn't exist.
GetNextLink = (response) as nullable text => Record.FieldOrDefault(response, "meta")[next]?;


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