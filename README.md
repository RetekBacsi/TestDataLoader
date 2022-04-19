# TestDataLoader
TestDataLoader is a small utility for loading test data from an XML resource for Salesforce Unit Tests.

## Introduction

Creating complex test data structures can be a challenge. When you have to create multiple records with various 
relations you often need to choose between readability and minimizing number of DML statements. 
This utility addresses this issue by moving the data into an XML static resource and let the code decide the order of 
DML operations. 

You can specify the records in a grouping most logical to the test layouts 
(e.g. an account, then the related contacts, then another account, more contact etc.)
The utility will group the records by types, and order them by dependencies. Thus minimizing the number of DML operations. 
In the above example the two accounts will be inserted first, then resolves the account dependencies and insert the contacts.
This way it'll only use 2 DML statements.

The code is already used in a few complex projects and saved us a lot of time. 

(Also it is possible  to delegate test data creation to non-developers, which can be a great help for regressions)

## Why use this over Test.loadData?

1. Organize test data by the function, not by data types. You can have a single static resouce per test class where you 
  set up a complex scenario with different object types. It is easier to understand than several different fiels.

2. Refer profiles/roles/recordtypes etc without hardcoding ids (which can break between sandboxes)

3. Control over Date values. Let's say you have a requirement to do something with records where a date custom field's 
  value in the next 7 days. Here you can set it to "TODAY + 3 DAYS", while with the standard loader the hard-coded 
  values will expire and your tests will fail after a time.

4. Circular dependencies. Let's say you have an Account, a list of Contacts, and the Account has a "Main Contact" 
  lookup. With the standard loader this is not possible.

5. The tool will figure out the dependency order*. You can define your data in any order rather than keeping in mind 
  what needs to be loaded first. This results in more readable test data in my experience. 
  (* for circular references it requires hints)

6. No need to keep the same type of objects together. You can define the test data in an order that expresses your 
  scenario. The library will group the objects and do only one insert per object type.

7. It's easy to find a specific test record. By using the PK attribute and the `getIdForPk` method you can get 
  the Id of a given without running queries. See example below.

## How to use
- Add the above code to your org.
- Create an XML file with your data (see examples below), and upload it as a static resource.
- Use the following snippet ():
```` javascript
TestDataLoader tdl = new TestDataLoader();
tdl.log = false;
tdl.load('MyTestData');
````

### Loading data from multiple files
```` javascript
TestDataLoader tdl = new TestDataLoader();
// Data loader logs verbosely. This is useful when finding issues with a data file, 
// but might be overkill for later runs
tdl.log = false;
tdl.init();
tdl.parse('file1'); 
tdl.parse('file2');
tdl.parse('file3');
// No query or DML happens until this point.
tdl.finish(); 
````

### Loading data in multiple passes
This is required when you need the result of triggers/automations run on the previous pass 
```` javascript
TestDataLoader tdl = new TestDataLoader();
tdl.log = false;
tdl.load('MyTestData');
tdl.append('OtherTestData');
````

### Referring to loaded data
Use the `getIdForPk` method to get the Id of an inserted record. This method uses internal structures and does not execute any queries.
example:

#### Data.xml
````xml
<Account pk="someAccount">
    <Name>Acme Corp</Name>
</Account>
````

#### Test Code
````javascript
  Id acmeAccount = tdl.getIdForPk('someAccount');
````

## Datafile Examples
(see the *examples* folder for more)
### Simple reference
````xml
<?xml version="1.0" encoding="UTF-8"?>
<dataset>
    <Account pk="acme">
        <Name>Hello</Name>
        <Account_Custom_Field__c>CustomValue</Account_Custom_Field__c>
    </Account>
    <Contact>
        <AccountId ref="acme"/>
        <FirstName>John</FirstName>
        <LastName>Doe</LastName>
        <Email>johndoe@example.com</Email>
    </Contact>
</dataset>
````

### Datafile Reference
- `dataset` - the root tag of the XML
- SObjects are represented by tags of the same name. They must be at the first level below the root. (`<Account></Account>`, `<Custom_Object__c></Custom_Object__c>`)
- Fields are represented by child tags of the SObject. (`<Pet_s_Name__c>Randee</Pet_s_Name__c`) - Most data types are handled automatically. Only Date/DateTime has special syntax. See below.
- SObject identifiers are defined by a `pk` attribute of the SObject tag. `pk` stands for "Primary Key". (`<MyObject__c pk="goat">`)
- References are specified by a `ref` attribute of a field tag. (`<Favorite_Pet__c ref="goat"/>`) 
  - Special references: certain attributes reference existing data in the system that's static across test runs. (e.g. record types, profiles etc):
    - Object Level attributes:
      - `recordType` - specifies a record type either by Developer Name or Name  (`<Account recordType="BusinessAccount"/>`)
      - `profile` -an existing profile (`<User profile="Standard User">`)
      - `userRole` - an existing user role (`<User userRole="CEO">`)
      - `abstract` - this definition should not be persisted. Only makes sense when used together with `template` (`<Account template="true" abstract="true" />`)
      - `template` - define default values for an object type. Especially useful for creating users. (`<Account template="true" abstract="true" />`)
      - `hierarchy` - use this to define the owner of a hierarchical custom setting
      - `permissionset` - reference to an existing permission set (`<PermissionSetAssignment permissionset='Enable_Goat_Shaving'>`)
      - `permissionsetLicense` - reference to an existing permission set license (`<PermissionSetLicenseAssign permissionsetLicense="GOAT_PermLicense">`)
      - `pk` - define a Primary Key for this record. Must be unique. (`<Contact pk="johndoe">`)
    - Field level attributes:
      - `ref` - references an existing primary key (`<My_friend__c ref="johndoe" />`)
      - `deferred` - used to solve circular references. Deferred relations are not resolved at insert time, but on a separate phase. 
        ```` xml
        <Human__c pk="human1">
          <My_Goat__c ref="goat1"/>
        </Human__c>
        <Goat__c pk="goat1">
          <My_Human__c ref="human1" deferred="true">
        </Goat__c>
        ````
        This way Goat1 is inserted first, without the My_Human reference. Then Human1 will be inserted with the reference resolved. Finally Goat1 will be updated with the human reference.
      - `rtRef` - references a record type id. For specifying the object's record type use the Object level `recordType` attribute. (`<My_Favorite_Record_Type__c rtRef="SomeRecordType"/>`)
      - `userRef` - references an existing user. For users created with the data loader use the standard pk/ref pair (`<Our_Hero__c userRef="johndoe@example.com">`) 
      - `standardPricebook` - references the id of the standard price book.
        ```` xml
          <PricebookEntry pk="pbeProductSample">
            <Pricebook2Id standardPricebook='true'/>
            <Product2Id ref="product1"/>
            <UnitPrice>200</UnitPrice>
            <IsActive>true</IsActive>
          </PricebookEntry>
        ````
    - Specifying dates/date times - Dates/DateTimes are parsed by the standard `Date.valueOf` or `DateTime.valueOf` function accordingly. For DateTime values there is a fallback for JSON datetime format.
    However, there is a way to use date expressions to specify relative dates. This can be useful if you want to make sure some date is in the future/past at the time of the test.
    The expression syntax is "today (+|-) X (day(s)|month(s)|year(s))"
      ```` xml
        <SomeObject>
          <Date_Field1__c>today + 30 days</Date_Field1__c>
          <Date_Field2__c>today - 1 year</Date_Field2__c>
        </SomeObject>
      ````
  
    
## Public Methods
- `getIdForPk(String pk)` - returns the Id for a given PK. Only valid after load/finish.
- `load(String name)` - Loads and persists a data file. The most used method. A shortcut for `init();parse(file);finish();`
- `append(String name)` - use this to load an extra data file, after loading at least one. This can be used if you need
refer values created by triggers/automations because of the previous loads.
- `init()` - initializes internal structures. Only needed when loading multiple files
- `parse(String name)` - parses a static resource, preparing for insert. It only does syntax checks, no references are resolved, also no DML/SOQL operations.
- `finish()` - persists the parsed resources. This is where the references are resolved and actual DML happens. 


